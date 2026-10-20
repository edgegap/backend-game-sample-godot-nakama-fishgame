extends SceneTree

# Test client. Either connects straight to a server ("-- --client
# --connect=127.0.0.1:7777") or signs up to Nakama and uses its matchmaker
# ("-- --client --email=someone@example.com" plus the --nakama-* settings). Then
# it presses Ready on every ready screen and logs what it sees until the match
# is over. Pair it with a server started with "-- --test-auto-hit".

var rounds_started := 0
var other_fish_seen := false

func _initialize() -> void:
	var main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	var ui = main.get_node("UILayer")
	var game = main.get_node("Game")

	ui.change_screen.connect(func(screen_name, _screen):
		print("TEST: screen " + screen_name)
		if screen_name == "ReadyScreen":
			_press_ready(main)
		elif screen_name == "MatchScreen" and rounds_started > 0:
			print("TEST: match over after %d rounds, saw the other fish move: %s" % [rounds_started, other_fish_seen])
			# Give the server a moment to record the win.
			await create_timer(3.0).timeout
			await _print_leaderboard()
			quit(0 if rounds_started >= 5 and other_fish_seen else 1))
	game.game_started.connect(func():
		rounds_started += 1
		print("TEST: round %d started with %d fish" % [rounds_started, game.get_node("Players").get_child_count()])
		_watch_other_fish(game))
	root.get_node("OnlineMatch").error.connect(func(msg): print("TEST: error " + msg))

	var timeout := int(_arg("timeout", "120"))
	create_timer(timeout).timeout.connect(func():
		print("TEST: timed out")
		quit(2))

	var email := _arg("email")
	if email != '':
		_matchmake(email)

func _arg(arg_name: String, default: String = '') -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + arg_name + "="):
			return arg.substr(arg_name.length() + 3)
	return default

func _matchmake(email: String) -> void:
	var online = root.get_node("Online")
	var online_match = root.get_node("OnlineMatch")
	var username := email.split("@")[0]
	var session = await online.nakama_client.authenticate_email_async(email, "pw-%d-%d" % [randi(), randi()], username, true)
	if session.is_exception():
		print("TEST: Nakama sign-up failed: " + session.get_exception().message)
		quit(3)
		return
	online.nakama_session = session
	online.connect_nakama_socket()
	await online.socket_connected
	online_match.matchmaker_matched.connect(func(): print("TEST: matchmaker matched, waiting for the server"))
	online_match.start_matchmaking(online.nakama_socket, { min_count = 2 })
	print("TEST: matchmaking as %s (%s)" % [username, session.user_id])

func _print_leaderboard() -> void:
	var online = root.get_node("Online")
	if online.nakama_session == null:
		return
	var result = await online.nakama_client.list_leaderboard_records_async(online.nakama_session, 'fish_game_wins')
	if result.is_exception():
		print("TEST: leaderboard error " + result.get_exception().message)
		return
	for record in result.records:
		print("TEST: leaderboard %s %s" % [record.username, record.score])

func _press_ready(main) -> void:
	await create_timer(0.5).timeout
	print("TEST: ready")
	main._on_ReadyScreen_ready_pressed()

func _watch_other_fish(game) -> void:
	var my_id := root.multiplayer.get_unique_id()
	var mine = game.get_node_or_null("Players/" + str(my_id))
	if mine:
		# Move a little so the other client can see our position change.
		Input.action_press("player1_right")
		await create_timer(0.3).timeout
		Input.action_release("player1_right")
	for fish in game.get_node("Players").get_children():
		if str(fish.name) != str(my_id):
			var start: Vector2 = fish.global_position
			await create_timer(0.8).timeout
			if is_instance_valid(fish) and fish.global_position.distance_to(start) > 1.0:
				other_fish_seen = true
