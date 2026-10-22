extends Node
## VINADI diagnostics logger for Godot 4.x.
## Output: user://diagnostics/session_<timestamp>.jsonl
## Records input events, player movement, collision contacts, floor changes,
## suspected falls, frame spikes, and periodic performance samples.

@export_group("Logging")
@export_range(1, 10, 1) var physics_sample_every_n_frames: int = 1
@export_range(1, 10, 1) var ground_probe_every_n_frames: int = 3
@export_range(1, 120, 1) var flush_every_n_physics_frames: int = 30
@export var frame_spike_threshold_ms: float = 40.0
@export var suspected_fall_drop: float = 0.75
@export var player_group: StringName = &"player"

var _file: FileAccess
var _log_path := ""
var _session_id := ""
var _physics_frame := 0
var _last_floor_state := false
var _have_floor_state := false
var _last_grounded_position := Vector3.ZERO
var _have_grounded_position := false
var _fall_reported := false
var _last_movement_state := -999
var _last_scene_path := ""
var _last_player_instance_id := 0
var _player: CharacterBody3D
var _last_perf_sample_msec := 0


func _ready() -> void:
	# Run after ordinary gameplay physics callbacks so the sample includes
	# the result of CharacterBody3D.move_and_slide() from that tick.
	process_priority = 1000
	process_physics_priority = 1000

	var folder := "user://diagnostics"
	var absolute_folder := ProjectSettings.globalize_path(folder)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_folder)
	if dir_error != OK:
		push_warning("Diagnostic logger could not create log folder. Error: %s" % dir_error)

	_session_id = Time.get_datetime_string_from_system()
	_session_id = _session_id.replace(":", "-").replace(" ", "_")
	_log_path = folder.path_join("session_%s.jsonl" % _session_id)
	_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _file == null:
		push_error("Diagnostic logger could not open %s (error %s)" % [_log_path, FileAccess.get_open_error()])
		return

	var screen_size := DisplayServer.window_get_size()
	_write_event("session_started", {
		"session_id": _session_id,
		"godot_version": Engine.get_version_info(),
		"project_name": ProjectSettings.get_setting("application/config/name", "Unknown"),
		"renderer_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", "Unknown"),
		"renderer_mobile_method": ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "Unknown"),
		"os_name": OS.get_name(),
		"os_version": OS.get_version(),
		"device_model": OS.get_model_name(),
		"screen_size": {"x": screen_size.x, "y": screen_size.y},
		"window_mode": DisplayServer.window_get_mode(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"time_scale": Engine.time_scale,
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine", "Unknown"),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"log_path": ProjectSettings.globalize_path(_log_path)
	})
	_last_scene_path = _scene_path()
	record_event("logger_ready", {"log_path": ProjectSettings.globalize_path(_log_path)})
	_find_player()


func _exit_tree() -> void:
	if _file != null:
		_write_event("session_ended", {})
		_file.flush()
		_file.close()


func _input(event: InputEvent) -> void:
	if _file == null:
		return

	# Mouse motion and touch drags arrive continuously. Camera rotations and
	# currently held input actions are sampled separately to avoid huge logs.
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		return
	if event is InputEventJoypadMotion:
		return
	if event is InputEventKey and (not event.pressed or event.echo):
		return
	if (event is InputEventMouseButton or event is InputEventJoypadButton) and not event.pressed:
		return

	record_event("input_event", {
		"event_type": event.get_class(),
		"description": event.as_text()
	})


func _process(delta: float) -> void:
	if _file == null:
		return

	var frame_ms := delta * 1000.0
	if frame_ms >= frame_spike_threshold_ms:
		record_event("frame_spike", {
			"frame_ms": frame_ms,
			"threshold_ms": frame_spike_threshold_ms,
			"fps_reported": Engine.get_frames_per_second(),
			"scene": _scene_path(),
			"player_position": _vec(_player.global_position) if is_instance_valid(_player) else {}
		})

	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_perf_sample_msec >= 1000:
		_last_perf_sample_msec = now_msec
		record_event("performance_sample", _performance_snapshot(delta))


func _physics_process(_delta: float) -> void:
	if _file == null:
		return

	_physics_frame += 1
	var current_scene := _scene_path()
	if current_scene != _last_scene_path:
		record_event("scene_changed", {"from": _last_scene_path, "to": current_scene})
		_last_scene_path = current_scene
		_player = null
		_have_floor_state = false
		_have_grounded_position = false
		_fall_reported = false
		_last_movement_state = -999

	if not is_instance_valid(_player):
		_find_player()

	if not is_instance_valid(_player):
		if _physics_frame % maxi(1, physics_sample_every_n_frames) == 0:
			_write_event("physics_sample", {
				"physics_frame": _physics_frame,
				"player_found": false,
				"scene": current_scene,
				"fps": Engine.get_frames_per_second()
			})
		_flush_if_due()
		return

	if _physics_frame % maxi(1, physics_sample_every_n_frames) == 0:
		_record_player_sample()
	_flush_if_due()


