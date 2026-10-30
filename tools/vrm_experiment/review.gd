extends Node3D
## Private inspection only. No combat systems or public character files change.
const Retarget = preload("humanoid_retarget.gd")
const MartialPose = preload("martial_pose.gd")
const FingerPose = preload("finger_pose.gd")
var donor: Node3D
var source: Node3D
var source_skeleton: Skeleton3D
var target_skeleton: Skeleton3D
var source_player: AnimationPlayer
var expression_player: AnimationPlayer
var mapper = Retarget.new()
var martial = MartialPose.new()
var fingers = FingerPose.new()
var camera: Camera3D
var title: Label
var clip: String = "idle"
var expression_baseline: Array[Dictionary] = []
var failures: Array[String] = []
var running: bool = false
var pad: StaticBody3D
var pad_shape: BoxShape3D
var pose_phase: float = 0.0
var contact_verified: bool = false
const CONTACT: float = 0.41

func _ready() -> void:
	call_deferred("_setup")

func _expect(value: bool, text: String) -> void:
	print("PASS: " if value else "FAIL: ",text)
	if not value:
		failures.append(text)

func _resolve(player: AnimationPlayer, short_name: String) -> String:
	for name in player.get_animation_list():
		if str(name) == short_name or str(name).ends_with("/"+short_name):
			return str(name)
	return ""

func _setup() -> void:
	var packed = load("res://user_assets/candidate.scn") as PackedScene
	if packed == null:
		printerr("Run the VRM importer before opening the review scene")
		get_tree().quit(1)
		return
	donor = packed.instantiate()
	add_child(donor)
	source = load("res://reference/source_kaizen.glb").instantiate()
	add_child(source)
	source.visible = false
	source_skeleton = source.find_children("*","Skeleton3D",true,false)[0]
	target_skeleton = donor.find_children("*","Skeleton3D",true,false)[0]
	source_player = source.find_children("*","AnimationPlayer",true,false)[0]
	expression_player = donor.find_children("*","AnimationPlayer",true,false)[0]
	for tree in donor.find_children("*","AnimationTree",true,false):
		tree.active = false
	source_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	expression_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var missing: PackedStringArray = mapper.setup(source_skeleton,target_skeleton)
	_expect(missing.is_empty(),"Required humanoid mappings found: "+str(missing))
	if not missing.is_empty():
		get_tree().quit(1)
		return
	var missing_martial: PackedStringArray = martial.setup(target_skeleton)
	var missing_fingers: PackedStringArray = fingers.setup(target_skeleton)
	_expect(missing_martial.is_empty(),"Martial arm/body joints available")
	_expect(missing_fingers.is_empty(),"Existing finger/thumb joints available")
	if not missing_martial.is_empty() or not missing_fingers.is_empty():
		get_tree().quit(1)
		return
	_verify_expressions()
	_verify_poses()
	_build_studio()
	_build_contact_pad()
	_select_clip("idle")
	running = true
	if "--capture" in OS.get_cmdline_user_args():
		await _captures()
	elif DisplayServer.get_name() == "headless":
		await _verify_contact()
		_finish()

func _verify_expressions() -> void:
	for mesh in donor.find_children("*","MeshInstance3D",true,false):
		var values: Array[float] = []
		for i in mesh.mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(i))
		expression_baseline.append({"mesh":mesh,"values":values})
	var blink := _resolve(expression_player,"blink")
	_expect(blink != "","Imported blink expression retained")
	if blink == "":
		return
	expression_player.play(blink,0.0)
	expression_player.seek(0.0,true)
	var change: float = 0.0
	for item in expression_baseline:
		for i in item.values.size():
			change += absf(item.mesh.get_blend_shape_value(i)-float(item.values[i]))
	_expect(change > 0.1,"Blink expression drives the imported facial morphs")
	expression_player.stop()
	for item in expression_baseline:
		for i in item.values.size():
			item.mesh.set_blend_shape_value(i,float(item.values[i]))

