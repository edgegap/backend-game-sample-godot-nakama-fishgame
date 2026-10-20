extends SceneTree

# Client side of the local network test: connects with "-- --client
# --connect=127.0.0.1:7777", presses Ready on every ready screen and logs what
# it sees until the match is over.

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
			quit(0 if rounds_started >= 5 and other_fish_seen else 1))
	game.game_started.connect(func():
		rounds_started += 1
		print("TEST: round %d started with %d fish" % [rounds_started, game.get_node("Players").get_child_count()])
		_watch_other_fish(game))
	root.get_node("OnlineMatch").error.connect(func(msg): print("TEST: error " + msg))

	create_timer(120).timeout.connect(func():
		print("TEST: timed out")
		quit(2))

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
