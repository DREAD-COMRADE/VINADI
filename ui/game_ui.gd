extends CanvasLayer

# ==============================================================================
# VINADI — GAMEPLAY CONTROLLER & EVENT COORDINATOR
# Drives 20s countdown, level win/loss screens, pause menu, interact prompts, and HUD.
# ==============================================================================

signal player_won
signal player_lost

@export var total_time: float = 20.0

var time_remaining: float
var is_running: bool = false
var game_ended: bool = false
var freeze_timer: bool = false
var is_paused: bool = false

# References
var _hud: VINADI_UI = null
var _interact_prompt: Label
var _win_screen: Control
var _game_over_screen: Control
var _pause_screen: Control


var _bg_music_player: AudioStreamPlayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_ui")
	layer = 6
	time_remaining = total_time
	call_deferred("_setup_hud")
	call_deferred("_setup_music")
	_build_popups()
	is_running = true


func _setup_music() -> void:
	var existing: AudioStreamPlayer = get_node_or_null("InGameMusicPlayer") as AudioStreamPlayer
	if not existing and get_parent():
		existing = get_parent().get_node_or_null("InGameMusicPlayer") as AudioStreamPlayer
	if not existing:
		var music_stream: AudioStream = load("res://assets/VINADI_theme.wav") as AudioStream
		if music_stream:
			_bg_music_player = AudioStreamPlayer.new()
			_bg_music_player.name = "InGameMusicPlayer"
			_bg_music_player.stream = music_stream
			_bg_music_player.volume_db = -4.0
			_bg_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(_bg_music_player)
			_bg_music_player.finished.connect(func():
				if _bg_music_player:
					_bg_music_player.play()
			)
			_bg_music_player.play()
	else:
		_bg_music_player = existing
		if not _bg_music_player.playing:
			_bg_music_player.play()
		_bg_music_player.finished.connect(func():
			if _bg_music_player:
				_bg_music_player.play()
		)


func _setup_hud() -> void:
	var huds := get_tree().get_nodes_in_group("hud")
	if huds.size() > 0:
		_hud = huds[0] as VINADI_UI
	if _hud:
		_hud.set_countdown(time_remaining, total_time)
		if not _hud.contamination_depleted.is_connected(trigger_game_over):
			_hud.contamination_depleted.connect(trigger_game_over)
		_sync_gas_mask_hud()


