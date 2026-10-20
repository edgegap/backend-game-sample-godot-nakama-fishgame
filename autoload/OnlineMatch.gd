extends Node

# Online matches run on a dedicated server that Nakama starts on Edgegap
# (see nakama/ and autoload/EdgegapServer.gd):
#
#   client: Nakama matchmaker ticket -> notification with the server address
#           -> ENet connection -> _hello with the Nakama session token
#   server: checks the token with Nakama, then registers the player here
#
# The server is always peer 1 and is not a player.

# For developers to set from the outside, for example:
#   OnlineMatch.max_players = 8
#   OnlineMatch.client_version = 'v1.2'
var min_players := 2
var max_players := 4
var client_version := 'dev'

# Notification codes sent by the Nakama module (nakama/main.go).
const NOTIFICATION_CONNECTION_INFO := 111
const NOTIFICATION_CREATE_TIMEOUT := 112
const NOTIFICATION_CREATE_FAILED := 113

# Nakama variables:
var nakama_socket: NakamaSocket
var matchmaker_ticket: String = ''

var players: Dictionary

enum MatchState {
	LOBBY = 0,
	MATCHING = 1,
	CONNECTING = 2,
	WAITING_FOR_ENOUGH_PLAYERS = 3,
	READY = 4,
	PLAYING = 5,
}
var match_state: int = MatchState.LOBBY: get = get_match_state

enum MatchMode {
	NONE = 0,
	MATCHMAKER = 3,
}
var match_mode: int = MatchMode.NONE: get = get_match_mode

signal error (message)
signal disconnected ()

signal matchmaker_matched ()
signal match_joined (match_id, mode)

signal player_joined (player)
signal player_left (player)

signal match_ready (players)
signal match_not_ready ()

class Player:
	var user_id: String
	var peer_id: int
	var username: String

	func _init(_user_id: String, _username: String, _peer_id: int) -> void:
		user_id = _user_id
		username = _username
		peer_id = _peer_id

	static func from_dict(data: Dictionary) -> Player:
		return Player.new(data['user_id'], data['username'], int(data['peer_id']))

	func to_dict() -> Dictionary:
		return {
			user_id = user_id,
			username = username,
			peer_id = peer_id,
		}

static func serialize_players(_players: Dictionary) -> Dictionary:
	var result := {}
	for key in _players:
		result[key] = _players[key].to_dict()
	return result

static func unserialize_players(_players: Dictionary) -> Dictionary:
	var result := {}
	for key in _players:
		result[int(key)] = Player.from_dict(_players[key])
	return result

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

#####
# Client
#####

func _set_nakama_socket(_nakama_socket: NakamaSocket) -> void:
	if nakama_socket == _nakama_socket:
		return

	if nakama_socket:
		nakama_socket.closed.disconnect(_on_nakama_socket_closed)
		nakama_socket.received_matchmaker_matched.disconnect(_on_nakama_matchmaker_matched)
		nakama_socket.received_notification.disconnect(_on_nakama_notification)

	nakama_socket = _nakama_socket

	if nakama_socket:
		nakama_socket.closed.connect(_on_nakama_socket_closed)
		nakama_socket.received_matchmaker_matched.connect(_on_nakama_matchmaker_matched)
		nakama_socket.received_notification.connect(_on_nakama_notification)

func start_matchmaking(_nakama_socket: NakamaSocket, data: Dictionary = {}) -> void:
	leave()
	_set_nakama_socket(_nakama_socket)
	match_mode = MatchMode.MATCHMAKER

	if data.has('min_count'):
		data['min_count'] = max(min_players, data['min_count'])
	else:
		data['min_count'] = min_players

	if data.has('max_count'):
		data['max_count'] = min(max_players, data['max_count'])
	else:
		data['max_count'] = max_players

	if client_version != '':
		if not data.has('string_properties'):
			data['string_properties'] = {}
		data['string_properties']['client_version'] = client_version

		var query = '+properties.client_version:' + client_version
		if data.has('query'):
			data['query'] += ' ' + query
		else:
			data['query'] = query

	match_state = MatchState.MATCHING
	var result = await nakama_socket.add_matchmaker_async(data.get('query', '*'), data['min_count'], data['max_count'], data.get('string_properties', {}), data.get('numeric_properties', {}))
	if result.is_exception():
		leave()
		emit_signal("error", "Unable to join match making pool")
	elif match_state == MatchState.MATCHING:
		matchmaker_ticket = result.ticket
	else:
		# The player gave up while the ticket was being created.
		nakama_socket.remove_matchmaker_async(result.ticket)

func _on_nakama_matchmaker_matched(_matched) -> void:
	if match_state != MatchState.MATCHING:
		return
	matchmaker_ticket = ''
	emit_signal("matchmaker_matched")

