extends Area3D
class_name GasHazardMinimalDamageFix

## Combined gas hazard for VINADI:
## - Applies gas-mask durability damage while the player is inside.
## - Creates a visible CPUParticles3D gas plume at runtime.
## Attach this script to the gas-zone Area3D, which must have a CollisionShape3D.

@export_group("Damage")
@export_range(0.0, 100.0, 1.0) var mask_damage_per_tick: float = 30.0
@export_range(0.1, 10.0, 0.1) var tick_interval: float = 0.5

@export_group("Gas Visual")
@export var show_gas_when_idle: bool = true
@export var gas_tint: Color = Color(0.62, 0.78, 0.70, 0.72)
@export_range(20, 240, 1) var particle_count: int = 120
@export_range(0.5, 5.0, 0.1) var particle_lifetime: float = 2.4
@export_range(0.1, 5.0, 0.1) var spray_speed_min: float = 0.7
@export_range(0.1, 8.0, 0.1) var spray_speed_max: float = 2.4
@export_range(0.1, 2.5, 0.05) var particle_size_min: float = 0.45
@export_range(0.1, 4.0, 0.05) var particle_size_max: float = 1.25
@export var spray_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
@export_range(0.0, 90.0, 1.0) var spread_degrees: float = 38.0

var _tick_elapsed: float = 0.0
var _inside_players: Dictionary = {}
var _gas_particles: CPUParticles3D


func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_mask = 0x7FFFFFFF

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	_create_gas_particles()

	print("[GasHazard] Ready | damage=", mask_damage_per_tick,
		" every ", tick_interval, "s | particles=", particle_count)


func _physics_process(delta: float) -> void:
	# Poll overlap list as well as using body_entered/body_exited signals.
	var current: Dictionary = {}
	for body in get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		if _is_player_body(body):
			current[body] = true
			if not _inside_players.has(body):
				print("[GasHazard] Player detected: ", body.get_path())
				_apply_damage(body) # Immediate damage on first detection.

	# Remove bodies that are no longer overlapping.
	for old_body in _inside_players.keys():
		if not current.has(old_body):
			print("[GasHazard] Player left gas zone.")
	_inside_players = current

	if _inside_players.is_empty():
		_tick_elapsed = 0.0
		if _gas_particles != null:
			_gas_particles.emitting = show_gas_when_idle
		return

	if _gas_particles != null:
		_gas_particles.emitting = true

	_tick_elapsed += delta
	var interval := maxf(tick_interval, 0.1)
	while _tick_elapsed >= interval:
		_tick_elapsed -= interval
		for body in _inside_players.keys():
			if is_instance_valid(body):
				_apply_damage(body)


func _on_body_entered(body: Node3D) -> void:
	print("[GasHazard] body_entered: ", body.get_path())
	if not _is_player_body(body):
		print("[GasHazard] Ignored non-player body.")
		return
	if not _inside_players.has(body):
		_inside_players[body] = true
		_apply_damage(body)


func _on_body_exited(body: Node3D) -> void:
	if _inside_players.has(body):
		_inside_players.erase(body)
		print("[GasHazard] body_exited: ", body.get_path())
	if _inside_players.is_empty():
		_tick_elapsed = 0.0
		if _gas_particles != null:
			_gas_particles.emitting = show_gas_when_idle


func _is_player_body(body: Node) -> bool:
	return body.is_in_group("player") or body.has_method("damage_gas_mask")


func _apply_damage(body: Node) -> void:
	if not body.has_method("damage_gas_mask"):
		push_warning("[GasHazard] Player detected, but damage_gas_mask(amount) is missing.")
		return

	var before: float = -1.0
	if body.has_method("get_gas_mask_durability"):
		before = float(body.call("get_gas_mask_durability"))
	elif body.get("gas_mask_durability") != null:
		before = float(body.get("gas_mask_durability"))

	body.call("damage_gas_mask", mask_damage_per_tick)

	var after: float = -1.0
	if body.has_method("get_gas_mask_durability"):
		after = float(body.call("get_gas_mask_durability"))
	elif body.get("gas_mask_durability") != null:
		after = float(body.get("gas_mask_durability"))

	print("[GasHazard] Mask damage=", mask_damage_per_tick,
		" | before=", before, " | after=", after)


func _create_gas_particles() -> void:
	# Reuse a correctly typed child if one already exists; otherwise create it.
	_gas_particles = get_node_or_null("GasParticles") as CPUParticles3D
	if _gas_particles == null:
		_gas_particles = CPUParticles3D.new()
		_gas_particles.name = "GasParticles"
		add_child(_gas_particles)

	_gas_particles.amount = particle_count
	_gas_particles.lifetime = particle_lifetime
	_gas_particles.one_shot = false
	_gas_particles.explosiveness = 0.0
	_gas_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_gas_particles.emission_sphere_radius = 0.12
	_gas_particles.direction = spray_direction.normalized()
	_gas_particles.spread = spread_degrees
	_gas_particles.initial_velocity_min = minf(spray_speed_min, spray_speed_max)
	_gas_particles.initial_velocity_max = maxf(spray_speed_min, spray_speed_max)
	_gas_particles.gravity = Vector3.ZERO
	_gas_particles.damping_min = 0.15
	_gas_particles.damping_max = 0.55
	_gas_particles.scale_amount_min = minf(particle_size_min, particle_size_max)
	_gas_particles.scale_amount_max = maxf(particle_size_min, particle_size_max)
	_gas_particles.color = gas_tint
	_gas_particles.local_coords = false
	_gas_particles.mesh = _make_soft_billboard_mesh()
	_gas_particles.position = Vector3.ZERO
	_gas_particles.emitting = show_gas_when_idle
	_gas_particles.visible = true


func _make_soft_billboard_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	# Soft circular alpha texture generated in memory; no external texture required.
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var uv := Vector2((float(x) + 0.5) / 64.0, (float(y) + 0.5) / 64.0)
			var radius := (uv - Vector2(0.5, 0.5)).length() * 2.0
			var alpha := 1.0 - smoothstep(0.12, 1.0, radius)
			alpha *= 0.72
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	var texture := ImageTexture.create_from_image(image)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	return quad
