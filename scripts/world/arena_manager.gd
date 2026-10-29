extends Node3D
## Original, deterministic low-poly stages. All geometry is authored at runtime.
## The combat floor is always at y=0; breakables are kept outside the spawn lane.

var arena_names: Array[String] = ["Rocky Wasteland", "Celestial Tournament", "Ruined Future City"]
var current_index := 0
var quality := 1
var destructibles: Array[Dictionary] = []
var transients: Array[Dictionary] = []
var time := 0.0
var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}

func build(index: int, level: int = 1) -> void:
	for child in get_children():
		child.queue_free()
	destructibles.clear()
	transients.clear()
	_materials.clear()
	current_index = clampi(index, 0, 2)
	quality = level
	_rng.seed = 39015 + current_index * 701
	_lighting()
	match current_index:
		0: _wasteland()
		1: _tournament()
		2: _city()
	_batch_static_architecture()

func _mat(color: Color, emission: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := str(color) + ":" + str(emission) + ":" + str(unshaded)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = material
	return material

func _lighting() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	var skies := [Color("379dc7"), Color("4163bd"), Color("536d9b")]
	var horizons := [Color("f9dcaa"), Color("f5d8ee"), Color("f6c79d")]
	sky_material.sky_top_color = skies[current_index]
	sky_material.sky_horizon_color = horizons[current_index]
	sky_material.ground_bottom_color = Color("26334d")
	sky_material.ground_horizon_color = horizons[current_index]
	sky_material.sky_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a3bad5")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = horizons[current_index]
	env.fog_light_energy = 0.65
	env.fog_density = 0.0016
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "AnimeSun"
	sun.rotation_degrees = Vector3(-47, -34, 0)
	sun.light_color = Color("ffe6bd")
	sun.light_energy = 0.92
	sun.shadow_enabled = quality > 0
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22, 145, 0)
	fill.light_color = Color("78a6f5")
	fill.light_energy = 0.18
	add_child(fill)
	# Deliberately simple, low-poly cloud banks remain behind the flight space.
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radial_segments = 12
	cloud_mesh.rings = 6
	cloud_mesh.radius = 1.0
	cloud_mesh.height = 2.0
	var clouds: Array[Transform3D] = []
	for i in range(28):
		var angle := float(i) * TAU / 28.0
		var radius := _rng.randf_range(100, 145)
		var pos := Vector3(cos(angle) * radius, _rng.randf_range(30, 55), sin(angle) * radius)
		clouds.append(Transform3D(Basis.IDENTITY.scaled(Vector3(_rng.randf_range(9, 20), 2.2, 6.0)), pos))
	_multimesh(cloud_mesh, _mat(Color("ffeddc"), 0, true), clouds)

