extends CanvasLayer

# ==============================================================================
# VINADI — MOBILE TOUCH CONTROLS & VIRTUAL JOYSTICK
# Provides a full on-screen touch interface for Android / mobile:
#   - Floating dynamic virtual joystick on left half (movement + auto-sprint)
#   - Smooth drag-look trackpad on right half (camera rotation)
#   - Dedicated action touch buttons: JUMP, SLIDE, USE, PAUSE
# Automatically enables on mobile/touchscreen devices, or via debug toggle.
# ==============================================================================

# References
var _player: CharacterBody3D = null
var _head: Node3D = null
var _game_ui = null

# Configuration
@export var touch_look_sensitivity: float = 0.003
@export var joystick_radius: float = 65.0
@export var auto_sprint_threshold: float = 0.85

# State - Joystick
var _joystick_active: bool = false
var _joystick_touch_id: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_current: Vector2 = Vector2.ZERO
var _joystick_dir: Vector2 = Vector2.ZERO
var _is_sprinting: bool = false

# State - Look Drag
var _look_touch_id: int = -1
var _look_last_pos: Vector2 = Vector2.ZERO

# UI Nodes
var _root: Control
var _joystick_base: Control
var _joystick_knob: Control
var _btn_jump: Button
var _btn_slide: Button
var _btn_use: Button
var _btn_pause: Button


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	call_deferred("_setup_references")

	# Check if running on mobile device or if touchscreen is detected
	var is_touch := DisplayServer.is_touchscreen_available() or \
			OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	
	# Always visible on touch devices; on desktop, keep available for testing via touch emulation
	visible = is_touch or ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)


func _setup_references() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as CharacterBody3D
		if _player:
			_head = _player.get_node_or_null("%Head")
			if not _head:
				_head = _player.find_child("Head", true, false)

	var guis := get_tree().get_nodes_in_group("game_ui")
	if guis.size() > 0:
		_game_ui = guis[0]


func _build_ui() -> void:
	var font: FontFile = load("res://fonts/Rajdhani-SemiBold.ttf") as FontFile
	if not font:
		font = load("res://font/Rajdhani-SemiBold.ttf") as FontFile

	_root = Control.new()
	_root.name = "TouchRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# ── Joystick Visuals ───────────────────────────────────────────────────────
	_joystick_base = _create_circle_panel(joystick_radius * 2.0, Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.7), 2)
	_joystick_base.visible = false
	_joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_joystick_base)

	_joystick_knob = _create_circle_panel(joystick_radius * 0.9, Color(1, 1, 1, 0.85), Color(0.1, 0.9, 0.5, 0.9), 2)
	_joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_base.add_child(_joystick_knob)

	# ── Default idle hint for joystick position ───────────────────────────────
	var default_hint := _create_circle_panel(joystick_radius * 2.0, Color(0, 0, 0, 0.2), Color(1, 1, 1, 0.25), 1)
	default_hint.set_anchor_and_offset(SIDE_LEFT, 0.0, 60.0)
	default_hint.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -60.0 - joystick_radius * 2.0)
	default_hint.custom_minimum_size = Vector2(joystick_radius * 2.0, joystick_radius * 2.0)
	default_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(default_hint)

	# ── Action Buttons ────────────────────────────────────────────────────────
	# JUMP
	_btn_jump = _create_action_button("JUMP", Vector2(74, 74), font)
	_btn_jump.set_anchor_and_offset(SIDE_RIGHT, 1.0, -35.0)
	_btn_jump.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -55.0)
	_btn_jump.button_down.connect(_on_jump_down)
	_btn_jump.button_up.connect(_on_jump_up)
	_root.add_child(_btn_jump)

	# SLIDE / CROUCH
	_btn_slide = _create_action_button("SLIDE", Vector2(70, 70), font)
	_btn_slide.set_anchor_and_offset(SIDE_RIGHT, 1.0, -125.0)
	_btn_slide.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -40.0)
	_btn_slide.button_down.connect(_on_slide_down)
	_btn_slide.button_up.connect(_on_slide_up)
	_root.add_child(_btn_slide)

	# USE / DECONTAMINATE
	_btn_use = _create_action_button("USE", Vector2(70, 70), font, Color(0.12, 1.0, 0.5, 0.95))
	_btn_use.set_anchor_and_offset(SIDE_RIGHT, 1.0, -35.0)
	_btn_use.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -145.0)
	_btn_use.button_down.connect(_on_use_down)
	_btn_use.button_up.connect(_on_use_up)
	_root.add_child(_btn_use)

	# PAUSE (Top Right)
	_btn_pause = _create_action_button("||", Vector2(48, 48), font)
	_btn_pause.set_anchor_and_offset(SIDE_RIGHT, 1.0, -25.0)
	_btn_pause.set_anchor_and_offset(SIDE_TOP, 0.0, 25.0)
	_btn_pause.pressed.connect(_on_pause_pressed)
	_root.add_child(_btn_pause)


func _create_circle_panel(diameter: float, bg_color: Color, border_color: Color, border_width: int) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(diameter, diameter)
	panel.size = Vector2(diameter, diameter)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(int(diameter * 0.5))
	sb.set_border_width_all(border_width)
	sb.border_color = border_color
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _create_action_button(label: String, btn_size: Vector2, font: FontFile, border_color: Color = Color(1, 1, 1, 0.9)) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = btn_size
	btn.size = btn_size
	btn.pivot_offset = btn_size * 0.5

	if font:
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 16 if label.length() > 3 else 20)

	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0.65)
	normal.set_corner_radius_all(int(min(btn_size.x, btn_size.y) * 0.5))
	normal.set_border_width_all(2)
	normal.border_color = border_color

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.25, 0.25, 0.25, 0.9)
	pressed.set_corner_radius_all(int(min(btn_size.x, btn_size.y) * 0.5))
	pressed.set_border_width_all(3)
	pressed.border_color = Color(1, 1, 1, 1)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn


