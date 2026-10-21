extends Control

# ==============================================================================
# VINADI — HUD PREVIEW CONTROLLER
# Independent standalone test harness. Runs simulated countdown and
# contamination drain without needing 3D world, physics, or player.
# ==============================================================================

@export var simulate_countdown: bool = true
@export var simulate_drain: bool = true

@export var test_time_duration: float = 20.0
@export var test_drain_duration: float = 25.0

var _sim_timer: float
var _sim_contamination: float = 100.0

@onready var hud: VINADI_UI = $UI
@onready var sim_info: Label = %SimInfo


func _ready() -> void:
	_sim_timer = test_time_duration
	_sim_contamination = 100.0

	if hud:
		hud.normal_drain_duration = test_drain_duration
		hud.set_countdown(_sim_timer, test_time_duration)
		hud.set_contamination(_sim_contamination)
		hud.contamination_depleted.connect(_on_contamination_depleted)

	_update_sim_info()


func _process(delta: float) -> void:
	if simulate_countdown and _sim_timer > 0.0:
		_sim_timer = max(0.0, _sim_timer - delta)
		if hud:
			hud.set_countdown(_sim_timer, test_time_duration)

	if simulate_drain and _sim_contamination > 0.0:
		var drain_rate: float = 100.0 / test_drain_duration
		_sim_contamination = max(0.0, _sim_contamination - (drain_rate * delta))
		if hud:
			hud.set_contamination(_sim_contamination)

	_update_sim_info()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return

	match event.keycode:
		KEY_H: # Simulate hazard hit
			_trigger_hazard_penalty(15.0)
		KEY_R: # Reset simulation
			_reset_simulation()
		KEY_T: # Toggle movement hints
			if hud:
				hud.set_hints_visible(not hud.hints_group.visible)
		KEY_C: # Toggle crosshair
			if hud:
				hud.set_crosshair_visible(not hud.crosshair_dot.visible)


func _trigger_hazard_penalty(amount: float) -> void:
	_sim_contamination = max(0.0, _sim_contamination - amount)
	if hud:
		hud.set_contamination(_sim_contamination)


func _reset_simulation() -> void:
	_sim_timer = test_time_duration
	_sim_contamination = 100.0
	if hud:
		hud.set_countdown(_sim_timer, test_time_duration)
		hud.set_contamination(_sim_contamination)


func _on_contamination_depleted() -> void:
	print("[UI Preview] Contamination depleted! Filter failure triggered.")


func _update_sim_info() -> void:
	if sim_info:
		sim_info.text = "HUD PREVIEW HARNESS  |  [H] Trigger Hazard (-15%%)  |  [R] Reset  |  [T] Toggle Hints  |  [C] Toggle Crosshair  |  Time: %.2fs  |  Filter: %.1f%%" % [_sim_timer, _sim_contamination]
