extends CanvasLayer
class_name VINADI_UI

## ==============================================================================
## VINADI — HUD CONTROLLER
## Minimal cinematic industrial 2D HUD.
## Displays countdown, objective, contamination/filter integrity, hints, & crosshair.
## Does NOT run an internal duplicate timer: driven purely via clean API methods.
## ==============================================================================

signal contamination_depleted
signal contamination_changed(new_value: float)

# ── Configurable In Inspector ────────────────────────────────────────────────
@export_group("Objective Settings")
@export var objective_heading_text: String = "OBJECTIVE"
@export var objective_body_text: String = "EVACUATE TO DECONTAMINATION CHAMBER"

@export_group("Contamination Settings")
## Seconds to drain from 100% to 0% under normal passive conditions
@export var normal_drain_duration: float = 25.0
## Instant percentage penalty applied per hazard hit (e.g. 15.0 = -15%)
@export var default_hazard_penalty: float = 15.0
## Critical threshold where bar turns urgent emergency red
@export var critical_contamination_threshold: float = 25.0

@export_group("Timer Settings")
## Time threshold below which digits turn emergency red
@export var timer_emergency_threshold: float = 5.0

@export_group("Visual Overrides (Leave override false to use your Theme/Inspector styling)")
## When enabled, overrides the progress bar fill color via code. Keep false to use your custom Theme styles!
@export var override_progress_bar_colors: bool = false
@export var normal_timer_color: Color = Color.WHITE
@export var emergency_timer_color: Color = Color(1.0, 0.18, 0.18)
@export var normal_bar_color: Color = Color(0.24, 0.65, 1.0, 0.95)
@export var emergency_bar_color: Color = Color(1.0, 0.18, 0.18, 0.95)

# ── Node References ──────────────────────────────────────────────────────────
@onready var hud_container: Control = $HUDContainer

# Objective
@onready var objective_heading: Label = %ObjectiveHeading
@onready var objective_label: Label = %ObjectiveLabel

# Countdown
@onready var timer_digits: Label = %TimerDigits
@onready var timer_bar: ProgressBar = %TimerBar

# Contamination / Filter Integrity
@onready var mask_icon: TextureRect = %MaskIcon
@onready var contamination_bar: ProgressBar = %ContaminationBar
@onready var contamination_percent_label: Label = %ContaminationPercentLabel

# Movement Hints
@onready var hints_group: Control = %MovementHints
@onready var hint_sprint: Label = %HintSprint
@onready var hint_jump: Label = %HintJump
@onready var hint_slide: Label = %HintSlide

# Crosshair
@onready var crosshair_dot: ColorRect = %CrosshairDot

# ── Runtime State ────────────────────────────────────────────────────────────
## Current contamination tolerance / filter integrity (0.0 to 100.0)
var current_contamination: float = 100.0
var _is_depleted: bool = false
var _contam_fill_style: StyleBoxFlat
var _timer_fill_style: StyleBoxFlat


func _ready() -> void:
	add_to_group("hud")
	_init_styles()
	apply_objective(objective_heading_text, objective_body_text)
	set_contamination(100.0)
	set_countdown(20.0, 20.0)


func _init_styles() -> void:
	if not override_progress_bar_colors:
		return
	# Clone styles so live color changes don't overwrite shared resources
	if contamination_bar:
		var fill: StyleBox = contamination_bar.get_theme_stylebox("fill")
		if fill is StyleBoxFlat:
			_contam_fill_style = fill.duplicate()
			contamination_bar.add_theme_stylebox_override("fill", _contam_fill_style)

	if timer_bar:
		var t_fill: StyleBox = timer_bar.get_theme_stylebox("fill")
		if t_fill is StyleBoxFlat:
			_timer_fill_style = t_fill.duplicate()
			timer_bar.add_theme_stylebox_override("fill", _timer_fill_style)


# ==============================================================================
# PUBLIC INTERFACE — COUNTDOWN
# ==============================================================================

