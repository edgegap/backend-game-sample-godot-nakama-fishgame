extends Node

# Dedicated server mode, for Edgegap deployments started by Nakama through
# edgegap/nakama-edgegap. Active when the game runs headless (--headless) or with
# the "-- --server" argument, unless "-- --client" is passed.
#
# The server reports to Nakama with the URLs the plugin injects:
#   NAKAMA_INSTANCE_EVENT_URL    READY once listening, STOP when the match is over
#   NAKAMA_CONNECTION_EVENT_URL  the Nakama user IDs connected right now
#   NAKAMA_INSTANCE_METADATA     what nakama/main.go passed, e.g. the matched user_ids
# and stops itself (STOP makes Nakama stop the Edgegap deployment).

const DEFAULT_PORT := 7777
const NO_PLAYERS_TIMEOUT := 60.0
const MAX_MATCH_DURATION := 20 * 60.0
const CONNECTION_REPORT_INTERVAL := 5.0
const STOP_GRACE_PERIOD := 30.0

var active := false

var instance_id := ''
var instance_event_url := ''
var connection_event_url := ''
# Nakama's address and "?http_key=...&unwrap", taken from the event URLs.
var nakama_url := ''
var _rpc_query := ''
var expected_user_ids: Array = []

var _stopping := false
var _had_players := false
var _connections_dirty := false
var _reported_connections := []

func _ready() -> void:
	active = (DisplayServer.get_name() == "headless" or Util.has_arg("server")) and not Util.has_arg("client")
	if not active:
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	_read_environment()

	var port := int(Util.get_setting("port", "GAME_PORT", str(DEFAULT_PORT)))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, OnlineMatch.max_players)
	if err != OK:
		push_error("Unable to listen on UDP port %d (error %d)" % [port, err])
		await _send_instance_event("ERROR", "Unable to listen on UDP port %d" % port)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	print("Fish Game server listening on UDP port %d (instance '%s')" % [port, instance_id])

	OnlineMatch.player_joined.connect(_on_player_joined)
	OnlineMatch.player_left.connect(_on_player_left)

	var connection_timer := Timer.new()
	connection_timer.wait_time = CONNECTION_REPORT_INTERVAL
	connection_timer.timeout.connect(_report_connections)
	add_child(connection_timer)
	connection_timer.start()

	get_tree().create_timer(NO_PLAYERS_TIMEOUT).timeout.connect(func():
		if not _had_players:
			stop("No players connected within %d seconds" % NO_PLAYERS_TIMEOUT))
	get_tree().create_timer(MAX_MATCH_DURATION).timeout.connect(func():
		stop("Reached the maximum match duration"))

	await _send_instance_event("READY", "Fish Game server is listening", {
		game_server = _game_server_metadata(),
	})

func _read_environment() -> void:
	instance_id = OS.get_environment("ARBITRIUM_REQUEST_ID")
	instance_event_url = OS.get_environment("NAKAMA_INSTANCE_EVENT_URL")
	connection_event_url = OS.get_environment("NAKAMA_CONNECTION_EVENT_URL")

	if instance_event_url != '':
		var rpc_index := instance_event_url.find("/v2/rpc/")
		var query_index := instance_event_url.find("?")
		if rpc_index > 0 and query_index > rpc_index:
			nakama_url = instance_event_url.substr(0, rpc_index)
			_rpc_query = instance_event_url.substr(query_index)
	# For local tests without Edgegap, point the server at Nakama directly.
	nakama_url = Util.get_setting("nakama-url", "NAKAMA_URL", nakama_url)

	var metadata = _parse_env_json("NAKAMA_INSTANCE_METADATA")
	if metadata is Dictionary and metadata.get("user_ids") is Array:
		expected_user_ids = metadata["user_ids"]

	print("Nakama: %s, expected players: %s" % [nakama_url if nakama_url != '' else "(none)", expected_user_ids])

func _game_server_metadata() -> Dictionary:
	var ports_mapping = _parse_env_json("ARBITRIUM_PORTS_MAPPING")
	return {
		ARBITRIUM_REQUEST_ID = instance_id,
		ARBITRIUM_PUBLIC_IP = OS.get_environment("ARBITRIUM_PUBLIC_IP"),
		ARBITRIUM_PORTS_MAPPING = ports_mapping if ports_mapping is Dictionary else {},
	}