func _find_player() -> void:
	var candidates := get_tree().get_nodes_in_group(player_group)
	if candidates.is_empty():
		candidates = get_tree().get_nodes_in_group(&"diagnostic_player")

	for candidate in candidates:
		if candidate is CharacterBody3D:
			_player = candidate as CharacterBody3D
			var instance_id := _player.get_instance_id()
			if instance_id != _last_player_instance_id:
				_last_player_instance_id = instance_id
				_have_floor_state = false
				_have_grounded_position = false
				_fall_reported = false
				record_event("player_found", {
					"node_path": str(_player.get_path()),
					"instance_id": instance_id,
					"position": _vec(_player.global_position),
					"collision_layer": _player.collision_layer,
					"collision_mask": _player.collision_mask
				})
			return


func _record_player_sample() -> void:
	if not is_instance_valid(_player):
		return

	var body := _player
	var pos := body.global_position
	var vel := body.velocity
	var grounded := body.is_on_floor()
	var movement_state_id := -1
	var movement_state_name := "UNKNOWN"
	var raw_state: Variant = body.get("movement_state")
	if raw_state != null:
		movement_state_id = int(raw_state)
		# VINADI's current player.gd defines WALK=0, CROUCH=1, SLIDE=2.
		var state_names := ["WALK", "CROUCH", "SLIDE"]
		if movement_state_id >= 0 and movement_state_id < state_names.size():
			movement_state_name = state_names[movement_state_id]

	var data: Dictionary = {
		"physics_frame": _physics_frame,
		"scene": _scene_path(),
		"player_path": str(body.get_path()),
		"player_position": _vec(pos),
		"player_rotation": _vec(body.global_rotation),
		"velocity": _vec(vel),
		"speed": vel.length(),
		"horizontal_speed": Vector2(vel.x, vel.z).length(),
		"is_on_floor": grounded,
		"is_on_wall": body.is_on_wall(),
		"is_on_ceiling": body.is_on_ceiling(),
		"floor_normal": _vec(body.get_floor_normal()),
		"floor_snap_length": body.floor_snap_length,
		"floor_max_angle_degrees": rad_to_deg(body.floor_max_angle),
		"collision_layer": body.collision_layer,
		"collision_mask": body.collision_mask,
		"slide_collision_count": body.get_slide_collision_count(),
		"movement_state_id": movement_state_id,
		"movement_state": movement_state_name,
		"is_sprinting": bool(body.get("is_sprinting")),
		"controls_enabled": bool(body.get("controls_enabled")),
		"health": body.get("health"),
		"input_actions_held": _pressed_actions(),
		"fps": Engine.get_frames_per_second(),
		"process_time_ms": _monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_process_time_ms": _monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"static_memory_bytes": _monitor(Performance.MEMORY_STATIC),
		"object_count": _monitor(Performance.OBJECT_COUNT),
		"node_count": _monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_node_count": _monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"physics_3d_active_objects": _monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"physics_3d_collision_pairs": _monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"render_objects": _monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"render_primitives": _monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_draw_calls": _monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	}

	var shape_info := _get_collision_shape_info(body)
	if not shape_info.is_empty():
		data["collision_shape"] = shape_info

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		data["camera_position"] = _vec(camera.global_position)
		data["camera_rotation"] = _vec(camera.global_rotation)

	var collisions: Array[Dictionary] = []
	for i in range(body.get_slide_collision_count()):
		var hit := body.get_slide_collision(i)
		var collider: Object = hit.get_collider()
		var collider_name := str(collider)
		var collider_class := "null"
		if collider != null:
			collider_class = collider.get_class()
			if collider is Node:
				collider_name = str((collider as Node).get_path())
		collisions.append({
			"collider": collider_name,
			"collider_class": collider_class,
			"collider_rid": str(hit.get_collider_rid()),
			"normal": _vec(hit.get_normal()),
			"contact_position": _vec(hit.get_position()),
			"travel": _vec(hit.get_travel()),
			"remainder": _vec(hit.get_remainder()),
			"collider_velocity": _vec(hit.get_collider_velocity()),
			"local_shape_index": hit.get_local_shape(),
			"collider_shape_index": hit.get_collider_shape()
		})
	data["slide_collisions"] = collisions

	if _physics_frame % maxi(1, ground_probe_every_n_frames) == 0:
		data["ground_probe"] = _ground_probe(body)

	_write_event("physics_sample", data)

	if _have_floor_state and _last_floor_state != grounded:
		record_event("floor_state_changed", {
			"from_grounded": _last_floor_state,
			"to_grounded": grounded,
			"position": _vec(pos),
			"velocity": _vec(vel),
			"movement_state": movement_state_name,
			"collisions": collisions,
			"ground_probe": _ground_probe(body)
		})

	if grounded:
		_last_grounded_position = pos
		_have_grounded_position = true
		_fall_reported = false

	if _have_grounded_position and not grounded:
		var vertical_drop := _last_grounded_position.y - pos.y
		if vertical_drop >= suspected_fall_drop and not _fall_reported:
			_fall_reported = true
			record_event("suspected_fall", {
				"position": _vec(pos),
				"last_grounded_position": _vec(_last_grounded_position),
				"vertical_drop": vertical_drop,
				"velocity": _vec(vel),
				"horizontal_speed": Vector2(vel.x, vel.z).length(),
				"movement_state": movement_state_name,
				"collision_shape": shape_info,
				"last_slide_collisions": collisions,
				"ground_probe": _ground_probe(body)
			})

	if movement_state_id != _last_movement_state:
		record_event("movement_state_changed", {
			"state_id": movement_state_id,
			"state": movement_state_name,
			"position": _vec(pos),
			"velocity": _vec(vel),
			"is_on_floor": grounded,
			"collision_shape": shape_info
		})
		_last_movement_state = movement_state_id

	_last_floor_state = grounded
	_have_floor_state = true


