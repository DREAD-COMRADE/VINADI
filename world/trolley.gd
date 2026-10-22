extends Node3D
class_name OneWayTrolley

@export_group("Movement")
## Speed in metres per second.
@export_range(0.1, 30.0, 0.1)
var trolley_speed: float = 5.0

## The world-space destination the trolley travels toward.
@export var destination: Marker3D

@export_group("Interaction")
@export_range(0.5, 5.0, 0.1)
var interaction_distance: float = 2.5

## Rider position relative to the trolley root.
@export var rider_offset: Vector3 = Vector3(0.0, 1.0, 0.0)

## Small stopping tolerance in metres.
@export_range(0.01, 1.0, 0.01)
var stop_distance: float = 0.15

var player: CharacterBody3D = null
var original_parent: Node = null

var is_moving: bool = false
var has_been_used: bool = false
var enter_was_pressed: bool = false


func _ready() -> void:
	print("Trolley ready: ", get_path())
	if destination == null:
		push_warning("Trolley: Destination is NOT assigned in the Inspector.")
	elif is_instance_valid(destination):
		print("Trolley destination: ", destination.get_path())


func _process(_delta: float) -> void:
	var interact_pressed := Input.is_action_pressed("interact")

	# Use the project's Input Map action (E) and detect a fresh press.
	if interact_pressed and not enter_was_pressed:
		_try_board()

	enter_was_pressed = interact_pressed


func _physics_process(delta: float) -> void:
	if not is_moving:
		return

	if not is_instance_valid(player):
		_finish_ride()
		return

	if not is_instance_valid(destination):
		push_warning("Trolley: Destination was removed during the ride.")
		_finish_ride()
		return

	var target := destination.global_position
	var remaining := global_position.distance_to(target)
	var step := trolley_speed * delta

	# Stop at the marker and never overshoot it.
	if remaining <= max(step, stop_distance):
		global_position = target
		_finish_ride()
		return

	# Move in a straight line toward the destination.
	global_position = global_position.move_toward(target, step)


func _try_board() -> void:
	print("Trolley: interact action detected. Checking boarding...")

	if has_been_used or is_moving:
		print("Trolley: Cannot board; already used or moving.")
		return

	if not is_instance_valid(destination):
		push_warning("Trolley: Assign a valid Destination Marker3D in the Inspector.")
		return

	var candidate := get_tree().get_first_node_in_group("player")

	if not is_instance_valid(candidate):
		push_warning("Trolley: No node found in the 'player' group.")
		return

	if not candidate is CharacterBody3D:
		push_warning("Trolley: The node in the 'player' group is not CharacterBody3D.")
		return

	var candidate_player := candidate as CharacterBody3D

	if candidate_player.is_riding_trolley:
		return

	var boarding_distance := candidate_player.global_position.distance_to(global_position)
	print("Trolley: Player distance = ", boarding_distance)

	if boarding_distance > interaction_distance:
		print("Trolley: Too far away to board. Move closer.")
		return

	player = candidate_player
	original_parent = player.get_parent()

	# Don't start a ride if the destination is already at the trolley.
	if global_position.distance_to(destination.global_position) <= stop_distance:
		player = null
		original_parent = null
		return
	print("Trolley: Boarding accepted; destination distance = ", global_position.distance_to(destination.global_position))

	# Stop normal player movement while riding.
	player.is_riding_trolley = true
	# Keep controls enabled so mouse-look continues during the ride.
	player.controls_enabled = true
	player.velocity = Vector3.ZERO

	# Parent the player to the trolley so they travel with it.
	player.reparent(self, true)
	player.global_position = to_global(rider_offset)

	has_been_used = true
	is_moving = true
	print("Trolley: Ride started at speed ", trolley_speed)


func _finish_ride() -> void:
	is_moving = false

	if is_instance_valid(player):
		# Preserve the player's world position when detaching.
		if is_instance_valid(original_parent):
			player.reparent(original_parent, true)

		player.is_riding_trolley = false
		player.controls_enabled = true
		player.velocity = Vector3.ZERO

	player = null
	original_parent = null

	# has_been_used remains true permanently.
