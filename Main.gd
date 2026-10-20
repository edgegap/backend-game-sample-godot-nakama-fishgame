extends Node2D

@onready var game = $Game
@onready var ui_layer: UILayer = $UILayer
@onready var ready_screen = $UILayer/Screens/ReadyScreen
@onready var music := $Music

const WINS_PER_MATCH := 5

var players := {}

var players_ready := {}
var players_score := {}

var match_started := false

func _ready() -> void:
	OnlineMatch.connect("error", Callable(self, "_on_OnlineMatch_error"))
	OnlineMatch.connect("disconnected", Callable(self, "_on_OnlineMatch_disconnected"))
	OnlineMatch.connect("player_joined", Callable(self, "_on_OnlineMatch_player_joined"))
	OnlineMatch.connect("player_left", Callable(self, "_on_OnlineMatch_player_left"))

	randomize()

	if EdgegapServer.active:
		# Dedicated server: no menus or music, just wait for the players.
		GameState.online_play = true
		ui_layer.hide_all()
		game.reload_map()
		return

	music.play_random()

	# Local testing: skip Nakama and connect straight to a server.
	var connect_address := Util.get_setting("connect")
	if connect_address != '':
		GameState.online_play = true
		game.reload_map()
		ui_layer.hide_all()
		ui_layer.show_back_button()
		ui_layer.show_message("Connecting to %s..." % connect_address)
		var parts := connect_address.split(":")
		OnlineMatch.connect_to_server(parts[0], int(parts[1]) if parts.size() > 1 else EdgegapServer.DEFAULT_PORT)
		await OnlineMatch.match_joined
		ui_layer.hide_message()
		ui_layer.show_screen("ReadyScreen", { players = OnlineMatch.players, clear = true })

#####
# UI callbacks
#####

func _on_TitleScreen_play_local() -> void:
	GameState.online_play = false

	ui_layer.hide_screen()
	ui_layer.show_back_button()

	start_game()

func _on_TitleScreen_play_online() -> void:
	GameState.online_play = true

	# Show the game map in the background because we have nothing better.
	game.reload_map()

	ui_layer.show_screen("ConnectionScreen")

func _on_UILayer_change_screen(name: String, _screen) -> void:
	if name == 'TitleScreen':
		ui_layer.hide_back_button()
	else:
		ui_layer.show_back_button()

	if name != 'ReadyScreen':
		if match_started:
			match_started = false
			music.play_random()

func _on_UILayer_back_button() -> void:
	ui_layer.hide_message()

	stop_game()

	if GameState.online_play:
		OnlineMatch.leave()

	if ui_layer.current_screen_name in ['ConnectionScreen', 'MatchScreen', 'CreditsScreen']:
		ui_layer.show_screen("TitleScreen")
	elif not GameState.online_play:
		ui_layer.show_screen("TitleScreen")
	else:
		ui_layer.show_screen("MatchScreen")

func _on_ReadyScreen_ready_pressed() -> void:
	var my_id := multiplayer.get_unique_id()
	ready_screen.set_status(my_id, "READY!")
	rpc_id(1, "player_ready", my_id)

#####
# OnlineMatch callbacks
#####

func _on_OnlineMatch_error(message: String):
	if message != '':
		ui_layer.show_message(message)
	ui_layer.show_screen("MatchScreen")

func _on_OnlineMatch_disconnected():
	_on_OnlineMatch_error('')

func _on_OnlineMatch_player_left(player) -> void:
	game.kill_player(player.peer_id)

	players.erase(player.peer_id)
	players_ready.erase(player.peer_id)

	if multiplayer.is_server():
		if OnlineMatch.match_state == OnlineMatch.MatchState.PLAYING and OnlineMatch.players.size() < 2:
			EdgegapServer.stop(player.username + " left - not enough players")
		return

	if OnlineMatch.players.size() < 2:
		OnlineMatch.leave()
		_on_OnlineMatch_error(player.username + " has left - not enough players!")
	else:
		ui_layer.show_message(player.username + " has left")

func _on_OnlineMatch_player_joined(player) -> void:
	if multiplayer.is_server():
		# Tell this new player about all the other players that are already ready.
		for ready_peer_id in players_ready:
			rpc_id(player.peer_id, "player_ready", ready_peer_id)

#####
# Gameplay methods and callbacks
#####

@rpc("any_peer", "call_remote", "reliable")
func player_ready(peer_id: int) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	# Players may only mark themselves ready; the server relays it to the others.
	if sender_id != 1 and sender_id != peer_id:
		return

	if not multiplayer.is_server():
		ready_screen.set_status(peer_id, "READY!")
		return

	if not OnlineMatch.players.has(peer_id) or players_ready.has(peer_id):
		return
	players_ready[peer_id] = true
	# Let the other players see it.
	for other_peer_id in OnlineMatch.players:
		if other_peer_id != peer_id:
			rpc_id(other_peer_id, "player_ready", peer_id)

	if players_ready.size() == OnlineMatch.players.size() and players_ready.size() >= OnlineMatch.min_players:
		if OnlineMatch.match_state != OnlineMatch.MatchState.PLAYING:
			OnlineMatch.start_playing()
		start_game()

func start_game() -> void:
	if GameState.online_play:
		players = OnlineMatch.get_player_names_by_peer_id()
	else:
		players = {
			1: "Player1",
			2: "Player2",
		}

	game.game_start(players)

func stop_game() -> void:
	OnlineMatch.leave()

	players.clear()
	players_ready.clear()
	players_score.clear()

	game.game_stop()

func restart_game() -> void:
	stop_game()
	start_game()

func _on_Game_game_started() -> void:
	if EdgegapServer.active:
		return

	ui_layer.hide_screen()
	ui_layer.hide_all()
	ui_layer.show_back_button()

	if not match_started:
		match_started = true
		music.play_random()

func _on_Game_player_dead(peer_id: int) -> void:
	if GameState.online_play and not multiplayer.is_server():
		var my_id = multiplayer.get_unique_id()
		if peer_id == my_id:
			ui_layer.show_message("You lose!")

func _on_Game_game_over(peer_id: int) -> void:
	players_ready.clear()

	if not GameState.online_play:
		show_winner(players[peer_id])
	elif multiplayer.is_server():
		if not players_score.has(peer_id):
			players_score[peer_id] = 1
		else:
			players_score[peer_id] += 1

		var is_match: bool = players_score[peer_id] >= WINS_PER_MATCH

		rpc("show_winner", players[peer_id], peer_id, players_score[peer_id], is_match)

@rpc("authority", "call_local", "reliable")
func show_winner(name: String, peer_id: int = 0, score: int = 0, is_match: bool = false) -> void:
	if EdgegapServer.active:
		if is_match:
			# The server records the win in Nakama, so clients can't fake it.
			var winner = OnlineMatch.players.get(peer_id)
			EdgegapServer.finish_match(winner.user_id if winner else '')
		return

	if is_match:
		ui_layer.show_message(name + " WINS THE WHOLE MATCH!")
	else:
		ui_layer.show_message(name + " wins this round!")

	await get_tree().create_timer(2.0).timeout
	if not game.started:
		return

	if GameState.online_play:
		if is_match:
			stop_game()
			ui_layer.show_screen("MatchScreen")
		else:
			ready_screen.hide_match_id()
			ready_screen.reset_status("Waiting...")
			ready_screen.set_score(peer_id, score)
			ui_layer.show_screen("ReadyScreen")
	else:
		restart_game()

func _on_Music_song_finished(song) -> void:
	if not music.current_song.playing:
		music.play_random()
