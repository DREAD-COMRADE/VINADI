extends CharacterBody3D

# ==============================================================================
# VINADI – FPP CHARACTER CONTROLLER
# Movements: Walk · Sprint · Jump (with sprint-jump boost) · Crouch · Slide
#
# All values are @exported — fully tunable in the Godot inspector.
# All input actions are defined in project.godot and will be rebindable
# by the player via a key-binding menu (built in a later milestone).
# ==============================================================================

# ── Movement ──────────────────────────────────────────────────────────────────
@export_group("Movement")
@export var walk_speed:            float = 4.5
@export var sprint_speed:          float = 7.0
@export var crouch_speed:          float = 2.2
@export var acceleration:          float = 8.0
@export var friction:              float = 6.0
@export var air_control:           float = 0.85

# ── Jump ──────────────────────────────────────────────────────────────────────
@export_group("Jump")
## Base upward impulse when jumping
@export var jump_velocity:         float = 6.5
## Extra height added when sprint-jumping
@export var sprint_jump_bonus:     float = 1.4
## Extra horizontal forward speed injected when sprint-jumping
@export var sprint_jump_h_boost:   float = 2.5
## Seconds before the player can jump again
@export var jump_cooldown:         float = 0.4

# ── Slide ─────────────────────────────────────────────────────────────────────
@export_group("Slide")
## Minimum horizontal speed required to start a slide
@export var slide_min_speed:       float = 5.0
## Horizontal speed set at slide start
@export var slide_impulse:         float = 10.5
## How fast the slide decelerates
@export var slide_friction:        float = 5.0
## Slide cancels automatically when speed falls below this
@export var slide_end_speed:       float = 1.8
## Hard cap on slide duration (seconds)
@export var slide_max_duration:    float = 1.2

# ── Physics ───────────────────────────────────────────────────────────────────
@export_group("Physics")
@export var gravity:               float = 22.0

# ── Capsule heights ───────────────────────────────────────────────────────────
@export_group("Capsule Heights")
@export var stand_height:          float = 1.8
@export var crouch_height:         float = 1.0
@export var slide_height:          float = 0.85
@export var height_toggle_speed:   float = 10.0

# ── Camera / Mouse ────────────────────────────────────────────────────────────
@export_group("Camera")
@export var mouse_sensitivity:     float = 0.002

# ── Camera Bob ────────────────────────────────────────────────────────────────
@export_group("Camera Bob")
@export var bob_frequency:         float = 2.4
@export var bob_amplitude:         float = 0.03
@export var dip_recovery_speed:    float = 4.5

# ── Viewmodel sway (read by WeaponHolder if present) ─────────────────────────
@export_group("Viewmodel Sway")
@export var sway_amount:           float = 0.0015
@export var sway_smooth:           float = 10.0

# ── Fall damage ───────────────────────────────────────────────────────────────
@export_group("Fall Damage")
@export var min_fall_distance:     float = 2.0
@export var damage_multiplier:     float = 25.0

# ==============================================================================
# NODE REFERENCES
# ==============================================================================
@onready var head:            Node3D            = %Head
@onready var camera:          Camera3D          = %Camera3D
@onready var collision_shape: CollisionShape3D  = %CollisionShape3D

# ==============================================================================
# INTERNAL STATE
# ==============================================================================
enum MovementState { WALK, CROUCH, SLIDE }
var movement_state: MovementState = MovementState.WALK

var is_sprinting:     bool    = false
var jump_timer:       float   = 0.0

# Slide
var slide_timer:      float   = 0.0
var slide_direction:  Vector3 = Vector3.ZERO

# Camera
var bob_time:            float = 0.0
var landing_dip_offset:  float = 0.0

# Fall damage
var highest_air_y:       float = 0.0
var is_in_air_last_frame: bool = false

# Exposed so a WeaponHolder / viewmodel node can read this each frame
var mouse_input:         Vector2 = Vector2.ZERO

