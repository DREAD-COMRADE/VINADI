extends Node3D

# ==============================================================================
# VINADI — MOBILE TOUCH CONTROLS
# Uses the VirtualJoystickDX addon for movement joystick.
# Swipe-to-look on right half, action buttons follow industry-standard placement.
#
# Layout (designed for 1280×720 canvas, scales with resolution):
#
#  LEFT HALF              |  RIGHT HALF
#  ───────────────────────┼───────────────────────────
#  [JOYSTICK - DYNAMIC]   |  [PAUSE]   (top-right, 44 px)
#  bottom-left ~160,590   |
#                         |  [USE]     (right col, row 2) 78 px
#  Swipe to look freely   |  [SLIDE]   (right row 1)  72 px
#  anywhere on right half |  [JUMP]    (bottom-right) 88 px
#
# References: COD Mobile, PUBG Mobile, Standoff 2 (FPS-standard proportions)
# ==============================================================================

var _player: CharacterBody3D = null
var _head: Node3D = null
var _game_ui = null

# Look sensitivity — FPS mobile standard is ~2.5× lower than mouse
const LOOK_SENSITIVITY: float = 0.0015

# Look drag state
var _look_touch_id: int = -1
var _look_last_pos: Vector2 = Vector2.ZERO

# Node references
var _canvas_layer: CanvasLayer
var _joystick: Node = null  # VirtualJoystickDX instance
var _btn_jump: Button
var _btn_slide: Button
var _btn_use: Button
var _btn_pause: Button
var _look_area: Control
var _root: Control


func _ready() -> void:
	_build_hud()
	call_deferred("_setup_references")
	# Auto-show only on touchscreen or mobile
	var show_hud: bool = DisplayServer.is_touchscreen_available() \
		or OS.has_feature("mobile") \
		or OS.has_feature("android") \
		or OS.has_feature("ios") \
		or ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)
	_canvas_layer.visible = show_hud


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


func _build_hud() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "MobileTouchHUD"
	_canvas_layer.layer = 8
	_canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas_layer)

	_root = Control.new()
	_root.name = "TouchRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_layer.add_child(_root)

	_build_look_area()
	_build_joystick()
	_build_action_buttons()


func _build_look_area() -> void:
	# Invisible Control covering the full screen to receive drag events for camera look.
	# Buttons on top of it consume their own touches first.
	_look_area = Control.new()
	_look_area.name = "LookArea"
	_look_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_look_area.mouse_filter = Control.MOUSE_FILTER_IGNORE  # pass to _input
	_root.add_child(_look_area)


