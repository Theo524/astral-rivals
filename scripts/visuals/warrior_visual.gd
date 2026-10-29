extends Node3D
## Imported skinned GLB and authored bone clips; no body primitives or limb code.
const TOON = preload("res://shaders/anime_toon.gdshader")
const KAIZEN_TOON = preload("res://shaders/kaizen_toon.gdshader")
const OUTLINE = preload("res://shaders/anime_outline.gdshader")
const AURA = preload("res://shaders/energy_aura.gdshader")
var identity: String = "kaizen"
var energy_color: Color = Color.CYAN
var model: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var materials: Array[Dictionary] = []
var form_index: int = 0
var quality: int = 1
var current_clip: String = ""
var current_state: String = ""
var presentation: String = ""
var attack_step: int = 1
var local_velocity: Vector3 = Vector3.ZERO
var _last_progress: float = 0.0
var _clock: float = 0.0
var _aura: MultiMeshInstance3D
var _aura_material: ShaderMaterial
var _shield: MeshInstance3D
var _shield_material: StandardMaterial3D
var _loaded: bool = false
var asset_error: String = ""

func setup(data: Dictionary) -> void:
	identity = str(data.get("id","kaizen"))
	energy_color = data.get("color",Color.CYAN)
	var path: String = "res://assets/characters/%s.glb" % identity
	if not ResourceLoader.exists(path):
		asset_error = "Missing imported character: " + path
		push_error(asset_error)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		asset_error = "Character could not load: " + path
		push_error(asset_error)
		return
	model = packed.instantiate() as Node3D
	# Blender -Y front becomes glTF +Z; gameplay and camera use local -Z.
	model.rotation.y = PI
	add_child(model)
	var skeletons := model.find_children("*","Skeleton3D",true,false)
	if not skeletons.is_empty():
		skeleton = skeletons[0] as Skeleton3D
	var players := model.find_children("*","AnimationPlayer",true,false)
	if not players.is_empty():
		animation_player = players[0] as AnimationPlayer
		animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		# glTF stores bone tracks but has no standardized loop flag.
		for clip in animation_player.get_animation_list():
			var short_name: String = str(clip).get_slice("/",str(clip).get_slice_count("/")-1)
			if short_name in ["idle","walk","run","hover","fly","charge","guard","victory"]:
				animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if skeleton == null or animation_player == null:
		asset_error = "Character needs Skeleton3D and AnimationPlayer: " + path
		push_error(asset_error)
		return
	_prepare_materials()
	_build_energy()
	_loaded = true
	set_form(0)
	_play("idle",0.0)

func _prepare_materials() -> void:
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_end = 120.0
		mesh.lod_bias = 0.7
		for surface in mesh.mesh.get_surface_count():
			var source: Material = mesh.mesh.surface_get_material(surface)
			var label: String = source.resource_name.to_lower() if source != null else "surface"
			var tint: Color = Color.WHITE
			var texture: Texture2D
			if source is StandardMaterial3D:
				tint = source.albedo_color
				texture = source.albedo_texture
			var material := ShaderMaterial.new()
			material.shader = KAIZEN_TOON if identity == "kaizen" else TOON
			material.set_shader_parameter("base_color",tint)
			material.set_shader_parameter("face_material",1.0 if ("skin" in label or "face" in label or "sclera" in label) else 0.0)
			if identity == "kaizen":
				var skin: bool = "skin" in label or "face" in label
				material.set_shader_parameter("shadow_tint",Color("c38c88") if skin else Color("879bc9"))
				material.set_shader_parameter("ink_detail",1.0 if "ink" in label else 0.0)
				material.set_shader_parameter("eye_detail",1.0 if ("eye" in label or "iris" in label or "sclera" in label) else 0.0)
				material.set_shader_parameter("hair_material",1.0 if "hair" in label else 0.0)
			if texture != null:
				material.set_shader_parameter("painted_texture",texture)
				material.set_shader_parameter("use_texture",true)
			if not ("ink" in label or "eye" in label or "iris" in label or "sclera" in label or "face" in label):
				var ink := ShaderMaterial.new()
				ink.shader = OUTLINE
				if identity == "kaizen":
					ink.set_shader_parameter("width",0.0018 if "hair" in label else 0.0028)
				material.next_pass = ink
			mesh.set_surface_override_material(surface,material)
			materials.append({"material":material,"base":tint,"name":label})

func anim_context(step: int, world_velocity: Vector3, facing: Vector3) -> void:
	attack_step = maxi(step,1)
	var forward := Vector3(facing.x,0,facing.z).normalized()
	local_velocity = Vector3(world_velocity.dot(forward.cross(Vector3.UP)),world_velocity.y,world_velocity.dot(forward))

