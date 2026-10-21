extends CanvasLayer

# ==============================================================================
# VINADI – DEBUG PANEL
# Toggle with F1.  Self-building CanvasLayer; no .tscn needed.
# Gives full runtime control over: timer, player stats, game state, engine.
# ==============================================================================

# ── Built node references ─────────────────────────────────────────────────────
var _panel_root:        Control     # entire panel — hidden/shown on F1
var _freeze_btn:        CheckButton
var _god_btn:           CheckButton
var _no_fall_btn:       CheckButton
var _speed_slider:      HSlider
var _speed_val_lbl:     Label
var _timescale_slider:  HSlider
var _timescale_val_lbl: Label
var _fps_lbl:           Label
var _pos_lbl:           Label
var _vel_lbl:           Label
var _state_lbl:         Label

# ── Scene references (found via groups) ───────────────────────────────────────
var _player: CharacterBody3D = null
var _game_ui: CanvasLayer    = null
var _visible: bool           = false


# ==============================================================================
# LIFECYCLE
# ==============================================================================
func _ready() -> void:
	layer = 10
	_build_panel()
	_panel_root.visible = false
	# Wait one frame so all _ready() calls in the scene have run
	call_deferred("_find_refs")


func _find_refs() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as CharacterBody3D
	var guis := get_tree().get_nodes_in_group("game_ui")
	if guis.size() > 0:
		_game_ui = guis[0] as CanvasLayer


# ==============================================================================
# INPUT
# ==============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("debug_panel", false):
		return
	_visible = not _visible
	_panel_root.visible = _visible
	if _visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# Only recapture if the game is still running
		var ended: bool = _game_ui != null and _game_ui.get("game_ended") == true
		var paused: bool = _game_ui != null and _game_ui.get("is_paused") == true
		if not ended and not paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ==============================================================================
# _PROCESS  — update info labels when panel is open
# ==============================================================================
func _process(_delta: float) -> void:
	if not _visible or _player == null:
		return
	_fps_lbl.text = "FPS: %d" % Engine.get_frames_per_second()
	var pos: Vector3   = _player.global_position
	_pos_lbl.text      = "Pos  (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]
	var h_spd: float   = Vector3(_player.velocity.x, 0.0, _player.velocity.z).length()
	_vel_lbl.text      = "Speed  %.2f m/s" % h_spd

	if _player.has_method("is_sliding")   and _player.is_sliding():
		_state_lbl.text = "State  SLIDING"
	elif _player.has_method("is_crouching") and _player.is_crouching():
		_state_lbl.text = "State  CROUCHING"
	elif _player.has_method("is_running")   and _player.is_running():
		_state_lbl.text = "State  SPRINTING"
	else:
		_state_lbl.text = "State  WALKING"


