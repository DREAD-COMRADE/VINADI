extends Control

## ==============================================================================
## VINADI — MAIN MENU CONTROLLER
## Displays title, backdrop, gas mask emblem, and sci-fi interactive buttons.
## Plays ambient theme music on loop.
## ==============================================================================

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton
@onready var music_player: AudioStreamPlayer = %MusicPlayer


func _ready() -> void:
	# Ensure cursor is free in the main menu
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Connect buttons
	if play_button:
		play_button.pressed.connect(_on_play_pressed)
		_setup_button_hover(play_button)
		play_button.grab_focus()

	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
		_setup_button_hover(quit_button)

	# Setup music
	if music_player:
		music_player.finished.connect(_on_music_finished)
		if not music_player.playing:
			music_player.play()


func _on_play_pressed() -> void:
	# Transition into the game world
	get_tree().change_scene_to_file("res://world/world.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_music_finished() -> void:
	# Loop the background music smoothly
	if music_player:
		music_player.play()


func _setup_button_hover(btn: Button) -> void:
	btn.mouse_entered.connect(func():
		var tween := create_tween()
		tween.tween_property(btn, "modulate", Color(1.15, 1.15, 1.15), 0.1)
	)
	btn.mouse_exited.connect(func():
		var tween := create_tween()
		tween.tween_property(btn, "modulate", Color.WHITE, 0.1)
	)