func _instance(mesh: Mesh, material: Material, at: Vector3, scale_value: Vector3 = Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	item.position = at
	item.scale = scale_value
	if parent == null:
		add_child(item)
	else:
		parent.add_child(item)
	return item

func _box(at: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(mesh, _mat(color), at, Vector3.ONE, parent)

func _cylinder(at: Vector3, radius: float, height: float, color: Color, top_radius: float = -1.0, parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32 if radius > 15 else 8
	return _instance(mesh, _mat(color), at, Vector3.ONE, parent)

func _ring(at: Vector3, radius: float, width: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(radius - width, 0.01)
	mesh.outer_radius = radius
	mesh.rings = 48 if radius > 10 else 24
	mesh.ring_segments = 6
	return _instance(mesh, _mat(color, 0.25), at, Vector3(1, 0.1, 1), parent)

func _collision_box(at: Vector3, size: Vector3, parent: Node3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if parent == null:
		add_child(body)
	else:
		parent.add_child(body)
	return body

func _floor(color: Color) -> void:
	_cylinder(Vector3(0, -0.3, 0), 58, 0.6, color)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 58
	shape.height = 0.6
	collider.shape = shape
	collider.position.y = -0.3
	body.add_child(collider)
	add_child(body)

func _multimesh(mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	var instance := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	instance.multimesh = multi
	instance.material_override = material
	add_child(instance)

func _batch_static_architecture() -> void:
	# Collapse individually authored architecture into material/shape instance batches
	# after its transforms are final. Breakables are children of their own roots and
	# stay separate so their collision and visibility can change independently.
	var groups: Dictionary = {}
	for child in get_children():
		if not child is MeshInstance3D: continue
		var mesh: Mesh = child.mesh
		var material: Material = child.material_override
		if material == null: continue
		var key := ""
		var unit_mesh: Mesh
		var mesh_scale := Vector3.ONE
		if mesh is BoxMesh:
			key = "box:" + str(material.get_instance_id())
			mesh_scale = mesh.size
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			unit_mesh = box
		elif mesh is CylinderMesh:
			var ratio: float = mesh.top_radius / maxf(mesh.bottom_radius, 0.001)
			key = "cylinder:" + str(material.get_instance_id()) + ":" + str(mesh.radial_segments) + ":" + str(snappedf(ratio, 0.001))
			mesh_scale = Vector3(mesh.bottom_radius, mesh.height, mesh.bottom_radius)
			var cylinder := CylinderMesh.new()
			cylinder.bottom_radius = 1.0
			cylinder.top_radius = ratio
			cylinder.height = 1.0
			cylinder.radial_segments = mesh.radial_segments
			unit_mesh = cylinder
		else:
			continue
		if not groups.has(key):
			groups[key] = {"mesh":unit_mesh, "material":material, "transforms":[]}
		var transformed: Transform3D = child.transform * Transform3D(Basis.IDENTITY.scaled(mesh_scale), Vector3.ZERO)
		groups[key].transforms.append(transformed)
		remove_child(child)
		child.queue_free()
	for group in groups.values():
		var transforms: Array[Transform3D] = []
		for transform in group.transforms: transforms.append(transform)
		_multimesh(group.mesh, group.material, transforms)

func _rock_mesh(seed_value: int = 0) -> ArrayMesh:
	# Faceted hand-shaped rock, with flat triangle normals for a painted silhouette.
	var rng := RandomNumberGenerator.new()
	rng.seed = 91 + seed_value
	var rings: Array[PackedVector3Array] = []
	for j in range(4):
		var ring := PackedVector3Array()
		for i in range(7):
			var angle := TAU * float(i) / 7.0 + float(j) * 0.16
			var width: float = [0.82, 1.0, 0.77, 0.26][j] * rng.randf_range(0.82, 1.16)
			ring.append(Vector3(cos(angle) * width, float(j) / 3.0 * 2.0, sin(angle) * width))
		rings.append(ring)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(3):
		for i in range(7):
			var next := (i + 1) % 7
			for v in [rings[j][i], rings[j + 1][next], rings[j + 1][i], rings[j][i], rings[j][next], rings[j + 1][next]]:
				surface.add_vertex(v)
	for i in range(7):
		surface.add_vertex(rings[3][i])
		surface.add_vertex(rings[3][(i + 1) % 7])
		surface.add_vertex(Vector3(0, 2.12, 0))
	surface.generate_normals()
	return surface.commit()

func _wasteland() -> void:
	_floor(Color("ddae76"))
	_ring(Vector3(0, 0.015, 0), 37, 0.08, Color("f2cb91"))
	var strata_colors := [Color("c7845c"), Color("a65d50"), Color("db9b69")]
	for layer in range(3):
		var transforms: Array[Transform3D] = []
		for i in range(18):
			var angle := float(i) * TAU / 18.0 + float(layer) * 0.09
			var radius := 48.0 + layer * 14.0
			var width := _rng.randf_range(5, 10)
			var height := _rng.randf_range(6, 18) + layer * 4
			var basis := Basis(Vector3.UP, angle).scaled(Vector3(width, height * 0.5, width * 0.8))
			transforms.append(Transform3D(basis, Vector3(cos(angle) * radius, -0.4, sin(angle) * radius)))
		_multimesh(_rock_mesh(layer), _mat(strata_colors[layer]), transforms)
	# Mesa caps and sediment bands give the horizon a deliberately drawn silhouette.
	for i in range(9):
		var angle := float(i) * TAU / 9.0
		var center := Vector3(cos(angle) * 60, 0, sin(angle) * 60)
		var height := _rng.randf_range(9, 18)
		_cylinder(center + Vector3.UP * height * 0.5, 6.8, height, Color("ae6a53"), 4.3)
		_cylinder(center + Vector3.UP * height, 4.8, 0.8, Color("e3af72"), 4.8)
		_cylinder(center + Vector3.UP * height * 0.48, 5.7, 0.35, Color("e1a06c"), 5.5)
	for i in range(15):
		var angle := float(i) * TAU / 15.0 + 0.2
		var radius := _rng.randf_range(17, 34)
		_breakable(Vector3(cos(angle) * radius, 0, sin(angle) * radius), _rng.randf_range(0.8, 2.0), Color("b97f5e"), false)
	# Flat scatter stones are batched into one draw call.
	var stones: Array[Transform3D] = []
	for i in range(110 if quality > 0 else 45):
		var pos := Vector3(_rng.randf_range(-43, 43), 0.01, _rng.randf_range(-43, 43))
		if pos.length() > 42: continue
		stones.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(0.22, 0.07, 0.3)), pos))
	_multimesh(_rock_mesh(), _mat(Color("eac598")), stones)
	for i in range(10):
		var angle := _rng.randf() * TAU
		var center := Vector3(cos(angle) * 29, 0.005, sin(angle) * 29)
		var crack := _box(center, Vector3(0.045, 0.006, 3.5), Color("ae805e"))
		crack.rotation.y = angle
	if quality > 0:
		_atmosphere(Vector3(0, 1.2, 32), Vector3(34, 0.4, 3), Color("e5bc8d"), Vector3.RIGHT, 1.8, 5.0, 16)

func _tournament() -> void:
	_floor(Color("c0bdd4"))
	# The platform is level with the common floor; its rim, gold inlay and tile seams
	# establish the stage without introducing a step into ground combat.
	_cylinder(Vector3(0, -1.15, 0), 43, 2.2, Color("677da7"), 43)
	_cylinder(Vector3(0, -0.12, 0), 41, 0.24, Color("c8c8ce"))
	_ring(Vector3(0, 0.008, 0), 40, 0.22, Color("e8b75a"))
	_ring(Vector3(0, 0.01, 0), 23, 0.09, Color("c4a467"))
	_ring(Vector3(0, 0.01, 0), 7.5, 0.06, Color("d4bd92"))
	var seam_mesh := BoxMesh.new()
	seam_mesh.size = Vector3(0.026, 0.008, 70)
	var seams: Array[Transform3D] = []
	for i in range(-5, 6):
		seams.append(Transform3D(Basis.IDENTITY, Vector3(i * 6, 0.014, 0)))
		seams.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.014, i * 6)))
	_multimesh(seam_mesh, _mat(Color("c8c0ba")), seams)
	# Eight compass-point sun emblems.
	for i in range(8):
		var angle := float(i) * TAU / 8.0
		var at := Vector3(cos(angle) * 31, 0.025, sin(angle) * 31)
		var jewel := _cylinder(at, 0.9, 0.03, Color("7ec6d9"), 0.9)
		jewel.rotation.y = angle
		_ring(at, 1.1, 0.15, Color("d5ad60"))
	for i in range(12):
		var angle := float(i) * TAU / 12.0
		var pos := Vector3(cos(angle) * 46, 0, sin(angle) * 46)
		_cylinder(pos + Vector3.UP * 0.3, 2.2, 0.6, Color("d5d5e7"))
		_cylinder(pos + Vector3.UP * 4.4, 1.0, 8, Color("f2e6d6"), 0.8)
		_cylinder(pos + Vector3.UP * 8.5, 1.5, 0.6, Color("ddba70"))
		_cylinder(pos + Vector3.UP * 9.6, 1.05, 1.5, Color("b8e5f3"), 0.0)
		var next_angle := angle + TAU / 12.0
		var midpoint := Vector3(cos(angle + TAU / 24.0) * 44.5, 8.1, sin(angle + TAU / 24.0) * 44.5)
		var lintel := _box(midpoint, Vector3(23.4, 0.55, 1.6), Color("d1c3df"))
		lintel.rotation.y = -angle - TAU / 24.0 - PI * 0.5
		# Banners face inward and catch a warm sun rim.
		var banner := _box(pos + Vector3(cos(next_angle) * -1.5, 5.2, sin(next_angle) * -1.5), Vector3(1.35, 3.5, 0.08), Color("465da4"))
		banner.rotation.y = -angle - PI * 0.5
	# Distant floating sanctuary islands: two meshes per island, no collisions.
	for i in range(8):
		var angle := float(i) * TAU / 8.0 + 0.22
		var pos := Vector3(cos(angle) * 88, _rng.randf_range(4, 19), sin(angle) * 88)
		_cylinder(pos, 0.3, 10, Color("6b72a2"), 8)
		_cylinder(pos + Vector3.UP * 5, 8.1, 0.8, Color("c2cfb0"))
		_cylinder(pos + Vector3.UP * 8.3, 1.4, 6, Color("e1d9e8"), 1.0)
	for i in range(8):
		var angle := float(i) * TAU / 8.0 + PI / 8
		_breakable(Vector3(cos(angle) * 34, 0, sin(angle) * 34), 1.0, Color("d8c5b4"), true)