# Health
var health:     float = 100.0
var max_health: float = 100.0

# Debug overrides (toggled via DebugPanel)
var god_mode:               bool  = false
var no_fall_damage:         bool  = false
var debug_speed_multiplier: float = 1.0


# Controls state
var controls_enabled: bool = true


func disable_controls() -> void:
	controls_enabled = false
	velocity = Vector3.ZERO


func enable_controls() -> void:
	controls_enabled = true


func is_control_disabled() -> bool:
	if not controls_enabled:
		return true
	var guis := get_tree().get_nodes_in_group("game_ui")
	if guis.size() > 0:
		var g = guis[0]
		if bool(g.get("game_ended")) or bool(g.get("is_paused")):
			return true
	return false


# ==============================================================================
# _READY
# ==============================================================================
func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode    = Input.MOUSE_MODE_CAPTURED
	floor_snap_length   = 0.6
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_max_angle     = deg_to_rad(60.0)
	max_slides          = 6


# ==============================================================================
# INPUT  (mouse-look + one-shot actions)
# ==============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if is_control_disabled():
		return

	# ── Mouse look ────────────────────────────────────────────────────────────
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_input = event.relative
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))

	# ── Re-capture cursor on click (only when game is actively running) ───────
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and \
				Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			var can_recapture: bool = true
			if get_tree().paused or is_control_disabled():
				can_recapture = false
			if can_recapture:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()


# ==============================================================================
# PHYSICS LOOP
# ==============================================================================
func _physics_process(delta: float) -> void:
	# Void fall safety check: prevents player from falling infinitely
	if global_position.y < -15.0:
		var guis := get_tree().get_nodes_in_group("game_ui")
		if guis.size() > 0 and guis[0].has_method("trigger_game_over"):
			guis[0].trigger_game_over()
		return

	if is_control_disabled():
		_handle_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, friction * 5.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * 5.0 * delta)
		move_and_slide()
		return

	if jump_timer > 0.0:
		jump_timer -= delta

	_handle_gravity(delta)
	_handle_crouch_slide(delta)   # crouch / slide state machine
	_handle_jump()
	_handle_movement(delta)
	_handle_camera(delta)
	_handle_fall_damage()


# ==============================================================================
# GRAVITY
# ==============================================================================
func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# Downward bias ensures continuous contact on downward slopes and CSG seams
		if velocity.y <= 0.0:
			velocity.y = -0.5


# ==============================================================================
# CROUCH & SLIDE state machine
# Called every physics tick; delta is used to increment slide_timer.
# ==============================================================================
func _handle_crouch_slide(delta: float) -> void:
	var crouch_just_pressed := Input.is_action_just_pressed("crouch")
	var crouch_held         := Input.is_action_pressed("crouch")

	# ── Try to START a slide ──────────────────────────────────────────────────
	if crouch_just_pressed and is_on_floor() and movement_state != MovementState.SLIDE:
		var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
		if h_speed >= slide_min_speed:
			_begin_slide()
			return   # skip remaining logic this frame

	# ── MAINTAIN / END active slide ───────────────────────────────────────────
	if movement_state == MovementState.SLIDE:
		slide_timer += delta
		var h_speed  := Vector3(velocity.x, 0.0, velocity.z).length()

		if slide_timer >= slide_max_duration or h_speed < slide_end_speed or not crouch_held:
			_end_slide()
		return   # while sliding, skip normal crouch logic below

	# ── NORMAL CROUCH (on ground) ─────────────────────────────────────────────
	if is_on_floor():
		if crouch_held:
			if movement_state != MovementState.CROUCH:
				movement_state = MovementState.CROUCH
				_snap_capsule_height(crouch_height)
		else:
			if movement_state == MovementState.CROUCH and _can_stand():
				movement_state = MovementState.WALK
				_snap_capsule_height(stand_height)
	else:
		# Airborne: allow ducking mid-air, and re-stand when the button is released
		if crouch_held and movement_state != MovementState.CROUCH:
			movement_state = MovementState.CROUCH
			_snap_capsule_height(crouch_height)
		elif not crouch_held and movement_state == MovementState.CROUCH and _can_stand():
			movement_state = MovementState.WALK
			_snap_capsule_height(stand_height)