func _build_joystick() -> void:
	# ── VirtualJoystickDX ────────────────────────────────────────────────────
	# Industry standard: DYNAMIC mode, bottom-left corner.
	# Entire left-half screen is active region.
	# Base radius 90 px, thumb radius 30 px.
	# Centered at approx (160, screen_bottom - 130).
	var script: Script = load("res://addons/virtual_joystick_DX/vjdx_core_script.gd")
	if not script:
		push_error("VirtualJoystickDX: core script not found. Is the plugin enabled?")
		return

	_joystick = script.new()
	_joystick.name = "MoveJoystick"
	_joystick.process_mode = Node.PROCESS_MODE_ALWAYS

	# Size — set large enough for the base circle
	_joystick.custom_minimum_size = Vector2(180, 180)
	_joystick.size = Vector2(180, 180)

	# Anchor: bottom-left corner. Offset inward so center sits at (160, h-130)
	# anchor (0,1) = bottom-left, then offset right and up
	_joystick.set_anchor_and_offset(SIDE_LEFT,   0.0,  70.0)   # 70 px from left
	_joystick.set_anchor_and_offset(SIDE_RIGHT,  0.0, 250.0)   # 70 + 180
	_joystick.set_anchor_and_offset(SIDE_TOP,    1.0, -220.0)  # 220 px above bottom
	_joystick.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -40.0)   # 40 px above bottom

	# VirtualJoystickDX properties (via property assignment — works on @tool nodes)
	_joystick.set("joystick_mode",    1)  # 1 = DYNAMIC
	_joystick.set("controller_style", 0)  # 0 = JOYSTICK
	_joystick.set("joystick_radius",  90.0)
	_joystick.set("thumb_radius",     30.0)
	_joystick.set("deadzone",         0.12)

	# Input mapping — wire to game actions
	_joystick.set("action_left",  "move_left")
	_joystick.set("action_right", "move_right")
	_joystick.set("action_up",    "move_forward")
	_joystick.set("action_down",  "move_back")
	_joystick.set("use_directional_mapping", true)

	# Active region: left half of screen only (set via region props)
	_joystick.set("use_active_region", true)
	_joystick.set("region_x", 0.0)
	_joystick.set("region_y", 0.0)
	# region_w and region_h will be set after viewport is ready (see _setup_references)
	# We'll set them to half-viewport dynamically

	# Style — translucent white circles, no texture (clean look)
	_joystick.set("debug_deadzone",  false)
	_joystick.set("debug_clampzone", false)
	_joystick.set("debug_show_region", false)
	_joystick.set("clampzone_ratio", 1.5)

	# Colors
	_joystick.set("color_js_base",         Color(0.0, 0.0, 0.0, 0.45))
	_joystick.set("color_js_border",       Color(1.0, 1.0, 1.0, 0.70))
	_joystick.set("color_js_thumb",        Color(1.0, 1.0, 1.0, 0.65))
	_joystick.set("color_js_thumb_active", Color(0.12, 1.0, 0.5, 0.90))

	# Haptics
	_joystick.set("haptic_enabled", true)

	# Auto-hide when gamepad connected
	_joystick.set("auto_hide_on_physical_input", true)
	_joystick.set("auto_show_on_touch", true)

	_root.add_child(_joystick)


func _build_action_buttons() -> void:
	var font: FontFile = _load_font()

	# ── JUMP ────────────────────────────────────────────────────────────────
	# Bottom-right corner. Biggest button — most frequent action.
	# Size: 88 px. Position: 45 px from right, 50 px from bottom.
	_btn_jump = _make_button("JUMP", 88, font, Color(1.0, 1.0, 1.0, 0.9))
	_btn_jump.set_anchor_and_offset(SIDE_RIGHT,  1.0, -45.0)
	_btn_jump.set_anchor_and_offset(SIDE_LEFT,   1.0, -133.0)
	_btn_jump.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -50.0)
	_btn_jump.set_anchor_and_offset(SIDE_TOP,    1.0, -138.0)
	_btn_jump.button_down.connect(func(): Input.action_press("jump", 1.0))
	_btn_jump.button_up.connect(func(): Input.action_release("jump"))
	_root.add_child(_btn_jump)

	# ── SLIDE/CROUCH ─────────────────────────────────────────────────────────
	# Left of JUMP, same row. Slightly smaller.
	# Size: 74 px. Position: 143 px from right, 55 px from bottom.
	_btn_slide = _make_button("SLIDE", 74, font, Color(1.0, 1.0, 1.0, 0.9))
	_btn_slide.set_anchor_and_offset(SIDE_RIGHT,  1.0, -143.0)
	_btn_slide.set_anchor_and_offset(SIDE_LEFT,   1.0, -217.0)
	_btn_slide.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -55.0)
	_btn_slide.set_anchor_and_offset(SIDE_TOP,    1.0, -129.0)
	_btn_slide.button_down.connect(func(): Input.action_press("crouch", 1.0))
	_btn_slide.button_up.connect(func(): Input.action_release("crouch"))
	_root.add_child(_btn_slide)

	# ── USE / INTERACT ───────────────────────────────────────────────────────
	# Above JUMP. Green tint — matches the green button in the game world.
	# Size: 78 px. Position: 48 px from right, 155 px from bottom.
	_btn_use = _make_button("USE", 78, font, Color(0.12, 1.0, 0.5, 0.95))
	_btn_use.set_anchor_and_offset(SIDE_RIGHT,  1.0, -48.0)
	_btn_use.set_anchor_and_offset(SIDE_LEFT,   1.0, -126.0)
	_btn_use.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -155.0)
	_btn_use.set_anchor_and_offset(SIDE_TOP,    1.0, -233.0)
	_btn_use.button_down.connect(func(): Input.action_press("interact", 1.0))
	_btn_use.button_up.connect(func(): Input.action_release("interact"))
	_root.add_child(_btn_use)

	# ── PAUSE ────────────────────────────────────────────────────────────────
	# Top-right. Small (44 px) — user tolerates the reach because pause is rare.
	_btn_pause = _make_button("||", 44, font, Color(1.0, 1.0, 1.0, 0.85))
	_btn_pause.set_anchor_and_offset(SIDE_RIGHT,  1.0, -24.0)
	_btn_pause.set_anchor_and_offset(SIDE_LEFT,   1.0, -68.0)
	_btn_pause.set_anchor_and_offset(SIDE_TOP,    0.0,  24.0)
	_btn_pause.set_anchor_and_offset(SIDE_BOTTOM, 0.0,  68.0)
	_btn_pause.pressed.connect(_on_pause_pressed)
	_root.add_child(_btn_pause)