func set_form(value: int) -> void:
	form_index = clampi(value,0,2)
	var glow: Color = energy_color
	if form_index > 0:
		glow = Color("ffce55") if identity == "kaizen" else (Color("e53c8b") if identity == "ryuzen" else Color("ffe49b"))
		if form_index == 2 and identity == "ryuzen":
			glow = Color("ff335b")
	for item in materials:
		var tint: Color = item.base
		if "hair" in str(item.name) and form_index > 0:
			tint = glow.lightened(0.18) if "light" in str(item.name) else glow
		item.material.set_shader_parameter("base_color",tint)
		item.material.set_shader_parameter("power",float(form_index)*0.5)
	if _aura_material != null:
		_aura_material.set_shader_parameter("energy_color",glow)
	if _shield_material != null:
		_shield_material.albedo_color = Color(glow,0.12)
		_shield_material.emission = glow

func set_quality(level: int) -> void:
	quality = clampi(level,0,2)
	if _aura != null:
		_aura.multimesh.visible_instance_count = [6,9,12][quality]
	if model != null:
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			mesh.lod_bias = [0.45,0.7,1.0][quality]

func set_presentation(pose: String) -> void:
	presentation = pose
	if pose != "":
		_play(pose,0.16)

func _resolve_clip(short_name: String) -> String:
	if animation_player == null:
		return ""
	if animation_player.has_animation(short_name):
		return short_name
	for clip in animation_player.get_animation_list():
		if str(clip).ends_with("/"+short_name):
			return str(clip)
	return ""

func _play(clip: String, blend: float = 0.09) -> void:
	var resolved := _resolve_clip(clip)
	if resolved == "" or resolved == current_clip:
		return
	current_clip = resolved
	animation_player.play(resolved,blend)
	animation_player.advance(0.0)

func animate(delta: float, state: String, speed: float, attack_progress: float, form: int, airborne: bool) -> void:
	if not _loaded:
		return
	_clock += delta
	if form != form_index:
		set_form(form)
	var clip: String = state
	if presentation != "":
		clip = presentation
	elif state == "idle":
		clip = ("fly" if speed > 2.0 else "hover") if airborne else ("run" if speed > 5.0 else ("walk" if speed > 0.5 else "idle"))
	elif state == "light":
		clip = "kick" if attack_step == 4 else "punch_%d" % mini(attack_step,3)
	elif state == "dead":
		clip = "defeat"
	elif state == "dash":
		clip = "dash_back" if local_velocity.z < -1.0 else "dash_forward"
	var old_clip: String = current_clip
	_play(clip,0.06 if state in ["light","heavy","hurt","dodge"] else 0.14)
	var timed: bool = state in ["light","heavy","blast","beam","ultimate","transform","dodge","hurt"] and presentation == ""
	if animation_player != null and current_clip != "":
		var length: float = animation_player.get_animation(current_clip).length
		if timed:
			var progress: float = clampf(attack_progress,0.0,0.999)
			if old_clip != current_clip or current_state != state or progress < _last_progress:
				animation_player.seek(progress*length,true)
			else:
				animation_player.advance(maxf(0.0,progress-_last_progress)*length)
			_last_progress = progress
		else:
			var rate: float = clampf(speed/7.0,0.55,1.45) if clip in ["run","walk"] else 1.0
			animation_player.advance(delta*rate)
	current_state = state
	_aura.visible = form > 0 or state in ["charge","transform","dash","beam","ultimate"]
	if _aura.visible:
		var intensity: float = 1.7 if state in ["transform","ultimate"] else (1.25 if state == "charge" else 0.8)
		_aura_material.set_shader_parameter("strength",intensity)
		_aura.rotation.y += delta*0.38
		_aura.scale.y = 1.0+sin(_clock*12.0)*0.035
	_shield.visible = state == "guard"
	if _shield.visible:
		_shield.scale = Vector3.ONE*(1.0+sin(_clock*7.0)*0.012)

func _build_energy() -> void:
	var flame := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.28,0,0),Vector3(0.28,0,0),Vector3(0.20,0.9,0),Vector3(-0.20,0.9,0),Vector3(0,1.9,0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(0.9,0.5),Vector2(0.1,0.5),Vector2(0.5,1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3,3,2,4])
	flame.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_aura_material = ShaderMaterial.new()
	_aura_material.shader = AURA
	flame.surface_set_material(0,_aura_material)
	_aura = MultiMeshInstance3D.new()
	_aura.multimesh = MultiMesh.new()
	_aura.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_aura.multimesh.mesh = flame
	_aura.multimesh.instance_count = 12
	for i in 12:
		var angle: float = float(i)*TAU/12.0
		var frame: Basis = Basis(Vector3.UP,-angle+PI/2.0).scaled(Vector3(0.8,1.0+float(i%3)*0.14,1))
		_aura.multimesh.set_instance_transform(i,Transform3D(frame,Vector3(cos(angle)*0.47,0.04,sin(angle)*0.47)))
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aura)
	_shield = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.03
	sphere.height = 2.3
	sphere.radial_segments = 16
	sphere.rings = 8
	_shield.mesh = sphere
	_shield.position.y = 1.1
	_shield_material = StandardMaterial3D.new()
	_shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_material.emission_enabled = true
	_shield_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield.material_override = _shield_material
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.visible = false
	add_child(_shield)
	set_quality(quality)