func _ground_probe(body: CharacterBody3D) -> Dictionary:
	# VINADI's player origin is intended to sit at the capsule's planted base.
	var origin := body.global_position + Vector3.UP * 0.15
	var endpoint := body.global_position - Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, body.collision_mask)
	query.exclude = [body.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := body.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return {"hit": false, "origin": _vec(origin), "endpoint": _vec(endpoint)}

	var collider: Object = result.get("collider")
	var collider_path := str(collider)
	if collider is Node:
		collider_path = str((collider as Node).get_path())
	return {
		"hit": true,
		"collider": collider_path,
		"collider_class": collider.get_class() if collider != null else "null",
		"position": _vec(result["position"]),
		"normal": _vec(result["normal"]),
		"distance_from_origin": origin.distance_to(result["position"]),
		"shape_index": result.get("shape", -1)
	}


func _get_collision_shape_info(body: CharacterBody3D) -> Dictionary:
	var nodes := body.find_children("*", "CollisionShape3D", true, false)
	for node in nodes:
		var shape_node := node as CollisionShape3D
		if shape_node == null:
			continue
		var shape: Shape3D = shape_node.shape
		var info := {
			"node_path": str(shape_node.get_path()),
			"global_position": _vec(shape_node.global_position),
			"local_position": _vec(shape_node.position),
			"disabled": shape_node.disabled,
			"shape_class": shape.get_class() if shape != null else "null"
		}
		if shape is CapsuleShape3D:
			var cap := shape as CapsuleShape3D
			info["capsule_height"] = cap.height
			info["capsule_radius"] = cap.radius
		elif shape is BoxShape3D:
			info["box_size"] = _vec(shape.size)
		elif shape is SphereShape3D:
			info["sphere_radius"] = shape.radius
		return info
	return {}


func _pressed_actions() -> Array[String]:
	var result: Array[String] = []
	for action in InputMap.get_actions():
		var action_name := str(action)
		if action_name.begins_with("ui_"):
			continue
		if Input.is_action_pressed(action):
			result.append(action_name)
	result.sort()
	return result


func _performance_snapshot(delta: float) -> Dictionary:
	return {
		"scene": _scene_path(),
		"fps": Engine.get_frames_per_second(),
		"last_frame_ms": delta * 1000.0,
		"process_time_ms": _monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_process_time_ms": _monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"static_memory_bytes": _monitor(Performance.MEMORY_STATIC),
		"object_count": _monitor(Performance.OBJECT_COUNT),
		"node_count": _monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_node_count": _monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"physics_3d_active_objects": _monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"physics_3d_collision_pairs": _monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"render_objects": _monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"render_primitives": _monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_draw_calls": _monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	}


func _monitor(monitor_id: int) -> float:
	return Performance.get_monitor(monitor_id)


func record_event(event_name: String, data: Dictionary = {}) -> void:
	_write_event(event_name, data)


func _write_event(event_name: String, data: Dictionary) -> void:
	if _file == null:
		return
	var record := {
		"timestamp": Time.get_datetime_string_from_system(),
		"elapsed_usec": Time.get_ticks_usec(),
		"event": event_name,
		"data": data
	}
	_file.store_line(JSON.stringify(record))


func _flush_if_due() -> void:
	if _file != null and flush_every_n_physics_frames > 0:
		if _physics_frame % flush_every_n_physics_frames == 0:
			_file.flush()


func _scene_path() -> String:
	var scene := get_tree().current_scene
	return str(scene.scene_file_path) if scene != null else ""


func _vec(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}
