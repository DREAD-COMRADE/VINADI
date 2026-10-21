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

# Swipe-to-look touch tracking
var _look_touch_id: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 8
	_connect_buttons()
	call_deferred("_setup_references")

	# Auto-show on touchscreens, mobile devices, or when touch emulation is enabled
	var show_hud: bool = DisplayServer.is_touchscreen_available() \
		or OS.has_feature("mobile") \
		or OS.has_feature("android") \
		or OS.has_feature("ios") \
		or ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)
	visible = show_hud


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
	if _player == null:
		return
	if _player.has_method("is_control_disabled") and _player.is_control_disabled():
		return

	var vp_half_x: float = get_viewport().get_visible_rect().size.x * 0.45

	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			# Only touches that are on the right side and not on buttons start a look drag
			if te.position.x >= vp_half_x and _look_touch_id == -1:
				if not _is_on_any_button(te.position):
					_look_touch_id = te.index
		else:
			if te.index == _look_touch_id:
				_look_touch_id = -1

	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if de.index == _look_touch_id:
			_apply_look(de.relative)


func _is_on_any_button(pos: Vector2) -> bool:
	for btn in [_btn_jump, _btn_slide, _btn_use, _btn_pause]:
		if btn and btn.is_visible_in_tree() and btn.get_global_rect().has_point(pos):
			return true
	return false


func _apply_look(delta: Vector2) -> void:
	if not is_instance_valid(_player):
		return
	_player.rotate_y(-delta.x * look_sensitivity)
	if _head and is_instance_valid(_head):
		_head.rotate_x(-delta.y * look_sensitivity)
		_head.rotation.x = clamp(_head.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))


# ==============================================================================
# PROCESS — Keep VirtualJoystickDX region synced to viewport width
# ==============================================================================

func _process(_delta: float) -> void:
	if _joystick and is_instance_valid(_joystick):
		var vp := get_viewport().get_visible_rect().size
		_joystick.set("region_w", vp.x * 0.5)
		_joystick.set("region_h", vp.y)