## Keep the HUD integrity readout tied to the player's actual gas-mask durability.
## The old passive drain was independent of gas damage, so the HUD could disagree
## with the player's real durability.
func _sync_gas_mask_hud() -> void:
	if not is_instance_valid(_hud):
		return

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var player: Node = players[0]
	var durability: float = -1.0

	if player.has_method("get_gas_mask_durability"):
		durability = float(player.call("get_gas_mask_durability"))
	elif "gas_mask_durability" in player:
		durability = float(player.get("gas_mask_durability"))

	if durability >= 0.0:
		_hud.set_contamination(clampf(durability, 0.0, 100.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not game_ended:
			toggle_pause()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_running or game_ended or freeze_timer or is_paused:
		return

	time_remaining = max(0.0, time_remaining - delta)

	if _hud:
		_hud.set_countdown(time_remaining, total_time)
		_sync_gas_mask_hud()

	if time_remaining <= 0.0:
		trigger_game_over()


# ==============================================================================
# PUBLIC API (Win / Lose / Reset / Interaction / Pause)
# ==============================================================================

func toggle_pause(force_state = null) -> void:
	if game_ended:
		return

	if force_state != null:
		is_paused = bool(force_state)
	else:
		is_paused = not is_paused

	get_tree().paused = is_paused

	if _pause_screen:
		_pause_screen.visible = is_paused

	if is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func trigger_win() -> void:
	if game_ended:
		return
	if is_paused:
		toggle_pause(false)
	game_ended = true
	is_running = false
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("disable_controls"):
			p.disable_controls()
	if _win_screen:
		_win_screen.visible = true
	if _interact_prompt:
		_interact_prompt.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	emit_signal("player_won")


func trigger_game_over() -> void:
	if game_ended:
		return
	if is_paused:
		toggle_pause(false)
	game_ended = true
	is_running = false
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("disable_controls"):
			p.disable_controls()
	if _game_over_screen:
		_game_over_screen.visible = true
	if _interact_prompt:
		_interact_prompt.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	emit_signal("player_lost")


func show_interact_prompt(visible_state: bool) -> void:
	if _interact_prompt:
		_interact_prompt.visible = visible_state and not game_ended and not is_paused


func reset_game() -> void:
	if is_paused:
		toggle_pause(false)
	time_remaining = total_time
	game_ended = false
	is_running = true
	freeze_timer = false
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("enable_controls"):
			p.enable_controls()
	if _win_screen:
		_win_screen.visible = false
	if _game_over_screen:
		_game_over_screen.visible = false
	if _interact_prompt:
		_interact_prompt.visible = false
	if _hud:
		_hud.set_countdown(total_time, total_time)
		_sync_gas_mask_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ==============================================================================
# POPUPS & INTERACTION PROMPT CONSTRUCTION
# ==============================================================================

func _build_popups() -> void:
	var font: FontFile = _load_font()

	var root: Control = Control.new()
	root.name = "PopupRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Interaction prompt: [ E ] / CLICK  DECONTAMINATE
	_interact_prompt = Label.new()
	_interact_prompt.name = "InteractPrompt"
	_interact_prompt.text = "[ E ]  or  CLICK   DECONTAMINATE"
	_interact_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_prompt.add_theme_font_size_override("font_size", 24)
	_interact_prompt.add_theme_color_override("font_color", Color(0.12, 1.0, 0.5, 1.0))
	_interact_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_interact_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_interact_prompt.add_theme_constant_override("shadow_offset_y", 1)
	if font:
		_interact_prompt.add_theme_font_override("font", font)
	_interact_prompt.set_anchor_and_offset(SIDE_LEFT, 0.5, -280.0)
	_interact_prompt.set_anchor_and_offset(SIDE_RIGHT, 0.5, 280.0)
	_interact_prompt.set_anchor_and_offset(SIDE_TOP, 1.0, -118.0)
	_interact_prompt.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -72.0)
	_interact_prompt.visible = false
	root.add_child(_interact_prompt)

	# Pause screen
	_pause_screen = _build_pause_screen(root, font)

	# Win & Game Over screens
	_win_screen = _build_end_screen(
		root, font,
		"DECONTAMINATED",
		"You reached the chamber in time.",
		Color(0.08, 0.92, 0.45),
		Color(0.0, 0.08, 0.04, 0.92),
		"PLAY AGAIN"
	)
	_game_over_screen = _build_end_screen(
		root, font,
		"CONTAMINATED",
		"You didn't make it to the chamber in time.",
		Color(0.95, 0.18, 0.18),
		Color(0.12, 0.02, 0.02, 0.92),
		"TRY AGAIN"
	)


func _build_pause_screen(parent: Control, font: FontFile) -> Control:
	var overlay: Control = Control.new()
	overlay.name = "PauseOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.08, 0.88)
	overlay.add_child(backdrop)

	var center_container: CenterContainer = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center_container)

	var content_box: VBoxContainer = VBoxContainer.new()
	content_box.alignment = BoxContainer.ALIGNMENT_CENTER
	content_box.add_theme_constant_override("separation", 24)
	center_container.add_child(content_box)

	var title_lbl: Label = Label.new()
	title_lbl.text = "PAUSED"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 64)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title_lbl.add_theme_constant_override("shadow_offset_x", 2)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	if font:
		title_lbl.add_theme_font_override("font", font)
	content_box.add_child(title_lbl)

	var sub_lbl: Label = Label.new()
	sub_lbl.text = "MISSION SUSPENDED"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 18)
	sub_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85))
	if font:
		sub_lbl.add_theme_font_override("font", font)
	content_box.add_child(sub_lbl)

	var btn_vbox: VBoxContainer = VBoxContainer.new()
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_vbox.add_theme_constant_override("separation", 14)
	content_box.add_child(btn_vbox)

	var resume_btn := _create_sci_fi_button("RESUME", Vector2(250, 52), font)
	resume_btn.pressed.connect(func():
		toggle_pause(false)
	)
	btn_vbox.add_child(resume_btn)

	var restart_btn := _create_sci_fi_button("RESTART", Vector2(250, 52), font)
	restart_btn.pressed.connect(func():
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
	)
	btn_vbox.add_child(restart_btn)

	var menu_btn := _create_sci_fi_button("MAIN MENU", Vector2(250, 52), font)
	menu_btn.pressed.connect(func():
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	)
	btn_vbox.add_child(menu_btn)

	parent.add_child(overlay)
	return overlay


