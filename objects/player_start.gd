extends Marker3D

# ==============================================================================
# PLAYER START
# Marks the player's spawn location and facing direction.
# On scene load, it teleports any node in the "player" group to its position
# and applies this marker's rotation:
# - Yaw (Y-axis rotation / direction to face) rotates the player body.
# - Pitch (X-axis look up/down tilt) applies to the player's Head/Camera.
# ==============================================================================

func _ready() -> void:
	call_deferred("_teleport_player")


func _teleport_player() -> void:
	for body in get_tree().get_nodes_in_group("player"):
		# Position
		body.global_position = global_position
		
		# Facing direction (Yaw around Y-axis)
		body.global_rotation.y = global_rotation.y
		body.global_rotation.z = 0.0
		
		# Vertical tilt (Pitch around X-axis for Head/Camera if present)
		var head_node: Node3D = body.get_node_or_null("%Head")
		if head_node:
			head_node.rotation.x = clamp(global_rotation.x, deg_to_rad(-80), deg_to_rad(80))
			head_node.rotation.y = 0.0
			head_node.rotation.z = 0.0
			
		break
