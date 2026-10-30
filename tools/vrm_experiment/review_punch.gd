extends Node3D
## Private Blender-action review. No retarget of old game clips, no live combat.
## Input motion contains world rest-relative quaternion deltas in Godot basis.
var motion: Dictionary
var originals: Array[Node3D] = []
var candidates: Array[Node3D] = []
var skeletons: Array[Skeleton3D] = []
var players: Array[AnimationPlayer] = []
var holders: Array[Node3D] = []
var pads: Array[MeshInstance3D] = []
var pad_centers: Array[Vector3] = []
var camera: Camera3D
var title: Label
var footer: Label
var failures: Array[String] = []
var running := false
var elapsed := 0.0
var duration := 1.2
var contact := 0.4
var pad_size := Vector3(0.22,0.30,0.10)
var contact_verified := false
var expression_verified := false

func _ready() -> void:
	call_deferred("_setup")

func _expect(value: bool, description: String) -> void:
	print("PASS: " if value else "FAIL: ",description)
	if not value: failures.append(description)

func _setup() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://user_assets/motion.json"))
	if not parsed is Dictionary:
		_expect(false,"Private baked Blender motion JSON exists")
		_finish()
		return
	motion = parsed
	duration = float(motion.duration)
	contact = float(motion.get("contact_seconds",0.4))
	_build_studio()
	for index in 2:
		var holder := Node3D.new()
		holder.position.x = -0.95 if index == 0 else 0.95
		add_child(holder)
		holders.append(holder)
		var original := (load("res://user_assets/original.scn") as PackedScene).instantiate() as Node3D
		holder.add_child(original)
		originals.append(original)
		var candidate := (load("res://user_assets/candidate.scn") as PackedScene).instantiate() as Node3D
		holder.add_child(candidate)
		candidates.append(candidate)
		if "--freeze-secondary" in OS.get_cmdline_user_args():
			_freeze_secondary(original)
			_freeze_secondary(candidate)
		var found := candidate.find_children("*","Skeleton3D",true,false)
		if found.is_empty():
			_expect(false,"Imported model contains a Skeleton3D")
			_finish()
			return
		var skeleton: Skeleton3D = found[0]
		skeletons.append(skeleton)
		for tree in candidate.find_children("*","AnimationTree",true,false): tree.active = false
		for tree in original.find_children("*","AnimationTree",true,false): tree.active = false
		for player in candidate.find_children("*","AnimationPlayer",true,false):
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for player in original.find_children("*","AnimationPlayer",true,false):
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		players.append(_bake(candidate,skeleton))
		var pad := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = pad_size
		pad.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("d55a40")
		# The front pad must not hide the face, guard and contact fist.
		# Side view retains an opaque target for reading the contact plane.
		if index == 0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = 0.18
		material.roughness = 0.8
		pad.material_override = material
		holder.add_child(pad)
		pads.append(pad)
	_verify_expression()
	_verify_motion()
	_set_motion_view()
	_pose(contact)
	for index in 2:
		# Calibrate once to actual curled knuckles, then keep the pad fixed.
		# The joint is inside the closed hand. Place the pad face just behind
		# that joint plane so the actual curled skin meets it, rather than
		# leaving the visible gap of a forward-offset bone-only calibration.
		var center := _knuckle(index)+Vector3(0,0,pad_size.z*0.5-0.012)
		pad_centers.append(center)
		pads[index].position = center
	_pose(0.0)
	_expect(not _overlap(0),"Guard fist is clear of the fixed pad")
	_pose(contact)
	contact_verified = _overlap(0)
	_expect(contact_verified,"Impact knuckles reach the fixed pad face (2.5 cm contact proxy)")
	_pose(duration)
	_expect(not _overlap(0),"Recovered fist leaves the fixed pad")
	_pose(0.0)
	if "--capture" in OS.get_cmdline_user_args():
		await _captures()
	elif DisplayServer.get_name() == "headless":
		_finish()
	else:
		running = true

