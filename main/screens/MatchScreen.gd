extends "res://main/Screen.gd"

@onready var matchmaker_player_count_control := $PanelContainer/VBoxContainer/MatchPanel/SpinBox

func _ready() -> void:
	$PanelContainer/VBoxContainer/MatchPanel/MatchButton.connect("pressed", Callable(self, "_on_match_button_pressed").bind(OnlineMatch.MatchMode.MATCHMAKER))

	# Every online match runs on an Edgegap server started by Nakama's
	# matchmaker, so private matches by ID aren't offered.
	$PanelContainer/VBoxContainer/CreatePanel.visible = false
	$PanelContainer/VBoxContainer/JoinPanel.visible = false

	OnlineMatch.connect("matchmaker_matched", Callable(self, "_on_OnlineMatch_matchmaker_matched"))
	OnlineMatch.connect("match_joined", Callable(self, "_on_OnlineMatch_joined"))

func _show_screen(_info: Dictionary = {}) -> void:
	matchmaker_player_count_control.value = 2

func _on_match_button_pressed(mode) -> void:
	# If our session has expired, show the ConnectionScreen again.
	if Online.nakama_session == null or Online.nakama_session.is_expired():
		ui_layer.show_screen("ConnectionScreen", { reconnect = true, next_screen = null })

		# Wait to see if we get a new valid session.
		await Online.session_changed
		if Online.nakama_session == null:
			return

	# Connect socket to realtime Nakama API if not connected.
	if not Online.is_nakama_socket_connected():
		Online.connect_nakama_socket()
		await Online.socket_connected

	ui_layer.hide_message()

	# Call internal method to do actual work.
	match mode:
		OnlineMatch.MatchMode.MATCHMAKER:
			_start_matchmaking()

func _start_matchmaking() -> void:
	var min_players = matchmaker_player_count_control.value

	ui_layer.hide_screen()
	ui_layer.show_message("Looking for match...")

	var data = {
		min_count = min_players,
		string_properties = {
			game = "fish_game",
			engine = "godot",
		},
		query = "+properties.game:fish_game +properties.engine:godot",
	}

	OnlineMatch.start_matchmaking(Online.nakama_socket, data)

func _on_OnlineMatch_matchmaker_matched() -> void:
	ui_layer.show_message("Match found! Starting a game server...")

func _on_OnlineMatch_joined(_match_id: String, _match_mode: int):
	ui_layer.hide_message()
	ui_layer.show_screen("ReadyScreen", {
		players = OnlineMatch.players,
		clear = true,
	})

func _on_PasteButton_pressed() -> void:
	pass

func _on_LeaderboardButton_pressed() -> void:
	ui_layer.show_screen("LeaderboardScreen")