func _verify_poses() -> void:
	for wanted in ["idle","walk","punch_1"]:
		var name := _resolve(source_player,wanted)
		_expect(name != "",wanted+" source clip exists")
		if name == "":
			continue
		var finite: bool = true
		for fraction in [0.0,0.15,0.25,0.41,0.60,0.85,0.99]:
			source_player.play(name,0.0)
			source_player.seek(source_player.get_animation(name).length*fraction,true)
			clip = wanted
			finite = _apply_pose(fraction) and finite
			for bone in target_skeleton.get_bone_count():
				finite = finite and target_skeleton.get_bone_global_pose(bone).is_finite()
		_expect(finite,wanted+" corrected pose stays finite at seven sample times")
	_pose_at("idle",0.15)
	var idle_hand := _point("LeftHand")
	var head := _point("Head")
	_expect(idle_hand.y > _point("Chest").y and idle_hand.y < head.y+0.1,"Guard fist lies between chest and face")
	_pose_at("walk",0.25)
	_expect(_point("LeftHand").y < _point("Chest").y,"Walking hands stay below the chest")
	_pose_at("punch_1",CONTACT)
	var shoulder := _point("LeftUpperArm")
	var elbow := _point("LeftLowerArm")
	var fist := _point("LeftHand")
	var length := shoulder.distance_to(elbow)+elbow.distance_to(fist)
	_expect(shoulder.distance_to(fist) > length*0.88,"Contact pose extends the punching arm beyond 88 percent of its chain")
	_expect(fist.z > idle_hand.z+0.12,"Contact pose visibly advances the lead fist")
	var middle := target_skeleton.find_bone("LeftMiddleIntermediate")
	_expect(target_skeleton.get_bone_pose_rotation(middle).angle_to(target_skeleton.get_bone_rest(middle).basis.get_rotation_quaternion()) > 0.7,"Punch bends existing middle-finger joint into a fist")

func _point(name: String) -> Vector3:
	return target_skeleton.get_bone_global_pose(target_skeleton.find_bone(name)).origin

func _apply_pose(phase: float) -> bool:
	pose_phase = clampf(phase,0.0,1.0)
	var valid: bool = mapper.apply_pose()
	valid = martial.apply(clip,pose_phase) and valid
	var curl: float = 0.82 if clip == "idle" else (0.22 if clip == "walk" else 1.0)
	valid = fingers.apply(curl,curl) and valid
	return valid

func _pose_at(wanted: String, phase: float) -> void:
	_select_clip(wanted)
	source_player.seek(source_player.current_animation_length*phase,true)
	_apply_pose(phase)
	_update_label()

func _select_clip(wanted: String) -> void:
	clip = wanted
	var name := _resolve(source_player,wanted)
	if name == "":
		return
	var animation := source_player.get_animation(name)
	animation.loop_mode = Animation.LOOP_LINEAR
	source_player.play(name,0.0)
	source_player.seek(0.0,true)
	_apply_pose(0.0)
	if pad != null: pad.visible = wanted == "punch_1"
	_update_label()

func _update_label() -> void:
	if title != null:
		var description: String = "IDLE — GUARD" if clip == "idle" else "WALK"
		if clip == "punch_1":
			description = "PUNCH — WINDUP" if pose_phase < 0.30 else ("PUNCH — STRIKE" if pose_phase < 0.54 else "PUNCH — RECOVERY")
			if absf(pose_phase-CONTACT)<0.001: description = "PUNCH — CONTACT"
		title.text = "PHASE 1E  /  "+description+"  /  PHASE %.2f  /  %.3fs" % [pose_phase,source_player.current_animation_position]+"\n1 guard   2 walk   3 punch   TAB camera   ESC quit"
		if contact_verified and clip == "punch_1" and absf(pose_phase-CONTACT)<0.001:
			title.text += "\nPAD CONTACT VERIFIED — isolated physics fixture"

func _process(delta: float) -> void:
	if running:
		source_player.advance(delta)
		_apply_pose(fmod(source_player.current_animation_position/maxf(source_player.current_animation_length,0.001),1.0))
		_update_label()

func _knuckle() -> Vector3:
	return target_skeleton.global_transform*((_point("LeftIndexIntermediate")+_point("LeftMiddleIntermediate"))*0.5)