func _freeze_secondary(node: Node) -> void:
	# Diagnostic option: isolate authored skin deformation from VRM springs.
	# In Godot 4.6 the importer drives springs through an INTERNAL modifier;
	# disabling Node._process alone does not stop that callback.
	if node is SkeletonModifier3D:
		node.active = false
	if node is Skeleton3D:
		node.clear_bones_global_pose_override()
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(true):
		_freeze_secondary(child)

func _semantic(name: String) -> String:
	return name.left(1).to_upper()+name.substr(1)

func _reset(skeleton: Skeleton3D) -> void:
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(bone)
		skeleton.set_bone_pose_position(bone,rest.origin)
		skeleton.set_bone_pose_rotation(bone,rest.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(bone,rest.basis.get_scale())

func _bake(candidate: Node3D,skeleton: Skeleton3D) -> AnimationPlayer:
	var animation := Animation.new()
	animation.length = duration
	animation.loop_mode = Animation.LOOP_LINEAR
	var tracks: Dictionary = {}
	var missing: Array[String] = []
	var map: Dictionary = {}
	for name: String in motion.frames[0].rotations:
		var bone := skeleton.find_bone(_semantic(name))
		if bone < 0:
			missing.append(name)
			continue
		map[bone] = name
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track,str(candidate.get_path_to(skeleton))+":"+skeleton.get_bone_name(bone))
		animation.track_set_interpolation_type(track,Animation.INTERPOLATION_LINEAR)
		tracks[bone] = track
	_expect(missing.is_empty(),"All baked humanoid bones map to native VRM skeleton: "+str(missing))
	var hips := skeleton.find_bone("Hips")
	var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(position_track,str(candidate.get_path_to(skeleton))+":Hips")
	var sorted_bones: Array = map.keys()
	sorted_bones.sort_custom(func(a: int,b: int) -> bool: return _depth(skeleton,a)<_depth(skeleton,b))
	var previous: Dictionary = {}
	for frame: Dictionary in motion.frames:
		_reset(skeleton)
		for bone: int in sorted_bones:
			var values: Array = frame.rotations[map[bone]]
			var delta := Quaternion(float(values[0]),float(values[1]),float(values[2]),float(values[3])).normalized()
			var desired := Basis(delta)*skeleton.get_bone_global_rest(bone).basis
			var parent := skeleton.get_bone_parent(bone)
			var parent_basis := Basis.IDENTITY if parent<0 else skeleton.get_bone_global_pose(parent).basis
			var rotation := (parent_basis.inverse()*desired).orthonormalized().get_rotation_quaternion()
			if previous.has(bone) and (previous[bone] as Quaternion).dot(rotation)<0.0:
				rotation = -rotation
			previous[bone] = rotation
			skeleton.set_bone_pose_rotation(bone,rotation)
			if bone == hips:
				var translation: Array = frame.hips_translation
				var world_position := skeleton.get_bone_global_rest(hips).origin+Vector3(float(translation[0]),float(translation[1]),float(translation[2]))
				var parent_global := Transform3D.IDENTITY if parent<0 else skeleton.get_bone_global_pose(parent)
				skeleton.set_bone_pose_position(hips,parent_global.affine_inverse()*world_position)
			animation.rotation_track_insert_key(int(tracks[bone]),float(frame.time),rotation)
		animation.position_track_insert_key(position_track,float(frame.time),skeleton.get_bone_pose_position(hips))
	_reset(skeleton)
	var player := AnimationPlayer.new()
	player.name = "BlenderPunchPreview"
	candidate.add_child(player)
	player.owner = candidate
	player.root_node = NodePath("..")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new()
	library.add_animation("straight_punch",animation)
	player.add_animation_library("",library)
	player.play("straight_punch",0.0)
	player.seek(0.0,true)
	if players.is_empty():
		_expect(ResourceSaver.save(animation,"res://user_assets/straight_punch.res",ResourceSaver.FLAG_COMPRESS)==OK,"Native reusable punch Animation saved privately")
	return player

func _depth(skeleton: Skeleton3D,bone: int) -> int:
	var depth := 0
	var parent := skeleton.get_bone_parent(bone)
	while parent>=0:
		depth+=1
		parent=skeleton.get_bone_parent(parent)
	return depth