# ==============================================================================
# INPUT HANDLING (Touch Screen events)
# ==============================================================================

func _input(event: InputEvent) -> void:
	if not visible:
		return

	var vp_size := get_viewport().get_visible_rect().size
	var half_screen_x := vp_size.x * 0.5

	# ── TOUCH DOWN ────────────────────────────────────────────────────────────
	if event is InputEventScreenTouch and event.pressed:
		var touch_ev := event as InputEventScreenTouch
		var pos: Vector2 = touch_ev.position

		# Check if touch is on action buttons
		if _is_pos_inside_control(_btn_jump, pos) or \
				_is_pos_inside_control(_btn_slide, pos) or \
				_is_pos_inside_control(_btn_use, pos) or \
				_is_pos_inside_control(_btn_pause, pos):
			return  # Let buttons consume the touch

		# Left half of screen -> Joystick
		if pos.x < half_screen_x:
			if not _joystick_active:
				_joystick_active = true
				_joystick_touch_id = touch_ev.index
				_joystick_center = pos
				_joystick_current = pos
				_joystick_base.global_position = _joystick_center - _joystick_base.size * 0.5
				_joystick_knob.position = (_joystick_base.size - _joystick_knob.size) * 0.5
				_joystick_base.visible = true
				_update_joystick_vector()
		# Right half of screen -> Look Drag
		else:
			if _look_touch_id == -1:
				_look_touch_id = touch_ev.index
				_look_last_pos = pos

	# ── TOUCH UP ──────────────────────────────────────────────────────────────
	elif event is InputEventScreenTouch and not event.pressed:
		var touch_ev := event as InputEventScreenTouch
		if touch_ev.index == _joystick_touch_id:
			_release_joystick()
		elif touch_ev.index == _look_touch_id:
			_look_touch_id = -1

	# ── DRAG ──────────────────────────────────────────────────────────────────
	elif event is InputEventScreenDrag:
		var drag_ev := event as InputEventScreenDrag
		if drag_ev.index == _joystick_touch_id:
			_joystick_current = drag_ev.position
			_update_joystick_vector()
		elif drag_ev.index == _look_touch_id:
			var delta_pos: Vector2 = drag_ev.relative
			_apply_look(delta_pos)


func _is_pos_inside_control(ctrl: Control, pos: Vector2) -> bool:
	if not ctrl or not ctrl.is_visible_in_tree():
		return false
	return ctrl.get_global_rect().has_point(pos)


func _update_joystick_vector() -> void:
	var diff := _joystick_current - _joystick_center
	var dist := diff.length()

	if dist > joystick_radius:
		diff = diff.normalized() * joystick_radius

	# Update knob visual offset
	var center_knob_offset := (_joystick_base.size - _joystick_knob.size) * 0.5
	_joystick_knob.position = center_knob_offset + diff

	# Normalized output (-1 to 1)
	_joystick_dir = diff / joystick_radius if joystick_radius > 0.0 else Vector2.ZERO

	# Auto sprint when pushed hard
	var strength := _joystick_dir.length()
	if strength >= auto_sprint_threshold and not _is_sprinting:
		_is_sprinting = true
		Input.action_press("sprint", 1.0)
	elif strength < auto_sprint_threshold and _is_sprinting:
		_is_sprinting = false
		Input.action_release("sprint")

	# Dispatch movement actions with strength
	_dispatch_action("move_right", max(0.0, _joystick_dir.x))
	_dispatch_action("move_left", max(0.0, -_joystick_dir.x))
	_dispatch_action("move_back", max(0.0, _joystick_dir.y))
	_dispatch_action("move_forward", max(0.0, -_joystick_dir.y))


func _dispatch_action(action_name: String, strength: float) -> void:
	if strength > 0.15:
		Input.action_press(action_name, strength)
	else:
		Input.action_release(action_name)


func _release_joystick() -> void:
	_joystick_active = false
	_joystick_touch_id = -1
	_joystick_dir = Vector2.ZERO
	_joystick_base.visible = false
	if _is_sprinting:
		_is_sprinting = false
		Input.action_release("sprint")
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")


func _apply_look(delta_vec: Vector2) -> void:
	if _player == null:
		_setup_references()
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("is_control_disabled") and _player.is_control_disabled():
		return

	_player.rotate_y(-delta_vec.x * touch_look_sensitivity)
	if _head and is_instance_valid(_head):
		_head.rotate_x(-delta_vec.y * touch_look_sensitivity)
		_head.rotation.x = clamp(_head.rotation.x, deg_to_rad(-80), deg_to_rad(80))


# ==============================================================================
# BUTTON CALLBACKS
# ==============================================================================

func _on_jump_down() -> void:
	Input.action_press("jump", 1.0)


func _on_jump_up() -> void:
	Input.action_release("jump")


func _on_slide_down() -> void:
	Input.action_press("crouch", 1.0)


func _on_slide_up() -> void:
	Input.action_release("crouch")


func _on_use_down() -> void:
	Input.action_press("interact", 1.0)


func _on_use_up() -> void:
	Input.action_release("interact")


func _on_pause_pressed() -> void:
	if _game_ui == null:
		_setup_references()
	if _game_ui and _game_ui.has_method("toggle_pause"):
		_game_ui.toggle_pause()
