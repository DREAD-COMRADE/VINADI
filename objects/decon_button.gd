extends Node3D

# ==============================================================================
# DECONTAMINATION BUTTON
# The win trigger. Player activates by pressing [E], Left Click, [F],
# or by directly approaching and touching the decontamination pedestal.
# ==============================================================================

var _player_in_range: bool = false
var _player_node: CharacterBody3D = null
var _game_ui = null
var _activated: bool = false
var _pulse_time: float = 0.0

@onready var _area: Area3D = $TriggerArea
@onready var _cap_mesh: MeshInstance3D = get_node_or_null("ButtonCapMesh")
@onready var _light: OmniLight3D = get_node_or_null("ButtonCapMesh/OmniLight3D")


func _ready() -> void:
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	_find_game_ui()


func _find_game_ui() -> void:
	var guis := get_tree().get_nodes_in_group("game_ui")
	if guis.size() > 0:
		_game_ui = guis[0]
	elif get_tree().root:
		_game_ui = get_tree().root.find_child("GameUI", true, false)


func _input(event: InputEvent) -> void:
	if not _player_in_range or _activated:
		return
	if _is_interact_event(event):
		_activate()


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or _activated:
		return
	if _is_interact_event(event):
		_activate()


func _is_interact_event(event: InputEvent) -> bool:
	if event.is_action_pressed("interact", false):
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.physical_keycode == KEY_F or event.keycode == KEY_E or event.keycode == KEY_F:
			return true
	return false


func _process(delta: float) -> void:
	if _activated:
		return

	# Continually check if player is in range via Area3D overlapping bodies or distance
	if not _player_in_range:
		for b in _area.get_overlapping_bodies():
			if b.is_in_group("player") or b is CharacterBody3D:
				_on_body_entered(b)
				break

	if _player_in_range:
		_pulse_time += delta * 6.0
		if _light:
			_light.light_energy = 2.0 + sin(_pulse_time) * 0.8

		# Multi-input polling fallback
		if Input.is_action_just_pressed("interact") \
				or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
				or Input.is_key_pressed(KEY_E) \
				or Input.is_key_pressed(KEY_F):
			_activate()
			return

		# Direct proximity / touch trigger (if player rushes right into the pedestal)
		if _player_node and is_instance_valid(_player_node):
			var dist: float = global_position.distance_to(_player_node.global_position)
			if dist <= 1.4:
				_activate()
				return


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body is CharacterBody3D:
		_player_in_range = true
		_player_node = body as CharacterBody3D
		if _game_ui == null:
			_find_game_ui()
		if _game_ui and _game_ui.has_method("show_interact_prompt"):
			_game_ui.show_interact_prompt(true)


func _on_body_exited(body: Node3D) -> void:
	if body == _player_node or body.is_in_group("player"):
		_player_in_range = false
		_player_node = null
		if _light:
			_light.light_energy = 2.0
		if _game_ui and _game_ui.has_method("show_interact_prompt"):
			_game_ui.show_interact_prompt(false)


func _activate() -> void:
	if _activated:
		return
	if _game_ui == null:
		_find_game_ui()
	if _game_ui and _game_ui.get("game_ended") == true:
		return

	_activated = true
	_player_in_range = false

	# Visual press feedback
	if _cap_mesh:
		var tw := create_tween()
		tw.tween_property(_cap_mesh, "position:y", 0.98, 0.08)
	if _light:
		_light.light_energy = 4.0

	if _game_ui:
		if _game_ui.has_method("show_interact_prompt"):
			_game_ui.show_interact_prompt(false)
		if _game_ui.has_method("trigger_win"):
			_game_ui.trigger_win()