func _begin_slide() -> void:
	movement_state  = MovementState.SLIDE
	slide_timer     = 0.0
	var h_vel       := Vector3(velocity.x, 0.0, velocity.z)
	slide_direction  = h_vel.normalized() if h_vel.length() > 0.01 else -transform.basis.z.normalized()
	# Kick velocity to the slide impulse speed
	velocity.x      = slide_direction.x * slide_impulse
	velocity.z      = slide_direction.z * slide_impulse
	_snap_capsule_height(slide_height)


func _end_slide() -> void:
	if _can_stand():
		movement_state = MovementState.WALK
		_snap_capsule_height(stand_height)
	else:
		# Low ceiling overhead – stay crouched
		movement_state = MovementState.CROUCH
		_snap_capsule_height(crouch_height)


# ==============================================================================
# JUMP  (sprint-jump gives extra height + forward horizontal burst)
# ==============================================================================
func _handle_jump() -> void:
	if not Input.is_action_just_pressed("jump"):
		return
	if not is_on_floor() or jump_timer > 0.0:
		return

	# Pressing jump while sliding cancels the slide (no jump)
	if movement_state == MovementState.SLIDE:
		_end_slide()
		return

	# Can't jump while crouched if there's no headroom
	if movement_state == MovementState.CROUCH and not _can_stand():
		return

	is_sprinting = Input.is_action_pressed("sprint")

	if is_sprinting:
		velocity.y       = jump_velocity + sprint_jump_bonus
		var fwd           = -transform.basis.z.normalized()
		velocity.x       += fwd.x * sprint_jump_h_boost
		velocity.z       += fwd.z * sprint_jump_h_boost
	else:
		velocity.y = jump_velocity

	jump_timer = jump_cooldown

	# Automatically stand when jumping from a crouch
	if movement_state == MovementState.CROUCH:
		movement_state = MovementState.WALK
		_snap_capsule_height(stand_height)


# ==============================================================================
# MOVEMENT  (walk / sprint / crouch / slide)
# ==============================================================================
func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# ── Sliding: only decelerate; player cannot steer ─────────────────────────
	if movement_state == MovementState.SLIDE:
		var slide_vel := Vector3(velocity.x, 0.0, velocity.z)
		slide_vel      = slide_vel.move_toward(Vector3.ZERO, slide_friction * delta)
		velocity.x     = slide_vel.x
		velocity.z     = slide_vel.z
		move_and_slide()
		return

	# ── Normal / crouched movement ────────────────────────────────────────────
	var current_speed: float
	match movement_state:
		MovementState.CROUCH:
			current_speed = crouch_speed
			is_sprinting  = false
		_:
			is_sprinting  = Input.is_action_pressed("sprint") and is_on_floor() \
							and input_dir != Vector2.ZERO
			current_speed = sprint_speed if is_sprinting else walk_speed

	current_speed *= debug_speed_multiplier

	var direction  := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_vel  := direction * current_speed
	var h_vel       := Vector3(velocity.x, 0.0, velocity.z)

	if direction.length() > 0.0:
		var accel := acceleration if is_on_floor() else acceleration * air_control
		h_vel = h_vel.move_toward(target_vel, accel * current_speed * delta)
	else:
		if is_on_floor():
			h_vel = h_vel.move_toward(Vector3.ZERO, friction * walk_speed * delta)
		else:
			h_vel = h_vel.move_toward(Vector3.ZERO, 0.5 * delta)

	velocity.x = h_vel.x
	velocity.z = h_vel.z
	move_and_slide()


