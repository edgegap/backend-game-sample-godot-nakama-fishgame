extends Node

# Nakama connection settings. The defaults match the local Nakama started by
# nakama/docker-compose.yml. Override them with "-- --nakama-host=..." style
# arguments or the NAKAMA_HOST / NAKAMA_PORT / NAKAMA_SCHEME / NAKAMA_SERVER_KEY
# environment variables.
var nakama_server_key: String = 'defaultkey'
var nakama_host: String = 'localhost'
var nakama_port: int = 7350
var nakama_scheme: String = 'http'

# For other scripts to access:
var nakama_client: NakamaClient: get = get_nakama_client
var nakama_session: NakamaSession: set = set_nakama_session
var nakama_socket: NakamaSocket

# Internal variable for initializing the socket.
var _nakama_socket_connecting := false

signal session_changed (nakama_session)
signal session_connected (nakama_session)
signal socket_connected (nakama_socket)

func _ready() -> void:
	# Don't stop processing messages from Nakama when the game is paused.
	Nakama.process_mode = Node.PROCESS_MODE_ALWAYS

	nakama_server_key = Util.get_setting("nakama-server-key", "NAKAMA_SERVER_KEY", nakama_server_key)
	nakama_host = Util.get_setting("nakama-host", "NAKAMA_HOST", nakama_host)
	nakama_port = int(Util.get_setting("nakama-port", "NAKAMA_PORT", str(nakama_port)))
	nakama_scheme = Util.get_setting("nakama-scheme", "NAKAMA_SCHEME", nakama_scheme)

func get_nakama_client() -> NakamaClient:
	if nakama_client == null:
		nakama_client = Nakama.create_client(
			nakama_server_key,
			nakama_host,
			nakama_port,
			nakama_scheme,
			Nakama.DEFAULT_TIMEOUT,
			NakamaLogger.LOG_LEVEL.ERROR)

	return nakama_client

func set_nakama_session(_nakama_session: NakamaSession) -> void:
	nakama_session = _nakama_session

	emit_signal("session_changed", nakama_session)

	if nakama_session and not nakama_session.is_exception() and not nakama_session.is_expired():
		emit_signal("session_connected", nakama_session)

func connect_nakama_socket() -> void:
	if is_nakama_socket_connected():
		return
	if _nakama_socket_connecting:
		return
	_nakama_socket_connecting = true

	var new_socket = Nakama.create_socket_from(nakama_client)
	await new_socket.connect_async(nakama_session)
	nakama_socket = new_socket
	_nakama_socket_connecting = false

	emit_signal("socket_connected", nakama_socket)

func is_nakama_socket_connected() -> bool:
	return nakama_socket != null && nakama_socket.is_connected_to_host()
