extends Node3D
## Private inspection only. No combat systems or public character files change.
const Retarget = preload("humanoid_retarget.gd")
var donor: Node3D
var source: Node3D
var source_skeleton: Skeleton3D
var target_skeleton: Skeleton3D
var source_player: AnimationPlayer
var expression_player: AnimationPlayer
var mapper = Retarget.new()
var camera: Camera3D
var title: Label
var clip: String = "idle"
var expression_baseline: Array[Dictionary] = []
var failures: Array[String] = []
var running: bool = false

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
	_verify_expressions()
	_verify_poses()
	_build_studio()
	_select_clip("idle")
	running = true
	if "--capture" in OS.get_cmdline_user_args():
		await _captures()
	elif DisplayServer.get_name() == "headless":
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
	var unmapped: Dictionary = {}
	for name in ["LeftMiddleProximal","RightMiddleProximal"]:
		var index := target_skeleton.find_bone(name)
		_expect(index >= 0,name+" finger joint retained")
		if index >= 0: unmapped[index] = target_skeleton.get_bone_pose_rotation(index)
	for wanted in ["idle","walk","punch_1"]:
		var name := _resolve(source_player,wanted)
		_expect(name != "",wanted+" source clip exists")
		if name == "":
			continue
		var finite: bool = true
		for fraction in [0.0,0.25,0.41,0.60,0.99]:
			source_player.play(name,0.0)
			source_player.seek(source_player.get_animation(name).length*fraction,true)
			finite = mapper.apply_pose() and finite
			for bone in target_skeleton.get_bone_count():
				finite = finite and target_skeleton.get_bone_global_pose(bone).is_finite()
			for index in unmapped:
				finite = finite and target_skeleton.get_bone_pose_rotation(index).is_equal_approx(unmapped[index])
		_expect(finite,wanted+" transfers finite poses at five sample times")

func _select_clip(wanted: String) -> void:
	clip = wanted
	var name := _resolve(source_player,wanted)
	if name == "":
		return
	var animation := source_player.get_animation(name)
	animation.loop_mode = Animation.LOOP_LINEAR
	source_player.play(name,0.0)
	source_player.seek(0.0,true)
	mapper.apply_pose()
	if title != null:
		title.text = "PRIVATE VRM EXPERIMENT  /  "+wanted.to_upper()+"\n1 idle   2 walk   3 punch   TAB camera   ESC quit"

func _process(delta: float) -> void:
	if running:
		source_player.advance(delta)
		mapper.apply_pose()

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
	source_player.seek(0.25,true)
	mapper.apply_pose()
	_camera(false)
	await _frames(2)
	await _capture("full_body.png")
	_camera(true)
	await _frames(2)
	await _capture("close_up.png")
	_camera(false)
	for wanted in ["walk","punch_1"]:
		_select_clip(wanted)
		source_player.seek(source_player.current_animation_length*0.41,true)
		mapper.apply_pose()
		if wanted == "punch_1":
			camera.position = Vector3(3.0,1.15,3.0)
			camera.look_at(Vector3(0,1.0,0))
		await _frames(2)
		await _capture(wanted+".png")
	_finish()

func _finish() -> void:
	var report := {"failures":failures,"tested_clips":["idle","walk","punch_1"],"expression_blink_checked":true,"graphical":DisplayServer.get_name() != "headless","scope":"Private isolated viewer; not a playable Kaizen replacement"}
	var file := FileAccess.open("res://results/review.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PRIVATE VRM REVIEW: ","passed" if failures.is_empty() else "failed")
	get_tree().quit(0 if failures.is_empty() else 1)
