extends SceneTree

# Dedicated server side of the local network test (see tests/README.md): every
# round, the server "hits" the fish of the lowest peer ID, so the other player
# wins the match after 5 rounds and the server stops itself.

func _initialize() -> void:
	var main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	var game = main.get_node("Game")
	game.game_started.connect(func(): _hit_a_player(game))

func _hit_a_player(game) -> void:
	await create_timer(1.5).timeout
	var fish: Array = game.get_node("Players").get_children()
	fish.sort_custom(func(a, b): return int(str(a.name)) < int(str(b.name)))
	print("TEST: server hits fish %s (of %d)" % [fish[0].name, fish.size()])
	var weapon := Node2D.new()
	game.add_child(weapon)
	weapon.global_position = fish[0].global_position + Vector2(20, 0)
	fish[0].server_hit(weapon)
	weapon.queue_free()
