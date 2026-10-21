extends CanvasLayer

# ==============================================================================
# VINADI — MOBILE TOUCH CONTROLS
# Thin controller script bound to nodes defined in touch_controls.tscn.
# You can position, resize, re-anchor, and re-style any button visually
# in the Godot 2D editor by opening res://ui/touch_controls.tscn!
# ==============================================================================

# References to scene nodes
@onready var _joystick: Control = %MoveJoystick
@onready var _btn_jump: Button = %JumpButton
@onready var _btn_slide: Button = %SlideButton
@onready var _btn_use: Button = %UseButton
@onready var _btn_pause: Button = %PauseButton
@onready var _look_area: Control = %LookArea

# Player / World references
var _player: CharacterBody3D = null
var _head: Node3D = null
var _game_ui = null

# Look sensitivity — standard for mobile FPS swipe look
@export var look_sensitivity: float = 0.0015
@export var auto_sprint_threshold: float = 0.85
## Set to true in Inspector if you want to preview/test touch controls on PC desktop
@export var force_show_for_testing: bool = false

# Swipe-to-look touch tracking
var _look_touch_id: int = -1
var _is_sprinting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 8
	_connect_buttons()
	_connect_joystick()
	call_deferred("_setup_references")

	# Only show on mobile devices (Android / iOS) or physical touchscreens
	# Hidden completely on the Windows .exe version unless force_show_for_testing is checked
	var is_mobile_device: bool = OS.has_feature("mobile") \
		or OS.has_feature("android") \
		or OS.has_feature("ios") \
		or DisplayServer.is_touchscreen_available()
	visible = is_mobile_device or force_show_for_testing

	# Keep joystick region updated when viewport/window size changes
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_update_joystick_region)
		call_deferred("_update_joystick_region")


func _setup_references() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as CharacterBody3D
		if _player:
			_head = _player.find_child("Head", true, false)
			if not _head:
				_head = _player.get_node_or_null("%Head")

	var guis := get_tree().get_nodes_in_group("game_ui")
	if guis.size() > 0:
		_game_ui = guis[0]


func _ensure_references() -> bool:
	if _player and is_instance_valid(_player) and _head and is_instance_valid(_head):
		return true
	_setup_references()
	return _player != null and is_instance_valid(_player)


func _connect_buttons() -> void:
	if _btn_jump:
		_btn_jump.button_down.connect(func(): Input.action_press("jump", 1.0))
		_btn_jump.button_up.connect(func(): Input.action_release("jump"))

	if _btn_slide:
		_btn_slide.button_down.connect(func(): Input.action_press("crouch", 1.0))
		_btn_slide.button_up.connect(func(): Input.action_release("crouch"))

	if _btn_use:
		_btn_use.button_down.connect(func(): Input.action_press("interact", 1.0))
		_btn_use.button_up.connect(func(): Input.action_release("interact"))

	if _btn_pause:
		_btn_pause.pressed.connect(_on_pause_pressed)


func _connect_joystick() -> void:
	if _joystick:
		if _joystick.has_signal("joystick_moved"):
			_joystick.connect("joystick_moved", _on_joystick_moved)
		if _joystick.has_signal("joystick_released"):
			_joystick.connect("joystick_released", _on_joystick_released)


func _on_joystick_moved(dir: Vector2) -> void:
	# Auto-sprint when joystick pushed to outer rim
	if dir.length() >= auto_sprint_threshold and not _is_sprinting:
		_is_sprinting = true
		Input.action_press("sprint", 1.0)
	elif dir.length() < auto_sprint_threshold and _is_sprinting:
		_is_sprinting = false
		Input.action_release("sprint")


func _on_joystick_released() -> void:
	if _is_sprinting:
		_is_sprinting = false
		Input.action_release("sprint")


func _on_pause_pressed() -> void:
	if _game_ui == null:
		_setup_references()
	if _game_ui and _game_ui.has_method("toggle_pause"):
		_game_ui.toggle_pause()


# ==============================================================================
# INPUT — Swipe-to-look on right side of screen
# ==============================================================================

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not _ensure_references():
		return
	if _player.has_method("is_control_disabled") and _player.is_control_disabled():
		return

	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			# Only touches within LookArea that are not on buttons start a look drag
			if _look_touch_id == -1 and _is_in_look_area(te.position):
				if not _is_on_any_button(te.position):
					_look_touch_id = te.index
		else:
			if te.index == _look_touch_id:
				_look_touch_id = -1

	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if de.index == _look_touch_id:
			_apply_look(de.relative)


func _is_in_look_area(pos: Vector2) -> bool:
	if _look_area and is_instance_valid(_look_area) and _look_area.is_visible_in_tree():
		return _look_area.get_global_rect().has_point(pos)
	# Fallback if no specific look area defined: right half of viewport
	var vp_size := get_viewport().get_visible_rect().size
	return pos.x >= vp_size.x * 0.4


func _is_on_any_button(pos: Vector2) -> bool:
	for btn in [_btn_jump, _btn_slide, _btn_use, _btn_pause]:
		if btn and is_instance_valid(btn) and btn.is_visible_in_tree() and btn.get_global_rect().has_point(pos):
			return true
	return false


func _apply_look(delta: Vector2) -> void:
	if not _ensure_references():
		return
	_player.rotate_y(-delta.x * look_sensitivity)
	if "mouse_input" in _player:
		_player.mouse_input = delta
	if _head and is_instance_valid(_head):
		_head.rotate_x(-delta.y * look_sensitivity)
		_head.rotation.x = clamp(_head.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))


# ==============================================================================
# VIEWPORT RESIZE — Keep VirtualJoystickDX region in sync
# ==============================================================================

func _update_joystick_region() -> void:
	if _joystick and is_instance_valid(_joystick):
		var vp := get_viewport().get_visible_rect().size
		_joystick.set("region_x", 0.0)
		_joystick.set("region_y", 0.0)
		_joystick.set("region_w", vp.x * 0.45)
		_joystick.set("region_h", vp.y)