func _build_contact_pad() -> void:
	# A fixed, explicitly staged target for this avatar's reach. This is not a
	# game opponent or combat damage test. Contact must occur geometrically.
	_pose_at("punch_1",CONTACT)
	pad = StaticBody3D.new()
	pad.collision_layer = 128
	pad.collision_mask = 0
	pad.position = _knuckle()+Vector3(0,0,0.075)
	add_child(pad)
	pad_shape = BoxShape3D.new()
	pad_shape.size = Vector3(0.28,0.36,0.12)
	var collision := CollisionShape3D.new()
	collision.shape = pad_shape
	pad.add_child(collision)
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = pad_shape.size
	visual.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c8493c")
	material.roughness = 0.9
	visual.material_override = material
	pad.add_child(visual)

func _pad_overlap() -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.025
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY,_knuckle())
	query.collision_mask = 128
	var hits := get_world_3d().direct_space_state.intersect_shape(query,4)
	return not hits.is_empty() and hits[0].collider == pad

func _verify_contact() -> void:
	running = false
	_pose_at("punch_1",0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(not _pad_overlap(),"Guard pose does not touch the fixed pad")
	_pose_at("punch_1",CONTACT)
	await get_tree().physics_frame
	contact_verified = _pad_overlap()
	_expect(contact_verified,"Contact frame overlaps the fixed practice pad")
	_pose_at("punch_1",0.99)
	await get_tree().physics_frame
	_expect(not _pad_overlap(),"Recovered fist has left the fixed pad")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1: _select_clip("idle")
		if event.keycode == KEY_2: _select_clip("walk")
		if event.keycode == KEY_3: _select_clip("punch_1")
		if event.keycode == KEY_TAB: _camera(not camera.has_meta("close"))
		if event.keycode == KEY_ESCAPE: get_tree().quit()

func _build_studio() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("17222e")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c5d7e6")
	settings.ambient_light_energy = 0.38
	environment.environment = settings
	add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28,-25,0)
	key.light_energy = 0.9
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15,145,0)
	fill.light_color = Color("bad9ff")
	fill.light_energy = 0.28
	add_child(fill)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10,10)
	floor.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("26394a")
	material.roughness = 1.0
	floor.material_override = material
	add_child(floor)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	_camera(false)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	title = Label.new()
	title.position = Vector2(24,20)
	title.add_theme_font_size_override("font_size",18)
	overlay.add_child(title)

func _camera(close: bool) -> void:
	var head: Vector3 = target_skeleton.global_transform*target_skeleton.get_bone_global_pose(target_skeleton.find_bone("Head")).origin
	if close:
		camera.set_meta("close",true)
		var aim := head+Vector3(0,0.08,0)
		camera.position = aim+Vector3(0.17,0.04,1.2)
		camera.fov = 29.0
		camera.look_at(aim)
	else:
		camera.remove_meta("close")
		camera.position = Vector3(1.4,1.15,4.2)
		camera.fov = 28.0
		camera.look_at(Vector3(0,head.y*0.55,0))

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	_expect(screenshot != null and not screenshot.is_empty(),filename+" has rendered pixels")
	if screenshot != null:
		_expect(screenshot.save_png("res://results/"+filename) == OK,filename+" saved privately")

func _captures() -> void:
	if DisplayServer.get_name() == "headless":
		failures.append("Graphical display required for capture")
		_finish()
		return
	await _frames(4)
	running = false
	await _verify_contact()
	_pose_at("idle",0.15)
	_camera(false)
	await _frames(2)
	await _capture("idle_guard.png")
	_camera(true)
	await _frames(2)
	await _capture("guard_close_up.png")
	_camera(false)
	for sample in [["walk",0.25,"walking.png"],["punch_1",0.20,"punch_windup.png"],["punch_1",CONTACT,"punch_contact.png"]]:
		var wanted: String = sample[0]
		_pose_at(wanted,float(sample[1]))
		if wanted == "punch_1":
			camera.position = Vector3(3.3,1.7,-0.8)
			camera.look_at(Vector3(0,1.0,0.3))
		await _frames(2)
		await _capture(str(sample[2]))
	_finish()

func _finish() -> void:
	var report := {"failures":failures,"tested_clips":["idle","walk","punch_1"],"expression_blink_checked":true,"pad_contact_verified":contact_verified,"graphical":DisplayServer.get_name() != "headless","scope":"Private pose correction and staged pad contact; no live gameplay damage"}
	var file := FileAccess.open("res://results/review.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PRIVATE VRM REVIEW: ","passed" if failures.is_empty() else "failed")
	get_tree().quit(0 if failures.is_empty() else 1)