func _build_end_screen(
		parent: Control,
		font: FontFile,
		title: String,
		subtitle: String,
		accent: Color,
		bg: Color,
		btn_text: String
	) -> Control:

	var overlay: Control = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = bg
	overlay.add_child(backdrop)

	var center_container: CenterContainer = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center_container)

	var content_box: VBoxContainer = VBoxContainer.new()
	content_box.alignment = BoxContainer.ALIGNMENT_CENTER
	content_box.add_theme_constant_override("separation", 22)
	center_container.add_child(content_box)

	var title_lbl: Label = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 68)
	title_lbl.add_theme_color_override("font_color", accent)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title_lbl.add_theme_constant_override("shadow_offset_x", 2)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	if font:
		title_lbl.add_theme_font_override("font", font)
	content_box.add_child(title_lbl)

	var sub_lbl: Label = Label.new()
	sub_lbl.text = subtitle
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 20)
	sub_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	if font:
		sub_lbl.add_theme_font_override("font", font)
	content_box.add_child(sub_lbl)

	# Cleanly aligned button row (Retry & Main Menu)
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 18)
	content_box.add_child(btn_row)

	var retry_btn: Button = _create_sci_fi_button(btn_text, Vector2(210, 52), font)
	retry_btn.pressed.connect(func():
		Engine.time_scale = 1.0
		get_tree().paused = false
		get_tree().reload_current_scene()
	)
	btn_row.add_child(retry_btn)

	var menu_btn: Button = _create_sci_fi_button("MAIN MENU", Vector2(210, 52), font)
	menu_btn.pressed.connect(func():
		Engine.time_scale = 1.0
		get_tree().paused = false
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	)
	btn_row.add_child(menu_btn)

	parent.add_child(overlay)
	return overlay


func _create_sci_fi_button(text_str: String, min_size: Vector2, font: FontFile) -> Button:
	var btn := Button.new()
	btn.text = text_str
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 20)
	if font:
		btn.add_theme_font_override("font", font)

	# Normal style: Black button with crisp white border
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0, 0, 0, 1)
	normal_sb.border_width_left = 2
	normal_sb.border_width_top = 2
	normal_sb.border_width_right = 2
	normal_sb.border_width_bottom = 2
	normal_sb.border_color = Color(1, 1, 1, 0.9)
	normal_sb.corner_radius_top_left = 2
	normal_sb.corner_radius_top_right = 2
	normal_sb.corner_radius_bottom_right = 2
	normal_sb.corner_radius_bottom_left = 2
	normal_sb.content_margin_left = 18
	normal_sb.content_margin_right = 18
	normal_sb.content_margin_top = 10
	normal_sb.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", normal_sb)

	# Hover style: Dark charcoal with solid white border, no blue
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(0.12, 0.12, 0.12, 1)
	hover_sb.border_width_left = 2
	hover_sb.border_width_top = 2
	hover_sb.border_width_right = 2
	hover_sb.border_width_bottom = 2
	hover_sb.border_color = Color(1, 1, 1, 1)
	hover_sb.corner_radius_top_left = 2
	hover_sb.corner_radius_top_right = 2
	hover_sb.corner_radius_bottom_right = 2
	hover_sb.corner_radius_bottom_left = 2
	hover_sb.content_margin_left = 18
	hover_sb.content_margin_right = 18
	hover_sb.content_margin_top = 10
	hover_sb.content_margin_bottom = 10
	btn.add_theme_stylebox_override("hover", hover_sb)

	# Pressed style: Slightly lighter gray with white border
	var pressed_sb := StyleBoxFlat.new()
	pressed_sb.bg_color = Color(0.2, 0.2, 0.2, 1)
	pressed_sb.border_width_left = 2
	pressed_sb.border_width_top = 2
	pressed_sb.border_width_right = 2
	pressed_sb.border_width_bottom = 2
	pressed_sb.border_color = Color(1, 1, 1, 1)
	pressed_sb.corner_radius_top_left = 2
	pressed_sb.corner_radius_top_right = 2
	pressed_sb.corner_radius_bottom_right = 2
	pressed_sb.corner_radius_bottom_left = 2
	pressed_sb.content_margin_left = 18
	pressed_sb.content_margin_right = 18
	pressed_sb.content_margin_top = 10
	pressed_sb.content_margin_bottom = 10
	btn.add_theme_stylebox_override("pressed", pressed_sb)

	# Focus style: Crisp white border, no blue
	var focus_sb := StyleBoxFlat.new()
	focus_sb.draw_center = false
	focus_sb.border_width_left = 2
	focus_sb.border_width_top = 2
	focus_sb.border_width_right = 2
	focus_sb.border_width_bottom = 2
	focus_sb.border_color = Color(1, 1, 1, 0.8)
	focus_sb.corner_radius_top_left = 2
	focus_sb.corner_radius_top_right = 2
	focus_sb.corner_radius_bottom_right = 2
	focus_sb.corner_radius_bottom_left = 2
	btn.add_theme_stylebox_override("focus", focus_sb)

	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9, 1))
	btn.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))

	return btn


func _load_font() -> FontFile:
	var path: String = "res://fonts/Rajdhani-SemiBold.ttf"
	if ResourceLoader.exists(path):
		return load(path) as FontFile
	return null
