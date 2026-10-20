extends Node

@export var cross_fade_duration: float = 2.0

signal song_finished (song)

var current_song
var initial_volume_dbs := {}

func _ready() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			initial_volume_dbs[child.name] = child.volume_db
			child.connect("finished", Callable(self, "_on_song_finished").bind(child))

func play(song_name: String) -> void:
	var next_song = get_node(song_name)
	if !next_song or next_song.playing:
		return
	
	if current_song:
		var fade_out := create_tween()
		fade_out.tween_property(current_song, "volume_db", -40.0, cross_fade_duration / 2.0)
		fade_out.tween_callback(current_song.stop)
	
	next_song.volume_db = -40.0
	next_song.play()
	create_tween().tween_property(next_song, "volume_db", initial_volume_dbs.get(next_song.name, 0.0), cross_fade_duration / 2.0)
	
	current_song = next_song

func play_random() -> void:
	if get_child_count() == 1:
		return
	
	var next_song: Node
	while next_song == null or current_song == next_song:
		next_song = _pick_random()
	
	play(next_song.name)

func _pick_random() -> Node:
	return get_child(randi() % (get_child_count() - 1))

func _on_song_finished(song) -> void:
	emit_signal("song_finished", song)