func _pose(time: float) -> void:
	elapsed = time
	for player in players:
		player.seek(minf(time,duration-0.000001),true)
	var phase := "GUARD"
	if time>0.02 and time<0.30: phase = "WIND-UP"
	elif time>=0.30 and time<0.48: phase = "IMPACT" if absf(time-contact)<0.002 else "DRIVE"
	elif time>=0.48 and time<0.95: phase = "RECOVERY"
	title.text = "PHASE 1F  /  BLENDER STRAIGHT PUNCH  /  "+phase+"  /  %.3fs"%time
	footer.text = "LEFT: FRONT  |  RIGHT: SIDE    •    Fixed practice pad; animation contact test, no game damage\nScripted Blender Action — first pass for review, quality is not guaranteed"
	if "--freeze-secondary" in OS.get_cmdline_user_args():
		footer.text = "LEFT: FRONT  |  RIGHT: SIDE    •    VRM springs disabled to inspect authored deformation\nScripted Blender Action — fixed contact fixture; no game damage or production-quality approval"

func _point(index: int,name: String) -> Vector3:
	var skeleton := skeletons[index]
	return holders[index].to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin))

func _knuckle(index: int) -> Vector3:
	return (_point(index,"LeftIndexIntermediate")+_point(index,"LeftMiddleIntermediate"))*0.5

func _overlap(index: int) -> bool:
	var difference := (_knuckle(index)-pad_centers[index]).abs()-pad_size*0.5
	return Vector3(maxf(difference.x,0),maxf(difference.y,0),maxf(difference.z,0)).length()<0.025

func _verify_motion() -> void:
	var finite := true
	var maximum_step := 0.0
	var previous: Dictionary = {}
	for frame: Dictionary in motion.frames:
		_pose(float(frame.time))
		for bone in skeletons[0].get_bone_count():
			var pose := skeletons[0].get_bone_global_pose(bone)
			finite = finite and pose.is_finite()
			var q := pose.basis.get_rotation_quaternion()
			if previous.has(bone): maximum_step=maxf(maximum_step,q.angle_to(previous[bone]))
			previous[bone]=q
	_expect(finite,"All baked animation bone transforms are finite at every frame")
	_pose(0.0)
	var begin: Array[Transform3D] = []
	for bone in skeletons[0].get_bone_count(): begin.append(skeletons[0].get_bone_global_pose(bone))
	_pose(duration)
	var loop_error := 0.0
	for bone in skeletons[0].get_bone_count():
		var end := skeletons[0].get_bone_global_pose(bone)
		loop_error=maxf(loop_error,end.origin.distance_to(begin[bone].origin))
	_expect(loop_error<0.001,"Recovered stance matches the starting guard without a loop position snap")
	print("BAKED_MOTION maximum per-frame global rotation step radians: ",maximum_step)

func _verify_expression() -> void:
	var candidate := candidates[0]
	var found := candidate.find_children("*","AnimationPlayer",true,false)
	for player: AnimationPlayer in found:
		if player == players[0]: continue
		var blink := ""
		for clip in player.get_animation_list():
			if str(clip)=="blink" or str(clip).ends_with("/blink"): blink=clip
		if blink.is_empty(): continue
		var meshes := candidate.find_children("*","MeshInstance3D",true,false)
		var baseline: Array = []
		for mesh: MeshInstance3D in meshes:
			var values: Array = []
			for i in mesh.mesh.get_blend_shape_count(): values.append(mesh.get_blend_shape_value(i))
			baseline.append(values)
		player.play(blink,0.0)
		player.seek(0.0,true)
		var change := 0.0
		for m in meshes.size():
			var mesh: MeshInstance3D = meshes[m]
			for i in baseline[m].size(): change+=absf(mesh.get_blend_shape_value(i)-float(baseline[m][i]))
		player.stop()
		for m in meshes.size():
			var mesh: MeshInstance3D = meshes[m]
			for i in baseline[m].size(): mesh.set_blend_shape_value(i,float(baseline[m][i]))
		expression_verified=change>0.1
		break
	_expect(expression_verified,"Imported blink still drives facial morphs independently of the punch")

