extends Node3D
## Fixed-capacity visual and gameplay pools. No physics body is spawned per shot.
## Segment tests sweep the whole travelled path, preventing fast shots tunnelling.
signal impact(position: Vector3, power: float)
signal sound_requested(cue: String)
signal beam_started(attacker: Node, ultimate: bool)

var fighters: Array = []
var arena: Node
var projectiles: Array[Dictionary] = []
var beams: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var quality := 1
const POOL_LIMITS = [[12, 2, 16], [24, 2, 28], [36, 4, 48]]
var pool_limits: Array = []
var _sphere: SphereMesh
var _ring: TorusMesh
var _cylinder: CylinderMesh
var _sparks: ArrayMesh

func _ready() -> void:
	quality = clampi(quality, 0, 2)
	pool_limits = POOL_LIMITS[quality].duplicate()
	_sphere = SphereMesh.new()
	_sphere.radial_segments = 8 if quality == 0 else 12
	_sphere.rings = 4 if quality == 0 else 6
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_ring = TorusMesh.new()
	_ring.inner_radius = 0.88
	_ring.outer_radius = 1.0
	_ring.rings = 16 if quality == 0 else 24
	_ring.ring_segments = 4
	_cylinder = CylinderMesh.new()
	_cylinder.top_radius = 0.5
	_cylinder.bottom_radius = 0.5
	_cylinder.height = 1.0
	_cylinder.radial_segments = 10
	_sparks = _spark_mesh()
	for i in int(pool_limits[0]):
		var root := Node3D.new()
		add_child(root)
		var shell := _mesh(root, _sphere, Color(0.1, 0.7, 1.0, 0.3))
		var core := _mesh(root, _sphere, Color.WHITE)
		core.scale = Vector3.ONE * 0.48
		var tail := _mesh(root, _sphere, Color(0.1, 0.7, 1.0, 0.4))
		tail.position.z = 0.8
		tail.scale = Vector3(0.4, 0.4, 1.6)
		root.visible = false
		projectiles.append({"active": false, "visual": root, "shell": shell, "core": core, "tail": tail})
	for i in int(pool_limits[1]):
		var root := Node3D.new()
		add_child(root)
		var shell := _mesh(root, _cylinder, Color(0.1, 0.7, 1.0, 0.28))
		var middle := _mesh(root, _cylinder, Color(0.3, 0.8, 1.0, 0.65))
		var core := _mesh(root, _cylinder, Color.WHITE)
		root.visible = false
		beams.append({"active": false, "visual": root, "shell": shell, "middle": middle, "core": core})
	for i in int(pool_limits[2]):
		var root := Node3D.new()
		add_child(root)
		var ball := _mesh(root, _sphere, Color.WHITE)
		var ring := _mesh(root, _ring, Color.WHITE)
		var ring2 := _mesh(root, _ring, Color.WHITE)
		ring2.rotation.x = PI * 0.5
		# One batched starburst mesh replaces separately spawned sparks.
		var sparks := _mesh(root, _sparks, Color.WHITE)
		root.visible = false
		effects.append({"active": false, "visual": root, "ball": ball, "ring": ring, "ring2": ring2, "sparks": sparks})

func _spark_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 6 if quality == 0 else 10
	for i in count:
		var angle := float(i) * TAU / float(count)
		var ray := Vector3(cos(angle), sin(angle), sin(angle * 3.0) * 0.25)
		var side := Vector3(-sin(angle), cos(angle), 0.0) * 0.045
		var inner := ray * 0.45
		var outer := ray * (1.15 + float(i % 3) * 0.22)
		st.add_vertex(inner - side)
		st.add_vertex(outer)
		st.add_vertex(inner + side)
	st.generate_normals()
	return st.commit()

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	# Unshaded additive color is already luminous. Excess emission washed every
	# colored ring to white in actual Compatibility-renderer captures.
	mat.emission_energy_multiplier = 0.35
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.disable_fog = true
	return mat