func _parse_env_json(env_name: String):
	var value := OS.get_environment(env_name)
	if value == '':
		return null
	return JSON.parse_string(value)

# Checks a Nakama session token with Nakama itself and returns
# { user_id, username }, or {} if the player doesn't belong on this server.
func verify_player(token: String) -> Dictionary:
	if nakama_url == '':
		# Local test without Nakama: anyone may join.
		if instance_id == '':
			var local_id := "local-%d" % randi()
			return { user_id = local_id, username = "Fish %d" % (randi() % 1000) }
		push_error("No Nakama URL to verify players with")
		return {}
	if token == '':
		return {}

	var response := await _http(HTTPClient.METHOD_GET, nakama_url + "/v2/account", ["Authorization: Bearer " + token])
	if response['code'] != 200:
		print("Rejected a player: Nakama returned %d for their session" % response['code'])
		return {}
	var account = JSON.parse_string(response['body'])
	if not account is Dictionary or not account.get("user") is Dictionary:
		return {}
	var user: Dictionary = account["user"]
	if expected_user_ids.size() > 0 and not expected_user_ids.has(user.get("id", "")):
		print("Rejected user %s: not matched to this server" % user.get("id", ""))
		return {}
	return { user_id = user["id"], username = user.get("username", "Fish") }

# The match is won: record the win in Nakama, then stop the server.
func finish_match(winner_user_id: String) -> void:
	if _stopping:
		return
	if nakama_url != '' and _rpc_query != '' and winner_user_id != '':
		var user_ids := []
		for player in OnlineMatch.players.values():
			user_ids.append(player.user_id)
		var response := await _http(HTTPClient.METHOD_POST, nakama_url + "/v2/rpc/report_match_result" + _rpc_query, ["Content-Type: application/json"], JSON.stringify({
			instance_id = instance_id,
			winner_user_id = winner_user_id,
			user_ids = user_ids,
		}))
		if response['code'] != 200:
			push_error("report_match_result failed (%d): %s" % [response['code'], response['body']])
	stop("Match finished")

# Asks Nakama to stop this deployment, and quits if that doesn't happen.
func stop(reason: String) -> void:
	if _stopping:
		return
	_stopping = true
	print("Stopping: " + reason)

	if instance_event_url == '':
		get_tree().quit()
		return

	await _report_connections()
	await _send_instance_event("STOP", reason)
	await get_tree().create_timer(STOP_GRACE_PERIOD).timeout
	get_tree().quit()

func _on_player_joined(_player) -> void:
	_had_players = true
	_connections_dirty = true

func _on_player_left(_player) -> void:
	_connections_dirty = true
	if OnlineMatch.players.size() == 0:
		stop("All players left")

func _report_connections() -> void:
	if not _connections_dirty or connection_event_url == '':
		return
	_connections_dirty = false
	var user_ids := []
	for player in OnlineMatch.players.values():
		user_ids.append(player.user_id)
	if user_ids == _reported_connections:
		return
	_reported_connections = user_ids
	var response := await _http(HTTPClient.METHOD_POST, connection_event_url, ["Content-Type: application/json"], JSON.stringify({
		instance_id = instance_id,
		connections = user_ids,
	}))
	if response['code'] != 200:
		push_error("Connection event failed (%d): %s" % [response['code'], response['body']])

func _send_instance_event(action: String, message: String, metadata: Dictionary = {}) -> void:
	if instance_event_url == '':
		return
	var response := await _http(HTTPClient.METHOD_POST, instance_event_url, ["Content-Type: application/json"], JSON.stringify({
		instance_id = instance_id,
		action = action,
		message = message,
		metadata = metadata,
	}))
	if response['code'] != 200:
		push_error("%s event failed (%d): %s" % [action, response['code'], response['body']])
	else:
		print("Sent %s to Nakama" % action)

func _http(method: int, url: String, headers: Array, body: String = '') -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	var err := request.request(url, PackedStringArray(headers), method, body)
	if err != OK:
		request.queue_free()
		return { code = 0, body = "request error %d" % err }
	var result: Array = await request.request_completed
	request.queue_free()
	return { code = result[1], body = (result[3] as PackedByteArray).get_string_from_utf8() }