func _on_nakama_notification(notification) -> void:
	if match_state != MatchState.MATCHING:
		return

	match notification.code:
		NOTIFICATION_CONNECTION_INFO:
			var info = JSON.parse_string(notification.content)
			if not info is Dictionary or not info.has('IpAddress') or int(info.get('Port', 0)) == 0:
				leave()
				emit_signal("error", "Got an invalid game server address")
				return
			_connect_to_server(info['IpAddress'], int(info['Port']))
		NOTIFICATION_CREATE_TIMEOUT:
			leave()
			emit_signal("error", "Timed out starting a game server")
		NOTIFICATION_CREATE_FAILED:
			leave()
			emit_signal("error", "Unable to start a game server")

# Also used for local testing: connect straight to a server without Nakama's matchmaker.
func connect_to_server(host: String, port: int) -> void:
	leave()
	match_mode = MatchMode.MATCHMAKER
	_connect_to_server(host, port)

func _connect_to_server(host: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		leave()
		emit_signal("error", "Unable to connect to the game server")
		return
	multiplayer.multiplayer_peer = peer
	match_state = MatchState.CONNECTING

func _on_connected_to_server() -> void:
	var token := ''
	if Online.nakama_session:
		token = Online.nakama_session.token
	rpc_id(1, "_hello", token, client_version)

func _on_connection_failed() -> void:
	leave()
	emit_signal("error", "Unable to connect to the game server")

func _on_server_disconnected() -> void:
	leave()
	emit_signal("disconnected")

@rpc("authority", "call_remote", "reliable")
func _welcome(players_data: Dictionary) -> void:
	players = unserialize_players(players_data)
	emit_signal("match_joined", '', match_mode)
	_check_enough_players()

@rpc("authority", "call_remote", "reliable")
func _remote_player_joined(player_data: Dictionary) -> void:
	var player = Player.from_dict(player_data)
	players[player.peer_id] = player
	emit_signal("player_joined", player)
	_check_enough_players()

@rpc("authority", "call_remote", "reliable")
func _boot_with_error(msg: String) -> void:
	leave()
	emit_signal("error", msg)

#####
# Server
#####

@rpc("any_peer", "call_remote", "reliable")
func _hello(token: String, version: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()

	if version != client_version:
		_boot(peer_id, "Client version doesn't match the server")
		return
	if match_state == MatchState.PLAYING:
		_boot(peer_id, "Sorry! The match has already begun.")
		return
	if players.size() >= max_players:
		_boot(peer_id, "Sorry! The match is full.")
		return

	var account: Dictionary = await EdgegapServer.verify_player(token)
	if account.is_empty():
		_boot(peer_id, "This game server is reserved for other players.")
		return
	if not multiplayer.get_peers().has(peer_id):
		return
	for other in players.values():
		if other.user_id == account['user_id']:
			_boot(peer_id, "You are already connected to this match.")
			return

	var player := Player.new(account['user_id'], account['username'], peer_id)
	players[peer_id] = player

	rpc_id(peer_id, "_welcome", serialize_players(players))
	for other_peer_id in players:
		if other_peer_id != peer_id:
			rpc_id(other_peer_id, "_remote_player_joined", player.to_dict())

	emit_signal("player_joined", player)
	_check_enough_players()

func _boot(peer_id: int, msg: String) -> void:
	rpc_id(peer_id, "_boot_with_error", msg)
	# Give the message time to arrive before dropping the connection.
	await get_tree().create_timer(1.0).timeout
	if multiplayer.multiplayer_peer and multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)

func start_playing() -> void:
	assert(match_state == MatchState.READY)
	match_state = MatchState.PLAYING

#####
# Both
#####

func leave(close_socket: bool = false) -> void:
	# The dedicated server keeps its ENet server until EdgegapServer stops it.
	if EdgegapServer.active:
		return

	var ticket := matchmaker_ticket
	var socket := nakama_socket

	# Initialize all the variables to their default state first, so a caller
	# that starts a new match right away isn't reset by the awaits below.
	matchmaker_ticket = ''
	players = {}
	match_state = MatchState.LOBBY
	match_mode = MatchMode.NONE

	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	if socket:
		if ticket:
			await socket.remove_matchmaker_async(ticket)
		if close_socket:
			socket.close()
			_set_nakama_socket(null)

func get_match_mode() -> int:
	return match_mode

func get_match_state() -> int:
	return match_state

func get_player_names_by_peer_id() -> Dictionary:
	var result = {}
	for peer_id in players:
		result[peer_id] = players[peer_id].username
	return result

func _on_nakama_socket_closed() -> void:
	# Once a player is on the game server, Nakama's socket is no longer needed.
	if match_state in [MatchState.LOBBY, MatchState.MATCHING]:
		leave()
		emit_signal("disconnected")
	_set_nakama_socket(null)

func _check_enough_players() -> void:
	if players.size() >= min_players:
		match_state = MatchState.READY;
		emit_signal("match_ready", players)
	else:
		match_state = MatchState.WAITING_FOR_ENOUGH_PLAYERS
		emit_signal("match_not_ready")

func _on_peer_disconnected(peer_id: int) -> void:
	var player = players.get(peer_id)
	if player != null:
		players.erase(peer_id)
		emit_signal("player_left", player)

	if match_state != MatchState.PLAYING:
		_check_enough_players()