func _make_button(label: String, diameter: int, font: FontFile, border_color: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(diameter, diameter)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical   = Control.SIZE_SHRINK_CENTER

	if font:
		btn.add_theme_font_override("font", font)
		var fs := 18 if label.length() > 3 else 22
		btn.add_theme_font_size_override("font_size", fs)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	var radius := int(diameter * 0.5)

	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color     = Color(0, 0, 0, 0.50)
	sb_normal.border_color = border_color
	sb_normal.set_corner_radius_all(radius)
	sb_normal.set_border_width_all(2)

	var sb_pressed := StyleBoxFlat.new()
	sb_pressed.bg_color     = Color(0.2, 0.2, 0.2, 0.85)
	sb_pressed.border_color = Color(1, 1, 1, 1)
	sb_pressed.set_corner_radius_all(radius)
	sb_pressed.set_border_width_all(3)

	var sb_empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal",   sb_normal)
	btn.add_theme_stylebox_override("hover",    sb_normal)
	btn.add_theme_stylebox_override("pressed",  sb_pressed)
	btn.add_theme_stylebox_override("focus",    sb_empty)
	btn.add_theme_stylebox_override("disabled", sb_empty)
	return btn


func _load_font() -> FontFile:
	var f := load("res://fonts/Rajdhani-SemiBold.ttf") as FontFile
	if not f:
		f = load("res://font/Rajdhani-SemiBold.ttf") as FontFile
	return f


# ==============================================================================
# INPUT — Swipe-to-look on right half of screen
# ==============================================================================

func _input(event: InputEvent) -> void:
	if not _canvas_layer.visible:
		return
	if _player == null:
		return
	if _player.has_method("is_control_disabled") and _player.is_control_disabled():
		return

	var vp_half_x: float = get_viewport().get_visible_rect().size.x * 0.5

	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			# Only right-half touches that aren't on action buttons start a look drag
			if te.position.x >= vp_half_x and _look_touch_id == -1:
				if not _is_on_any_button(te.position):
					_look_touch_id = te.index
					_look_last_pos = te.position
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
	_player.rotate_y(-delta.x * LOOK_SENSITIVITY)
	if _head and is_instance_valid(_head):
		_head.rotate_x(-delta.y * LOOK_SENSITIVITY)
		_head.rotation.x = clamp(_head.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))


# ==============================================================================
# CALLBACKS
# ==============================================================================

func _on_pause_pressed() -> void:
	if _game_ui == null:
		_setup_references()
	if _game_ui and _game_ui.has_method("toggle_pause"):
		_game_ui.toggle_pause()


# ==============================================================================
# PROCESS — Keep joystick region synced to left half of screen
# ==============================================================================

func _process(_delta: float) -> void:
	if _joystick == null or not is_instance_valid(_joystick):
		return
	var vp := get_viewport().get_visible_rect().size
	_joystick.set("region_w", vp.x * 0.5)
	_joystick.set("region_h", vp.y)
