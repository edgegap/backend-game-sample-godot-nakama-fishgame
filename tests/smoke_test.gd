extends SceneTree

# Plays local mode for a few seconds, then checks the fish landed on the map and
# saves a screenshot. Run with a window so the screenshot renders:
#   godot --path . --script res://tests/smoke_test.gd -- --screenshot=res://tests/smoke.png

var ok_pickup := false

func _initialize() -> void:
	var main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_TitleScreen_play_local()

	for i in 180:
		await physics_frame

	# Player 1 walks to the sword, picks it up, swings, jumps and throws it.
	await _hold("player1_right", 25)
	var fish = main.get_node("Game/Players/1")
	var pickups := []
	for node in main.get_node("Game/Map/Objects").get_children():
		if node.has_method("can_pickup"):
			pickups.append("%s %s" % [node.name, node.global_position])
	print("fish at %s, pickups: %s" % [fish.global_position, pickups])
	await _tap("player1_grab")
	print("picked up: %s" % fish.current_pickup)
	ok_pickup = fish.current_pickup != null
	await _tap("player1_use")
	await _hold("player1_jump", 10)
	await _hold("player1_left", 15)
	await _tap("player1_grab")
	for i in 60:
		await physics_frame

	var players: Array = main.get_node("Game/Players").get_children()
	var ok := players.size() == 2 and ok_pickup
	for player in players:
		print("%s at %s, on floor: %s" % [player.name, player.global_position, player.is_on_floor()])
		ok = ok and player.is_on_floor()

	var shot := ''
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			shot = arg.substr(13)
	if shot != '':
		await process_frame
		root.get_texture().get_image().save_png(shot)

	print("SMOKE TEST " + ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)

func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await physics_frame
	Input.action_release(action)
	await physics_frame

func _tap(action: String) -> void:
	await _hold(action, 2)
	for i in 10:
		await physics_frame