func _city() -> void:
	_floor(Color("778795"))
	# Crossed avenues create readable movement lanes at the center.
	_box(Vector3(0, 0.006, 0), Vector3(15, 0.012, 110), Color("455765"))
	_box(Vector3(0, 0.014, 0), Vector3(110, 0.012, 15), Color("455765"))
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.13, 0.015, 2.2)
	var stripes: Array[Transform3D] = []
	for i in range(-13, 14):
		stripes.append(Transform3D(Basis.IDENTITY, Vector3(0, 0.03, i * 4)))
		stripes.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(i * 4, 0.032, 0)))
	_multimesh(stripe_mesh, _mat(Color("e1c684")), stripes)
	var glass := _mat(Color("5cc8d0"), 0.35)
	var windows: Array[Transform3D] = []
	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(0.7, 1.05, 0.05)
	for i in range(24):
		var angle := float(i) * TAU / 24.0 + 0.05
		var radius := _rng.randf_range(43, 64)
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var height := _rng.randf_range(9, 29)
		var width := _rng.randf_range(4.5, 7)
		var body := _box(pos + Vector3.UP * height * 0.5, Vector3(width, height, width * 0.8), Color("7b8b9f") if i % 2 == 0 else Color("617489"))
		body.rotation.y = angle + PI * 0.5
		# Asymmetric upper remnants and protruding floor slabs communicate ruins.
		var remnant := _box(pos + Vector3(width * 0.24, height + 1.8, 0), Vector3(width * 0.34, 3.6, width * 0.66), Color("96a0ac"))
		remnant.rotation.y = angle + PI * 0.5
		for floor_index in range(int(height / 3.0)):
			var slab := _box(pos + Vector3.UP * (floor_index * 3 + 0.3), Vector3(width + 0.4, 0.16, width * 0.8 + 0.4), Color("a8afaf"))
			slab.rotation.y = angle + PI * 0.5
			for column in range(3):
				if (floor_index + column + i) % 4 == 0: continue
				var local_pos := Vector3((column - 1) * width * 0.24, floor_index * 3 + 1.6, -width * 0.405)
				var basis := Basis(Vector3.UP, angle + PI * 0.5)
				windows.append(Transform3D(basis, pos + basis * local_pos))
		if i % 4 == 0:
			var antenna := _box(pos + Vector3.UP * (height + 5), Vector3(0.2, 8, 0.2), Color("344b62"))
			antenna.rotation.z = 0.15
	_multimesh(window_mesh, glass, windows)
	for i in range(15):
		var angle := float(i) * TAU / 15.0 + 0.28
		var radius := _rng.randf_range(20, 35)
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		_breakable(pos, _rng.randf_range(0.65, 1.35), Color("9ca6aa"), true)
	# Canted bridge ruins and support ribs stand beyond the combat boundary.
	for side in [-1, 1]:
		var bridge := _box(Vector3(side * 58, 7.5, 0), Vector3(24, 1.4, 8), Color("a0a9ad"))
		bridge.rotation.z = side * 0.14
		for z in [-3.5, 3.5]:
			_box(Vector3(side * 58, 8.8, z), Vector3(24, 0.4, 0.3), Color("4c6980"))
		_box(Vector3(side * 61, 3.5, 0), Vector3(2, 7, 6), Color("75869b"))
	var rubble: Array[Transform3D] = []
	for i in range(70 if quality > 0 else 30):
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(13, 41)
		var pos := Vector3(cos(angle) * radius, 0.02, sin(angle) * radius)
		rubble.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(0.4, 0.15, 0.6)), pos))
	_multimesh(_rock_mesh(6), _mat(Color("8f9da8")), rubble)
	if quality > 0:
		for i in range(3):
			var angle := float(i) * TAU / 3.0 + 0.4
			_atmosphere(Vector3(cos(angle) * 51, 7, sin(angle) * 51), Vector3(1.3, 0.4, 1.3), Color("5b6679"), Vector3(0.15, 1, 0), 1.4, 3.5, 12)