# ==============================================================================
# CAMERA  (head position by state + bob + landing dip)
# ==============================================================================
func _handle_camera(delta: float) -> void:
	# ── Lerp head Y to the correct eye-level for the current state ─────────────
	var target_head_y: float = match_head_y()
	head.position.y = move_toward(head.position.y, target_head_y, height_toggle_speed * delta)

	# ── Landing dip recovery ───────────────────────────────────────────────────
	landing_dip_offset = move_toward(landing_dip_offset, 0.0, dip_recovery_speed * delta)

	# ── Head bob (skip while sliding) ─────────────────────────────────────────
	var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if is_on_floor() and h_speed > 0.1 and movement_state != MovementState.SLIDE:
		bob_time += delta * h_speed * bob_frequency
		camera.position.y = sin(bob_time) * bob_amplitude - landing_dip_offset
		camera.position.x = cos(bob_time * 0.5) * bob_amplitude * 0.5
	else:
		bob_time = 0.0
		camera.position.y = move_toward(camera.position.y, -landing_dip_offset, delta * 3.0)
		camera.position.x = move_toward(camera.position.x,  0.0,                delta * 3.0)


func match_head_y() -> float:
	match movement_state:
		MovementState.CROUCH: return 0.4
		MovementState.SLIDE:  return 0.2
		_:                    return 0.8


# ==============================================================================
# FALL DAMAGE
# ==============================================================================
func _handle_fall_damage() -> void:
	if no_fall_damage or god_mode:
		is_in_air_last_frame = false
		highest_air_y = global_position.y
		return

	if not is_on_floor():
		if not is_in_air_last_frame or global_position.y > highest_air_y:
			highest_air_y = global_position.y
		is_in_air_last_frame = true
	else:
		if is_in_air_last_frame:
			var fall_distance := highest_air_y - global_position.y
			if fall_distance > min_fall_distance:
				take_damage((fall_distance - min_fall_distance) * damage_multiplier)
				if not is_inside_tree():
					return
			if fall_distance > 1.5:
				landing_dip_offset = clamp(fall_distance * 0.08, 0.0, 0.45)
		is_in_air_last_frame = false
		highest_air_y        = global_position.y


# ==============================================================================
# HELPERS
# ==============================================================================
## Returns true if there is enough vertical clearance to stand.
func _can_stand() -> bool:
	var test_shape: CapsuleShape3D = collision_shape.shape.duplicate()
	test_shape.height = stand_height

	var params          := PhysicsShapeQueryParameters3D.new()
	params.shape         = test_shape
	params.exclude       = [self]

	var bottom_y: float  = collision_shape.global_position.y - collision_shape.shape.height * 0.5
	var center_y: float  = bottom_y + stand_height * 0.5 + 0.05
	params.transform     = collision_shape.global_transform
	params.transform.origin.y = center_y

	return get_world_3d().direct_space_state.intersect_shape(params).is_empty()


## Instantly set the capsule to the new height while keeping the base planted.
func _snap_capsule_height(new_height: float) -> void:
	collision_shape.shape.height = new_height
	# Keep the capsule's centre at the correct height above the player origin
	collision_shape.position.y   = new_height * 0.5


# ==============================================================================
# PUBLIC API  (callable by other game systems)
# ==============================================================================
func take_damage(amount: float) -> void:
	if god_mode:
		return
	health = max(0.0, health - amount)
	if health <= 0.0:
		_on_death()


func heal(amount: float) -> void:
	health = min(health + amount, max_health)


func _on_death() -> void:
	# Placeholder: reload scene. Replace with a death-screen flow later.
	get_tree().call_deferred("reload_current_scene")


## Query helpers – useful for animation controllers and game-logic nodes.
func is_sliding()  -> bool: return movement_state == MovementState.SLIDE
func is_crouching() -> bool: return movement_state == MovementState.CROUCH
func is_running()   -> bool: return is_sprinting