# ==============================================================================
# PANEL CONSTRUCTION
# ==============================================================================
func _build_panel() -> void:
	var font: FontFile = _load_font()

	# Full-screen root (ignore mouse except over actual panel)
	var root: Control = Control.new()
	root.name = "DebugRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel_root = root

	# ── Side panel background ──────────────────────────────────────────────────
	var panel_bg := PanelContainer.new()
	panel_bg.set_anchor_and_offset(SIDE_LEFT,   0.0,   0.0)
	panel_bg.set_anchor_and_offset(SIDE_TOP,    0.0,   0.0)
	panel_bg.set_anchor_and_offset(SIDE_RIGHT,  0.0, 310.0)
	panel_bg.set_anchor_and_offset(SIDE_BOTTOM, 1.0,   0.0)
	panel_bg.grow_horizontal = Control.GROW_DIRECTION_END
	panel_bg.grow_vertical   = Control.GROW_DIRECTION_END

	var bg_style         := StyleBoxFlat.new()
	bg_style.bg_color     = Color(0.03, 0.03, 0.08, 0.94)
	bg_style.border_width_right = 2
	bg_style.border_color       = Color(0.28, 0.48, 1.0, 0.38)
	bg_style.content_margin_left   = 12.0
	bg_style.content_margin_right  = 12.0
	bg_style.content_margin_top    = 12.0
	bg_style.content_margin_bottom = 12.0
	panel_bg.add_theme_stylebox_override("panel", bg_style)
	root.add_child(panel_bg)

	# Scroll container so long panels don't overflow
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_bg.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(272.0, 0.0)
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# ── Header ────────────────────────────────────────────────────────────────
	_add_lbl(vbox, "⚙  DEBUG PANEL   [F1]", 15, Color(0.4, 0.82, 1.0), font)
	_sep(vbox)

	# ── TIMER ─────────────────────────────────────────────────────────────────
	_add_lbl(vbox, "TIMER", 11, Color(0.55, 0.55, 0.55), font)

	_freeze_btn = _check(vbox, "Freeze Timer", font)
	_freeze_btn.toggled.connect(_on_freeze)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 4)
	vbox.add_child(time_row)
	_btn_in(time_row, "+5 sec",  font).pressed.connect(_on_add_time)
	_btn_in(time_row, "−5 sec",  font).pressed.connect(_on_sub_time)
	_btn_in(time_row, "Reset Timer", font).pressed.connect(_on_reset_timer)
	_sep(vbox)

	# ── PLAYER ────────────────────────────────────────────────────────────────
	_add_lbl(vbox, "PLAYER", 11, Color(0.55, 0.55, 0.55), font)

	_god_btn = _check(vbox, "God Mode  (no damage, no death)", font)
	_god_btn.toggled.connect(_on_god)

	_no_fall_btn = _check(vbox, "No Fall Damage", font)
	_no_fall_btn.toggled.connect(_on_no_fall)

	_add_lbl(vbox, "Speed Multiplier", 12, Color(0.72, 0.72, 0.72), font)
	var spd_row := HBoxContainer.new()
	vbox.add_child(spd_row)
	_speed_slider = _slider(spd_row, 0.5, 4.0, 0.1, 1.0)
	_speed_slider.value_changed.connect(_on_speed)
	_speed_val_lbl = _add_lbl(spd_row, "1.0×", 13, Color.WHITE, font)
	_speed_val_lbl.custom_minimum_size = Vector2(44, 0)
	_sep(vbox)

	# ── GAME ──────────────────────────────────────────────────────────────────
	_add_lbl(vbox, "GAME", 11, Color(0.55, 0.55, 0.55), font)

	var game_row := HBoxContainer.new()
	game_row.add_theme_constant_override("separation", 4)
	vbox.add_child(game_row)
	var win_btn  := _btn_in(game_row, "✓  Force WIN",  font)
	var lose_btn := _btn_in(game_row, "✗  Force LOSE", font)
	win_btn.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	lose_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_btn.pressed.connect(_on_force_win)
	lose_btn.pressed.connect(_on_force_lose)
	_btn_in(vbox, "⟳   Restart Scene", font).pressed.connect(_on_restart)
	_sep(vbox)

	# ── ENGINE ────────────────────────────────────────────────────────────────
	_add_lbl(vbox, "ENGINE", 11, Color(0.55, 0.55, 0.55), font)
	_add_lbl(vbox, "Time Scale", 12, Color(0.72, 0.72, 0.72), font)

	var ts_row := HBoxContainer.new()
	vbox.add_child(ts_row)
	_timescale_slider = _slider(ts_row, 0.05, 3.0, 0.05, 1.0)
	_timescale_slider.value_changed.connect(_on_timescale)
	_timescale_val_lbl = _add_lbl(ts_row, "1.00×", 13, Color.WHITE, font)
	_timescale_val_lbl.custom_minimum_size = Vector2(52, 0)
	_sep(vbox)

	# ── INFO ──────────────────────────────────────────────────────────────────
	_add_lbl(vbox, "INFO  (live)", 11, Color(0.55, 0.55, 0.55), font)
	_fps_lbl   = _add_lbl(vbox, "FPS  --",          13, Color(0.85, 0.85, 0.85), font)
	_pos_lbl   = _add_lbl(vbox, "Pos  --",           13, Color(0.85, 0.85, 0.85), font)
	_vel_lbl   = _add_lbl(vbox, "Speed  --",         13, Color(0.85, 0.85, 0.85), font)
	_state_lbl = _add_lbl(vbox, "State  --",         13, Color(0.85, 0.85, 0.85), font)


# ==============================================================================
# SIGNAL CALLBACKS
# ==============================================================================
func _on_freeze(on: bool) -> void:
	if _game_ui: _game_ui.freeze_timer = on

func _on_god(on: bool) -> void:
	if _player: _player.god_mode = on

func _on_no_fall(on: bool) -> void:
	if _player: _player.no_fall_damage = on

func _on_speed(v: float) -> void:
	_speed_val_lbl.text = "%.1f×" % v
	if _player: _player.debug_speed_multiplier = v

func _on_timescale(v: float) -> void:
	_timescale_val_lbl.text = "%.2f×" % v
	Engine.time_scale = v

func _on_add_time() -> void:
	if _game_ui:
		_game_ui.time_remaining = min(_game_ui.time_remaining + 5.0, _game_ui.total_time * 2.0)

func _on_sub_time() -> void:
	if _game_ui:
		_game_ui.time_remaining = max(0.5, _game_ui.time_remaining - 5.0)

func _on_reset_timer() -> void:
	if _game_ui:
		_game_ui.time_remaining = _game_ui.total_time

func _on_force_win() -> void:
	if _game_ui and _game_ui.has_method("trigger_win"):
		_game_ui.trigger_win()

func _on_force_lose() -> void:
	if _game_ui and _game_ui.has_method("trigger_game_over"):
		_game_ui.trigger_game_over()

func _on_restart() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ==============================================================================
# BUILDER HELPERS
# ==============================================================================
func _add_lbl(p: Control, text: String, size: int, col: Color, font: FontFile) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font: l.add_theme_font_override("font", font)
	p.add_child(l)
	return l

func _sep(p: Control) -> void:
	p.add_child(HSeparator.new())

func _check(p: Control, text: String, font: FontFile) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	if font: b.add_theme_font_override("font", font)
	p.add_child(b)
	return b

func _btn_in(p: Control, text: String, font: FontFile) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	if font: b.add_theme_font_override("font", font)
	p.add_child(b)
	return b

func _slider(p: Control, lo: float, hi: float, step: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step      = step
	s.value     = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(s)
	return s

func _load_font() -> FontFile:
	var path := "res://fonts/Rajdhani-SemiBold.ttf"
	if ResourceLoader.exists(path):
		return load(path) as FontFile
	return null