func _mesh(root: Node3D, mesh: Mesh, color: Color) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = _material(color)
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(item)
	return item

func _tint(mesh: MeshInstance3D, color: Color) -> void:
	var mat := mesh.material_override as StandardMaterial3D
	mat.albedo_color = color
	mat.emission = Color(color.r, color.g, color.b)

func _valid_target(owner: Node) -> Node:
	if not is_instance_valid(owner):
		return null
	var selected = owner.get("target")
	if is_instance_valid(selected) and selected.get("hp") > 0.0:
		return selected
	for fighter in fighters:
		if is_instance_valid(fighter) and fighter != owner and fighter.get("hp") > 0.0:
			return fighter
	return null

func _origin(owner: Node) -> Vector3:
	return owner.global_position + Vector3.UP * 1.28

func fire(owner: Node, kind: String = "blast", charge: float = 1.0) -> void:
	if not is_instance_valid(owner):
		return
	var target := _valid_target(owner)
	var origin := _origin(owner)
	var direction: Vector3 = -owner.global_basis.z
	if is_instance_valid(target):
		direction = (_origin(target) - origin).normalized()
	if direction.length_squared() < 0.1:
		direction = Vector3.FORWARD
	var color: Color = owner.color
	var multiplier: float = owner.damage_multiplier() * float(owner.data.get("energy_rate", 1.0))
	if kind == "nova":
		burst(origin, color, 7.0)
		for fighter in fighters:
			if is_instance_valid(fighter) and fighter != owner:
				var offset: Vector3 = _origin(fighter) - origin
				if offset.length() <= 9.0:
					fighter.receive_hit(110.0 * multiplier, offset.normalized() * 23.0 + Vector3.UP * 5.0, owner, "nova")
		_environment_impact(origin, 8.0, 110.0)
		sound_requested.emit("explosion")
		return
	if kind in ["beam", "ultimate"]:
		for beam in beams:
			if not beam.active:
				beam.merge({"active": true, "owner": owner, "direction": direction, "origin": origin,
					"age": 0.0, "duration": 1.25 if kind == "beam" else 2.0,
					"tick": 0.0, "radius": 0.7 if kind == "beam" else 1.65,
					"damage": (18.0 if kind == "beam" else 32.0) * multiplier,
					"color": color, "length": 70.0, "kind": kind}, true)
				beam.visual.visible = true
				_tint(beam.shell, Color(color.r, color.g, color.b, 0.22))
				_tint(beam.middle, Color(color.r, color.g, color.b, 0.62))
				burst(origin + direction * 0.8, color, 1.9)
				sound_requested.emit("beam")
				beam_started.emit(owner, kind == "ultimate")
				return
		return
	for shot in projectiles:
		if not shot.active:
			var large := kind == "sphere"
			var radius := (0.65 + charge * 0.15) if large else 0.24
			shot.merge({"active": true, "owner": owner, "target": target, "kind": kind,
				"position": origin + direction * 0.95, "velocity": direction * (24.0 if large else 43.0),
				"age": 0.0, "life": 3.0, "radius": radius,
				"damage": (95.0 * charge if large else 30.0) * multiplier, "color": color}, true)
			shot.visual.position = shot.position
			shot.visual.scale = Vector3.ONE * radius * 2.0
			shot.visual.visible = true
			_tint(shot.shell, Color(color.r, color.g, color.b, 0.65))
			_tint(shot.tail, Color(color.r, color.g, color.b, 0.32))
			sound_requested.emit("blast")
			return