## Updates the countdown timer display.
## time_remaining: current seconds (e.g. 13.45)
## max_time: total / initial duration for progress bar ratio (defaults to 20.0)
func set_countdown(time_remaining: float, max_time: float = 20.0) -> void:
	var t: float = max(0.0, time_remaining)

	if timer_digits:
		timer_digits.text = "%05.2f SEC" % t
		if t <= timer_emergency_threshold and t > 0.0:
			timer_digits.modulate = emergency_timer_color
		else:
			timer_digits.modulate = normal_timer_color

	if timer_bar:
		timer_bar.max_value = max_time
		timer_bar.value = t
		if override_progress_bar_colors and _timer_fill_style:
			_timer_fill_style.bg_color = emergency_bar_color if t <= timer_emergency_threshold else normal_bar_color


# ==============================================================================
# PUBLIC INTERFACE — CONTAMINATION / FILTER INTEGRITY
# ==============================================================================

## Sets the exact contamination percentage (clamped 0 to 100).
func set_contamination(value_percent: float) -> void:
	var clamped_val: float = clamp(value_percent, 0.0, 100.0)
	current_contamination = clamped_val

	if contamination_bar:
		contamination_bar.value = clamped_val

	if contamination_percent_label:
		contamination_percent_label.text = "%d%%" % int(round(clamped_val))

	# Urgency color modulation
	var is_critical: bool = clamped_val <= critical_contamination_threshold

	if override_progress_bar_colors and _contam_fill_style:
		var active_color: Color = emergency_bar_color if is_critical else normal_bar_color
		_contam_fill_style.bg_color = active_color

	if mask_icon:
		mask_icon.modulate = emergency_timer_color if is_critical else Color.WHITE

	emit_signal("contamination_changed", clamped_val)

	if clamped_val <= 0.0 and not _is_depleted:
		_is_depleted = true
		emit_signal("contamination_depleted")
	elif clamped_val > 0.0:
		_is_depleted = false


## Passive tick update: call each frame from gameplay/player controller.
## Drains 100% over normal_drain_duration seconds.
func apply_passive_drain(delta: float) -> void:
	if normal_drain_duration <= 0.0:
		return
	var drain_per_sec: float = 100.0 / normal_drain_duration
	set_contamination(current_contamination - (drain_per_sec * delta))


## Applies an immediate penalty when touching a hazard zone.
## penalty_percent: if <= 0, uses default_hazard_penalty.
func apply_hazard_penalty(penalty_percent: float = -1.0) -> void:
	var penalty: float = default_hazard_penalty if penalty_percent <= 0.0 else penalty_percent
	set_contamination(current_contamination - penalty)


## Returns current contamination tolerance percentage.
func get_contamination() -> float:
	return current_contamination


## Returns true if tolerance has hit 0%.
func is_depleted() -> bool:
	return _is_depleted


# ==============================================================================
# PUBLIC INTERFACE — OBJECTIVE
# ==============================================================================

func apply_objective(heading: String, body: String) -> void:
	if objective_heading:
		objective_heading.text = heading
	if objective_label:
		objective_label.text = body


# ==============================================================================
# PUBLIC INTERFACE — MOVEMENT HINTS
# ==============================================================================

func set_hints_visible(is_shown: bool) -> void:
	if hints_group:
		hints_group.visible = is_shown


func update_hints(sprint_text: String = "", jump_text: String = "", slide_text: String = "") -> void:
	if hint_sprint and not sprint_text.is_empty():
		hint_sprint.text = sprint_text
	if hint_jump and not jump_text.is_empty():
		hint_jump.text = jump_text
	if hint_slide and not slide_text.is_empty():
		hint_slide.text = slide_text


# ==============================================================================
# PUBLIC INTERFACE — CROSSHAIR
# ==============================================================================

func set_crosshair_visible(is_shown: bool) -> void:
	if crosshair_dot:
		crosshair_dot.visible = is_shown


func set_crosshair_size(pixels: Vector2) -> void:
	if crosshair_dot:
		crosshair_dot.custom_minimum_size = pixels
		crosshair_dot.size = pixels
		# Keep perfectly centered around anchor (0.5, 0.5)
		crosshair_dot.offset_left = -pixels.x * 0.5
		crosshair_dot.offset_top = -pixels.y * 0.5
		crosshair_dot.offset_right = pixels.x * 0.5
		crosshair_dot.offset_bottom = pixels.y * 0.5