func _set_neutral_view(angle: float) -> void:
	for index in 2:
		originals[index].visible=index==0
		candidates[index].visible=index==1
		holders[index].rotation.y=angle
		_reset(skeletons[index])
		pads[index].visible=false
	title.text="PHASE 1F  /  NEUTRAL PROPORTIONS  /  ORIGINAL vs MODIFIED"
	footer.text="LEFT: ORIGINAL VRM  |  RIGHT: CONTROLLED BODY EDIT    •    Same camera, scale and lighting\nFace, hair, textures and expressions preserved; no bone scaling"
	if "--freeze-secondary" in OS.get_cmdline_user_args():
		footer.text += " • VRM springs disabled in both views"

func _set_motion_view() -> void:
	for index in 2:
		originals[index].visible=false
		candidates[index].visible=true
		holders[index].rotation.y=0.0 if index==0 else PI*0.5
		pads[index].visible=true

func _build_studio() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("17222e")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("c5d7e6")
	settings.ambient_light_energy=0.38
	environment.environment=settings
	add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-28,-25,0)
	key.light_energy=0.9
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-15,145,0)
	fill.light_color=Color("bad9ff")
	fill.light_energy=0.28
	add_child(fill)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(10,10)
	floor.mesh=plane
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("26394a")
	material.roughness=1.0
	floor.material_override=material
	add_child(floor)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2.55
	camera.position=Vector3(0,0.95,5)
	add_child(camera)
	camera.look_at(Vector3(0,0.95,0))
	camera.current=true
	var overlay := CanvasLayer.new()
	add_child(overlay)
	title=Label.new()
	title.position=Vector2(24,18)
	title.add_theme_font_size_override("font_size",20)
	overlay.add_child(title)
	footer=Label.new()
	footer.position=Vector2(24,get_viewport().get_visible_rect().size.y-66)
	footer.add_theme_font_size_override("font_size",16)
	overlay.add_child(footer)

func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	_expect(screenshot!=null and not screenshot.is_empty(),filename+" contains rendered pixels")
	if screenshot!=null: _expect(screenshot.save_png("res://results/"+filename)==OK,filename+" saved privately")

func _captures() -> void:
	if DisplayServer.get_name()=="headless":
		_expect(false,"Graphical display required for capture")
		_finish()
		return
	await _frames(4)
	for view in [[0.0,"neutral_front.png"],[PI*0.5,"neutral_side.png"],[PI*0.25,"neutral_threequarter.png"]]:
		_set_neutral_view(float(view[0]))
		await _frames(2)
		await _capture(str(view[1]))
	_set_motion_view()
	for sample in [[0.0,"guard.png"],[0.2,"windup.png"],[contact,"impact.png"],[0.6,"recovery.png"]]:
		_pose(float(sample[0]))
		await _frames(2)
		await _capture(str(sample[1]))
	if "--stills" in OS.get_cmdline_user_args():
		_finish()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://results/frames"))
	for frame: Dictionary in motion.frames:
		_pose(float(frame.time))
		await _frames(1)
		await _capture("frames/frame_%04d.png"%roundi(float(frame.time)*float(motion.fps)))
	_finish()

func _process(delta: float) -> void:
	if running:
		_pose(fmod(elapsed+delta,duration))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: get_tree().quit()

func _finish() -> void:
	var report := {"failures":failures,"graphical":DisplayServer.get_name()!="headless","baked_blender_action":true,"expression_blink_checked":expression_verified,"fixed_pad_contact_verified":contact_verified,"secondary_frozen":"--freeze-secondary" in OS.get_cmdline_user_args(),"scope":"Private single-punch and proportion experiment; no live gameplay modification"}
	var file := FileAccess.open("res://results/review_punch.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PRIVATE BLENDER PUNCH REVIEW: ","passed" if failures.is_empty() else "failed")
	get_tree().quit(0 if failures.is_empty() else 1)