func _physics_process(delta: float) -> void:
	for shot in projectiles:
		if not shot.active:
			continue
		shot.age += delta
		if shot.age > shot.life or not is_instance_valid(shot.owner):
			_retire(shot)
			continue
		if shot.kind == "homing" and is_instance_valid(shot.target):
			var desired: Vector3 = (_origin(shot.target) - shot.position).normalized() * 37.0
			shot.velocity = shot.velocity.lerp(desired, 1.0 - exp(-2.7 * delta))
		var previous: Vector3 = shot.position
		shot.position += shot.velocity * delta
		shot.visual.position = shot.position
		if shot.velocity.length_squared() > 0.1:
			shot.visual.quaternion = Quaternion(Vector3.FORWARD, shot.velocity.normalized())
		var consumed := false
		for fighter in fighters:
			if not is_instance_valid(fighter) or fighter == shot.owner or fighter.get("hp") <= 0.0:
				continue
			var closest := Geometry3D.get_closest_point_to_segment(_origin(fighter), previous, shot.position)
			if closest.distance_to(_origin(fighter)) < 0.78 + shot.radius:
				var accepted: bool = fighter.receive_hit(shot.damage, shot.velocity.normalized() * (17.0 if shot.kind == "sphere" else 8.0), shot.owner, shot.kind)
				burst(closest, shot.color, 2.5 if shot.kind == "sphere" else 1.0)
				if accepted:
					_environment_impact(closest, 2.6 if shot.kind == "sphere" else 0.9, shot.damage)
				_retire(shot)
				consumed = true
				break
		if consumed:
			continue
		if shot.position.y < 0.12:
			burst(shot.position, shot.color, 1.4)
			_environment_impact(shot.position, 2.0, shot.damage)
			_retire(shot)
			continue
		# Small fixed pool: at most 630 unique pairs, with inactive shots skipped.
		for other in projectiles:
			if other == shot or not other.active or other.owner == shot.owner:
				continue
			var closest := Geometry3D.get_closest_point_to_segment(other.position, previous, shot.position)
			if closest.distance_to(other.position) < shot.radius + other.radius + 0.2:
				burst(closest, Color(0.9, 0.7, 1.0), 2.0)
				_retire(other)
				_retire(shot)
				impact.emit(closest, 0.6)
				break
	_update_beams(delta)
	_update_effects(delta)

func _update_beams(delta: float) -> void:
	for beam in beams:
		if not beam.active:
			continue
		beam.age += delta
		beam.tick -= delta
		if beam.age > beam.duration or not is_instance_valid(beam.owner):
			_retire(beam)
			continue
		if beam.owner.get("hp") <= 0.0 or beam.owner.get("state") in ["hurt", "dead"]:
			_retire(beam)
			continue
		beam.origin = _origin(beam.owner) + beam.direction * 0.7
		var length: float = beam.length
		var end: Vector3 = beam.origin + beam.direction * length
		# Opposing beams meet at their closest overlap; both end at the clash.
		for other in beams:
			if not other.active or other == beam or other.owner == beam.owner:
				continue
			if beam.direction.dot(other.direction) < -0.6:
				var midpoint: Vector3 = (beam.origin + other.origin) * 0.5
				var near := Geometry3D.get_closest_point_to_segment(midpoint, beam.origin, end)
				if near.distance_to(midpoint) < beam.radius + other.radius + 1.5:
					length = beam.origin.distance_to(midpoint)
					end = midpoint
					if beam.tick <= 0.0:
						burst(midpoint, Color(0.95, 0.8, 1.0), 3.5)
						impact.emit(midpoint, 0.4)
		beam.visual.position = beam.origin + beam.direction * length * 0.5
		beam.visual.quaternion = Quaternion(Vector3.UP, beam.direction.normalized())
		var pulse: float = 1.0 + sin(beam.age * 44.0) * 0.09
		var radius: float = beam.radius * pulse
		beam.shell.scale = Vector3(radius * 2.6, length, radius * 2.6)
		beam.middle.scale = Vector3(radius * 1.7, length, radius * 1.7)
		beam.core.scale = Vector3(radius * 0.65, length, radius * 0.65)
		if beam.tick > 0.0:
			continue
		beam.tick = 0.15
		for fighter in fighters:
			if not is_instance_valid(fighter) or fighter == beam.owner or fighter.get("hp") <= 0.0:
				continue
			var closest := Geometry3D.get_closest_point_to_segment(_origin(fighter), beam.origin, end)
			if closest.distance_to(_origin(fighter)) < beam.radius + 0.75:
				if fighter.receive_hit(beam.damage, beam.direction * 7.0, beam.owner, beam.kind):
					burst(closest, beam.color, 1.5)
					_environment_impact(closest, 2.4, beam.damage)

