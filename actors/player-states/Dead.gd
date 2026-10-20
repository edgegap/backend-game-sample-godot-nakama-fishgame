extends "res://addons/snopek-state-machine/State.gd"

var ExplodeEffect: PackedScene = preload("res://actors/ExplodeEffect.tscn")

@onready var host = $"../.."

func _state_enter(info: Dictionary) -> void:
	# Online, the server ends the player (see Player.server_hit), and _do_die
	# makes the explosion everywhere.
	if GameState.online_play:
		return
	var explosion = ExplodeEffect.instantiate()
	host.get_parent().add_child(explosion)
	explosion.global_position = host.global_position
	
	host.die()
