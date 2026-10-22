extends Node3D
class_name TimedChamberDoor

## Assign the node that should move as the door (usually a MeshInstance3D
## or a Node3D containing the door mesh). If left empty, this node moves.
@export_group("Door")
@export var door_to_move: Node3D

## Position offset from the fully open position to the fully closed position.
## Set this in the door node's LOCAL coordinates.
@export var closed_offset: Vector3 = Vector3(0.0, -3.0, 0.0)

@export_group("Countdown")
## Total countdown duration for the game.
@export_range(1.0, 300.0, 0.5)
var game_duration: float = 20.0

## Number of seconds remaining when the door starts closing.
@export_range(1.0, 30.0, 0.5)
var close_start_seconds_remaining: float = 6.0

## Number of seconds remaining when the door must be completely closed.
@export_range(0.0, 10.0, 0.5)
var fully_closed_seconds_remaining: float = 1.0

@export_group("Animation")
## Optional smoothing. 1.0 = linear, values above 1 keep it open longer
## then accelerate toward the end.
@export_range(0.5, 3.0, 0.1)
var closing_ease: float = 1.5

## If true, capture the open position automatically when the scene starts.
@export var capture_open_position_on_ready: bool = true

var _elapsed: float = 0.0
var _open_position: Vector3
var _closed_position: Vector3
var _is_closed: bool = false


func _ready() -> void:
	if door_to_move == null:
		door_to_move = self

	if capture_open_position_on_ready:
		_open_position = door_to_move.position
	else:
		_open_position = door_to_move.position

	_closed_position = _open_position + closed_offset

	if fully_closed_seconds_remaining >= close_start_seconds_remaining:
		push_warning(
            "Door: fully_closed_seconds_remaining should be less than "
			+ "close_start_seconds_remaining."
		)


## Call this from the game's countdown if you already have one.
## Pass the elapsed time since the countdown began.
func set_elapsed_time(seconds_elapsed: float) -> void:
	_elapsed = clampf(seconds_elapsed, 0.0, game_duration)
	_update_door()


func _process(delta: float) -> void:
	# Standalone fallback: this script runs its own 20-second timer.
	# If your game already has a countdown, use set_elapsed_time() instead
	# and remove/comment this timer increment to avoid running two timers.
	_elapsed = minf(_elapsed + delta, game_duration)
	_update_door()


func _update_door() -> void:
	if _is_closed:
		return

	var seconds_remaining := game_duration - _elapsed

	if seconds_remaining > close_start_seconds_remaining:
		return

	var closing_duration := (
		close_start_seconds_remaining - fully_closed_seconds_remaining
	)

	if closing_duration <= 0.0:
		door_to_move.position = _closed_position
		_is_closed = true
		return

	var progress := (
		close_start_seconds_remaining - seconds_remaining
	) / closing_duration
	progress = clampf(progress, 0.0, 1.0)

	# Ease the movement so it starts gently and finishes by the final second.
	var eased_progress := pow(progress, closing_ease)
	door_to_move.position = _open_position.lerp(
		_closed_position,
		eased_progress
	)

	if seconds_remaining <= fully_closed_seconds_remaining:
		door_to_move.position = _closed_position
		_is_closed = true