func _environment_impact(pos: Vector3, radius: float, power: float) -> void:
	impact.emit(pos, clampf(power / 35.0, 0.15, 1.8))
	if is_instance_valid(arena) and arena.has_method("impact"):
		arena.impact(pos, radius, power)

func _retire(item: Dictionary) -> void:
	item.active = false
	item.visual.visible = false

func burst(pos: Vector3, color: Color, scale_factor: float = 1.0) -> void:
	for effect in effects:
		if not effect.active:
			effect.merge({"active": true, "age": 0.0, "duration": 0.42,
				"size": scale_factor, "color": color, "trail": false}, true)
			effect.visual.position = pos
			effect.visual.visible = true
			effect.visual.scale = Vector3.ONE * 0.02
			_tint(effect.ball, Color(1.0, 0.95, 0.8, 0.9))
			_tint(effect.ring, Color(color.r, color.g, color.b, 0.8))
			_tint(effect.ring2, Color(color.r, color.g, color.b, 0.5))
			_tint(effect.sparks, Color(1.0, 0.94, 0.75, 0.95))
			effect.sparks.visible = quality > 0
			return

func trail(pos: Vector3, color: Color) -> void:
	if quality == 0:
		return
	for effect in effects:
		if not effect.active:
			effect.merge({"active": true, "age": 0.0, "duration": 0.22,
				"size": 0.6, "color": color, "trail": true}, true)
			effect.visual.position = pos
			effect.visual.visible = true
			effect.visual.scale = Vector3.ONE
			effect.ball.scale = Vector3.ONE
			effect.sparks.visible = false
			return

func _update_effects(delta: float) -> void:
	for effect in effects:
		if not effect.active:
			continue
		effect.age += delta
		var progress: float = effect.age / effect.duration
		if progress >= 1.0:
			_retire(effect)
			continue
		var size: float = effect.size
		var color: Color = effect.color
		if effect.trail:
			effect.visual.scale = Vector3.ONE * size * (1.0 - progress)
			effect.ring.visible = false
			effect.ring2.visible = false
			effect.sparks.visible = false
			_tint(effect.ball, Color(color.r, color.g, color.b, (1.0 - progress) * 0.35))
		else:
			effect.visual.scale = Vector3.ONE * size * (0.15 + progress * 2.2)
			effect.ring.visible = true
			effect.ring2.visible = true
			effect.sparks.visible = quality > 0 and progress < 0.7
			effect.sparks.scale = Vector3.ONE * (0.55 + progress * 1.4)
			effect.sparks.rotation.z = effect.age * 1.5
			effect.ball.scale = Vector3.ONE * maxf(0.01, 1.0 - progress * 1.4)
			effect.ring.rotation.y += delta * 3.0
			_tint(effect.ball, Color(1.0, 0.96, 0.85, (1.0 - progress) * 0.65))
			_tint(effect.ring, Color(color.r, color.g, color.b, (1.0 - progress) * 0.8))
			_tint(effect.ring2, Color(color.r, color.g, color.b, (1.0 - progress) * 0.45))
			_tint(effect.sparks, Color(1.0, 0.94, 0.75, maxf(0.0, 1.0 - progress * 1.7)))

func active_count() -> int:
	var count := 0
	for shot in projectiles:
		if shot.active:
			count += 1
	for beam in beams:
		if beam.active:
			count += 1
	return count