func _atmosphere(at: Vector3, extents: Vector3, color: Color, direction: Vector3, speed: float, size_value: float, count: int) -> void:
	# One particle draw per bank, with a generated soft radial mask; no texture asset
	# dependency, expensive collision, particle lights or full-screen fog pass.
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var radius := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var alpha := pow(maxf(0.0, 1.0 - radius), 1.8)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.albedo_color = Color(color, 0.32)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	var particles := CPUParticles3D.new()
	particles.position = at
	particles.mesh = quad
	particles.amount = count
	particles.lifetime = 8.0
	particles.preprocess = 7.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = extents
	particles.direction = direction
	particles.spread = 12
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = speed * 0.7
	particles.initial_velocity_max = speed
	particles.scale_amount_min = size_value
	particles.scale_amount_max = size_value * 1.6
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)

func _breakable(at: Vector3, size_value: float, color: Color, pillar: bool) -> void:
	var root := Node3D.new()
	root.position = at
	root.name = "Breakable"
	add_child(root)
	if pillar:
		_cylinder(Vector3(0, size_value * 0.3, 0), size_value * 1.1, size_value * 0.6, color.darkened(0.1), -1, root)
		_cylinder(Vector3(0, size_value * 1.4, 0), size_value * 0.65, size_value * 2, color, size_value * 0.55, root)
		_cylinder(Vector3(0, size_value * 2.5, 0), size_value * 0.9, size_value * 0.3, color.lightened(0.15), -1, root)
	else:
		_instance(_rock_mesh(int(at.x + at.z)), _mat(color), Vector3.ZERO, Vector3(size_value, size_value, size_value), root)
	var body := _collision_box(Vector3(0, size_value, 0), Vector3(size_value * 1.4, size_value * 2, size_value * 1.4), root)
	destructibles.append({"node":root, "body":body, "pos":at + Vector3.UP * size_value, "hp":38.0, "size":size_value, "color":color})

