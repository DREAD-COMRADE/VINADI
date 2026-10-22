
extends Node3D

## Temporary diagnostic fix for VINADI's main floor.
## Adds a simple box collider over the long starting floor.
## Keep the existing CSG geometry for visuals and other collisions.

@export var floor_center := Vector3(32.5, -0.59, -4.5)
@export var floor_size := Vector3(102.0, 1.5, 10.0)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "MainFloorFallbackCollision"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
	floor_body.position = floor_center
	add_child(floor_body)

	var collision := CollisionShape3D.new()
	collision.name = "MainFloorFallbackShape"

	var box := BoxShape3D.new()
	box.size = floor_size
	collision.shape = box

	floor_body.add_child(collision)
	collision.position = Vector3.ZERO

	print(
		"[FloorFix] Main floor fallback collider created at ",
		floor_center,
		" with size ",
		floor_size
	)
