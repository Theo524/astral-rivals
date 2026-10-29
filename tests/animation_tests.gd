extends SceneTree
## Actual imported skeleton/skin/animation checks. This does not certify art quality.
## Run after Godot imports assets: godot --headless --path . --script res://tests/animation_tests.gd

const EXPECTED := ["idle", "walk", "run", "hover", "fly", "dash_forward", "dash_back", "punch_1", "punch_2", "punch_3", "kick", "heavy", "blast", "beam", "charge", "guard", "parry", "dodge", "hurt", "knockback", "recovery", "transform", "ultimate", "victory", "defeat"]
const Visual = preload("res://scripts/visuals/warrior_visual.gd")
const Roster = preload("res://scripts/data/character_data.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func _clip(player: AnimationPlayer, wanted: String) -> String:
	for animation in player.get_animation_list():
		if animation == wanted or animation.get_file() == wanted or animation.ends_with("|"+wanted):
			return animation
	return ""

func _check_character(identity: String) -> void:
	var path := "res://assets/characters/%s.glb" % identity
	_expect(ResourceLoader.exists(path), identity + " has an imported GLB asset")
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	_expect(scene != null, identity + " asset loads as a real PackedScene")
	if scene == null:
		return
	var model := scene.instantiate()
	root.add_child(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	_expect(not skeletons.is_empty(), identity + " imports an actual Skeleton3D")
	_expect(not players.is_empty(), identity + " imports an AnimationPlayer")
	if skeletons.is_empty() or players.is_empty():
		model.free()
		return
	var skeleton := skeletons[0] as Skeleton3D
	var player := players[0] as AnimationPlayer
	_expect(skeleton.get_bone_count() >= 18, identity + " retains the full articulated humanoid skeleton")
	var skinned_count: int = 0
	var body_surfaces_are_meshes: bool = true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin != null:
			skinned_count += 1
			body_surfaces_are_meshes = body_surfaces_are_meshes and mesh.mesh is ArrayMesh
	_expect(skinned_count >= 1, identity + " geometry uses real Skin weights")
	_expect(body_surfaces_are_meshes, identity + " imported body uses authored ArrayMesh surfaces rather than runtime primitives")
	var missing: Array[String] = []
	var finite_poses: bool = true
	for wanted in EXPECTED:
		var name: String = _clip(player, wanted)
		if name.is_empty():
			missing.append(wanted)
			continue
		var clip := player.get_animation(name)
		if clip.length <= 0.0 or clip.get_track_count() < 10:
			missing.append(wanted + " (invalid clip)")
		player.play(name)
		for fraction in [0.0, 0.41, 0.99]:
			player.seek(clip.length * fraction, true)
			for bone_index in skeleton.get_bone_count():
				if not skeleton.get_bone_pose(bone_index).is_finite():
					finite_poses = false
	_expect(missing.is_empty(), identity + " includes all 25 nonempty authored skeletal clips" + (": "+", ".join(missing) if not missing.is_empty() else ""))
	_expect(finite_poses, identity + " has finite bone poses across every clip's startup/contact/recovery")
	var arm: int = skeleton.find_bone("upper_arm.L")
	var thigh: int = skeleton.find_bone("thigh.R")
	if arm >= 0 and thigh >= 0:
		player.play(_clip(player, "idle"))
		player.seek(0.0, true)
		var idle_arm: Quaternion = skeleton.get_bone_pose_rotation(arm)
		var idle_leg: Quaternion = skeleton.get_bone_pose_rotation(thigh)
		player.play(_clip(player, "punch_1"))
		player.seek(player.current_animation_length * 0.41, true)
		_expect(idle_arm.angle_to(skeleton.get_bone_pose_rotation(arm)) > 0.18, identity + " punch changes the weighted arm at its contact frame")
		player.play(_clip(player, "kick"))
		player.seek(player.current_animation_length * 0.41, true)
		_expect(idle_leg.angle_to(skeleton.get_bone_pose_rotation(thigh)) > 0.4, identity + " kick changes the weighted leg at its contact frame")
	else:
		_expect(false, identity + " preserves named arm and leg bones for animation integration")
	player.stop()
	model.free()
	var wrapper := Visual.new()
	root.add_child(wrapper)
	for data in Roster.roster():
		if data.id == identity:
			wrapper.setup(data)
	_expect(wrapper.asset_error.is_empty() and wrapper.skeleton != null and wrapper.animation_player != null, identity + " runtime visual wrapper loads the imported skeleton")
	if wrapper.animation_player != null:
		_expect(wrapper.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, identity + " gameplay timing manually drives AnimationPlayer rather than rotating limbs")
		var all_forms: bool = true
		for form in 3:
			wrapper.set_form(form)
			wrapper.animate(1.0/60.0,"light",0.0,0.41,form,false)
			all_forms = all_forms and wrapper.form_index == form and wrapper.get_transform().is_finite()
		_expect(all_forms, identity + " all three transformation forms preserve a finite animated rig")
		wrapper.animate(1.0/60.0,"idle",0.0,0.0,0,false)
		var hand: int = wrapper.skeleton.find_bone("hand.L")
		if hand >= 0:
			var world_hand: Vector3 = wrapper.skeleton.global_transform * wrapper.skeleton.get_bone_global_pose(hand).origin
			_expect(world_hand.z < -0.15, identity + " imported fighting guard faces gameplay -Z after model-axis correction")
		else:
			_expect(false, identity + " keeps a named hand bone for facing verification")
		var moving_bone: int = wrapper.skeleton.find_bone("chest")
		var before: Quaternion = wrapper.skeleton.get_bone_pose_rotation(moving_bone)
		for i in 20:
			wrapper.animate(1.0/60.0,"idle",0.0,0.0,0,false)
		var after: Quaternion = wrapper.skeleton.get_bone_pose_rotation(moving_bone)
		_expect(before.angle_to(after) > 0.00005, identity + " repeated visual updates advance real breathing bone animation")
		wrapper.set_quality(0)
		_expect(wrapper.quality == 0 and wrapper.skeleton.get_bone_count() >= 18, identity + " low quality keeps the same complete skinned character")
	wrapper.free()

func _run() -> void:
	for identity in ["kaizen", "ryuzen", "akira"]:
		_check_character(identity)
	await process_frame
	print("ANIMATION TESTS: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