func impact(pos: Vector3, radius: float, power: float) -> void:
	for prop in destructibles:
		if not is_instance_valid(prop.node): continue
		if prop.hp <= 0.0: continue
		if prop.pos.distance_to(pos) > radius + prop.size: continue
		prop.hp -= power
		if prop.hp > 0.0: continue
		prop.node.visible = false
		for shape in prop.body.get_children():
			if shape is CollisionShape3D:
				shape.set_deferred("disabled", true)
		for i in range(5 if quality > 0 else 3):
			if transients.size() >= 36: break
			var shard := _instance(_rock_mesh(i), _mat(prop.color), prop.pos, Vector3.ONE * _rng.randf_range(0.14, 0.35) * prop.size)
			var velocity: Vector3 = (prop.pos - pos).normalized() * _rng.randf_range(3, 7) + Vector3(_rng.randf_range(-3, 3), _rng.randf_range(4, 8), _rng.randf_range(-3, 3))
			transients.append({"node":shard, "life":1.8, "max_life":1.8, "velocity":velocity, "kind":"shard"})
	# Ground scars and expanding dust rings are bounded and expire after impact.
	if pos.y < 5.0 and transients.size() < 34:
		var scar := _cylinder(Vector3(pos.x, 0.02, pos.z), clampf(radius * 0.55, 0.4, 3.4), 0.014, Color("725d59") if current_index == 0 else Color("4b5367"))
		transients.append({"node":scar, "life":5.0, "max_life":5.0, "velocity":Vector3.ZERO, "kind":"scar"})
		var ring := _ring(Vector3(pos.x, 0.06, pos.z), maxf(radius, 0.5), 0.08, Color("e4c69c") if current_index == 0 else Color("d8e7ed"))
		transients.append({"node":ring, "life":0.55, "max_life":0.55, "velocity":Vector3.ZERO, "kind":"ring"})

func update(delta: float) -> void:
	time += delta
	for i in range(transients.size() - 1, -1, -1):
		var item := transients[i]
		item.life -= delta
		if not is_instance_valid(item.node) or item.life <= 0:
			if is_instance_valid(item.node): item.node.queue_free()
			transients.remove_at(i)
			continue
		if item.kind == "shard":
			item.velocity.y -= delta * 18.0
			item.node.position += item.velocity * delta
			item.node.rotation += Vector3(delta * 3, delta * 2, delta)
			if item.node.position.y < 0.08:
				item.node.position.y = 0.08
				item.velocity *= 0.4
				item.velocity.y = absf(item.velocity.y) * 0.5
			if item.life < 0.4: item.node.scale *= maxf(0.0, 1.0 - delta * 6.0)
		elif item.kind == "ring":
			item.node.scale.x += delta * 3.5
			item.node.scale.z += delta * 3.5
			item.node.scale.y *= maxf(0.0, 1.0 - delta * 4.0)
		elif item.life < 0.8:
			item.node.scale *= maxf(0.0, 1.0 - delta * 3.0)
