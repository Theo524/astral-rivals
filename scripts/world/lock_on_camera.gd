extends Camera3D
## Mobile-friendly two-subject combat camera. No scene dependencies.

var player: Node3D
var enemy: Node3D
var locked: bool = true
var shake_enabled: bool = true
var sensitivity: float = 1.0

var _focus := Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = -0.25
var _locked_orbit: float = 0.0
var _shake: float = 0.0
var _cinematic: float = 0.0
var _cinematic_length: float = 1.0
var _clock: float = 0.0
var _initialized: bool = false
var _cinematic_kind: String = "special"
var _base_position := Vector3.ZERO
var _collision_sphere: SphereShape3D


func _ready() -> void:
	near = 0.12
	far = 260.0
	fov = 62.0
	current = true
	_collision_sphere = SphereShape3D.new()
	_collision_sphere.radius = 0.28


func kick(amount: float) -> void:
	_shake = minf(_shake + amount * 0.055, 0.22)


func cinematic(duration: float = 1.0, kind: String = "special") -> void:
	_cinematic = maxf(duration, 0.1)
	_cinematic_length = _cinematic
	_cinematic_kind = kind


func snap() -> void:
	_initialized = false
	_shake = 0.0
	_cinematic = 0.0
	_base_position = global_position
	_update_camera(1.0, true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if locked:
			_locked_orbit = clampf(_locked_orbit - event.relative.x * 0.004 * sensitivity, -0.65, 0.65)
		else:
			_yaw -= event.relative.x * 0.005 * sensitivity
		_pitch = clampf(_pitch - event.relative.y * 0.004 * sensitivity, -0.75, 0.45)


func _process(delta: float) -> void:
	_clock += delta
	_shake = move_toward(_shake, 0.0, delta * 1.1)
	_cinematic = maxf(_cinematic - delta, 0.0)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var x := Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X)
		var y := Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_Y)
		if absf(x) > 0.15:
			if locked:
				_locked_orbit = clampf(_locked_orbit - x * delta * 1.4 * sensitivity, -0.65, 0.65)
			else:
				_yaw -= x * delta * 2.2 * sensitivity
		if absf(y) > 0.15:
			_pitch = clampf(_pitch - y * delta * 1.2 * sensitivity, -0.75, 0.45)
	_update_camera(delta, false)


func _update_camera(delta: float, immediate: bool) -> void:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	var p := player.global_position + Vector3.UP * 1.25
	var pursuit_speed: float = player.velocity.length() if player is CharacterBody3D else 0.0
	var desired: Vector3
	var aim: Vector3
	var wanted_fov: float = 62.0
	if locked and is_instance_valid(enemy) and enemy.is_inside_tree():
		var e := enemy.global_position + Vector3.UP * 1.25
		var separation := p.distance_to(e)
		var away := p - e
		away.y = 0.0
		if away.length_squared() < 0.04:
			away = Vector3(0.0, 0.0, 1.0)
		away = away.normalized().rotated(Vector3.UP, _locked_orbit)
		# Over-the-shoulder at melee range; both subjects remain framed in flight.
		var side := away.cross(Vector3.UP).normalized()
		var distance := clampf(5.0 + separation * 0.40 + minf(pursuit_speed*0.075,2.7), 5.6, 30.0)
		var altitude := maxf(p.y, e.y)
		var height := 1.8 + minf(separation * 0.10, 3.8) + absf(p.y - e.y) * 0.25 - _pitch*1.0
		var shoulder_offset: float = 1.35
		# A modest lower, wider shoulder view makes Kaizen's revised guard and
		# clothing readable and separates the two silhouettes in close combat.
		# Keep the established long-range/aerial framing and other roster intact.
		var character_data = player.get("data")
		if character_data is Dictionary and character_data.get("id","") == "kaizen":
			var close_weight: float = 1.0-smoothstep(3.0,8.0,separation)
			distance -= close_weight*0.6
			height -= close_weight*0.65
			shoulder_offset += close_weight*0.85
		desired = p + away * distance + side * shoulder_offset + Vector3.UP * height
		aim = p.lerp(e, 0.45)
		if altitude > 5.0:
			desired.y += 0.8
		wanted_fov = clampf(57.0 + separation * 0.35 + minf(pursuit_speed*0.10,3.5), 58.0, 78.0)
		if _cinematic > 0.0:
			var phase := 1.0 - _cinematic / _cinematic_length
			var accent := sin(phase * PI)
			var orbit_strength := 1.8 if _cinematic_kind == "transform" else 0.9
			desired += side * accent * orbit_strength - away * accent * 0.65
			wanted_fov -= accent * (5.0 if _cinematic_kind == "transform" else 2.5)
	else:
		var orbit := Vector3(sin(_yaw), 0.0, cos(_yaw))
		desired = p + orbit * 9.0 + Vector3.UP * (3.4 - _pitch * 5.0)
		aim = p + Vector3.UP * 0.4
	# Sweeping a near-plane-sized sphere avoids the corner clipping of a
	# center-only ray. One bounded query; fighters themselves are excluded.
	if is_inside_tree() and get_world_3d() != null:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _collision_sphere
		query.transform = Transform3D(Basis.IDENTITY,p)
		query.motion = desired-p
		query.collision_mask = 1
		var excluded: Array[RID] = []
		if player is CollisionObject3D:
			excluded.append(player.get_rid())
		if is_instance_valid(enemy) and enemy is CollisionObject3D:
			excluded.append(enemy.get_rid())
		query.exclude = excluded
		var fractions := get_world_3d().direct_space_state.cast_motion(query)
		if fractions.size() >= 1 and fractions[0] < 1.0:
			desired = p+(desired-p)*maxf(0.05,fractions[0]-0.02)
	var weight := 1.0 if immediate or not _initialized else 1.0-exp(-delta*(8.0+minf(pursuit_speed*0.11,4.0)))
	_base_position = _base_position.lerp(desired,weight)
	global_position = _base_position
	_focus = _focus.lerp(aim, weight)
	if shake_enabled and _shake > 0.0:
		global_position += Vector3(sin(_clock * 73.0), sin(_clock * 91.0), cos(_clock * 67.0)) * _shake
	if global_position.distance_squared_to(_focus) > 0.001:
		look_at(_focus, Vector3.UP)
	fov = lerpf(fov, wanted_fov, weight)
	_initialized = true
