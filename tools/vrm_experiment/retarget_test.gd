extends SceneTree
## Mathematical regression using only the PUBLIC existing source character and
## a synthetic T-pose skeleton. It is not VRM rendering or deformation evidence.
## godot --headless --path . --script res://tools/vrm_experiment/retarget_test.gd

const Retarget = preload("res://tools/vrm_experiment/humanoid_retarget.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool,message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ",message)

func _target() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	# Identity rest bases and horizontal arms intentionally differ from the
	# source's angled A-pose and arbitrary Blender bone roll.
	var definitions := [
		["Hips",-1,Vector3(0,1,0)], ["Spine",0,Vector3(0,0.2,0)],
		["Chest",1,Vector3(0,0.2,0)], ["Neck",2,Vector3(0,0.3,0)],
		["Head",3,Vector3(0,0.1,0)],
		["LeftUpperArm",2,Vector3(0.3,0.24,0)],
		["LeftLowerArm",5,Vector3(0.35,0,0)], ["LeftHand",6,Vector3(0.3,0,0)],
		["RightUpperArm",2,Vector3(-0.3,0.24,0)],
		["RightLowerArm",8,Vector3(-0.35,0,0)], ["RightHand",9,Vector3(-0.3,0,0)],
		["LeftUpperLeg",0,Vector3(0.14,0,0)],
		["LeftLowerLeg",11,Vector3(0,-0.5,0)], ["LeftFoot",12,Vector3(0,-0.5,0)],
		["RightUpperLeg",0,Vector3(-0.14,0,0)],
		["RightLowerLeg",14,Vector3(0,-0.5,0)], ["RightFoot",15,Vector3(0,-0.5,0)],
		["LeftMiddleProximal",7,Vector3(0.1,0,0)],
		["RightMiddleProximal",10,Vector3(-0.1,0,0)]
	]
	for definition in definitions:
		var index: int = skeleton.get_bone_count()
		skeleton.add_bone(definition[0])
		skeleton.set_bone_parent(index,definition[1])
		skeleton.set_bone_rest(index,Transform3D(Basis.IDENTITY,definition[2]))
	skeleton.reset_bone_poses()
	return skeleton

func _run() -> void:
	var packed := load("res://assets/characters/kaizen.glb") as PackedScene
	if packed == null:
		printerr("FAIL: public source character is not imported")
		quit(1)
		return
	var model := packed.instantiate()
	root.add_child(model)
	var skeletons := model.find_children("*","Skeleton3D",true,false)
	var players := model.find_children("*","AnimationPlayer",true,false)
	if skeletons.is_empty() or players.is_empty():
		model.free()
		printerr("FAIL: public source character has no skeleton/player")
		quit(1)
		return
	var source := skeletons[0] as Skeleton3D
	var player := players[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var target := _target()
	var finger := Quaternion(Vector3.RIGHT,0.7)
	target.set_bone_pose_rotation(17,finger)
	var transfer := Retarget.new()
	_expect(transfer.setup(source,target).is_empty(),"All body bone mappings resolve")
	var worst: float = 0.0
	var samples: int = 0
	for clip in ["idle","walk","punch_1"]:
		if not player.has_animation(clip):
			_expect(false,"Missing source animation "+clip)
			continue
		player.play(clip)
		for fraction in [0.0,0.41,0.99]:
			player.seek(player.current_animation_length*fraction,true)
			_expect(transfer.apply_pose(),"Retarget produces finite transforms")
			for name: String in Retarget.CHILDREN:
				var child: String = Retarget.CHILDREN[name]
				var a: Vector3 = source.get_bone_global_pose(source.find_bone(child)).origin-source.get_bone_global_pose(source.find_bone(name)).origin
				var b: Vector3 = target.get_bone_global_pose(target.find_bone(Retarget.BONES[child])).origin-target.get_bone_global_pose(target.find_bone(Retarget.BONES[name])).origin
				worst = maxf(worst,a.normalized().angle_to(b.normalized()))
			_expect(target.get_bone_pose_rotation(17).is_equal_approx(finger),"Unmapped finger pose remains unchanged")
			for index in target.get_bone_count():
				_expect(target.get_bone_global_pose(index).is_finite(),"Finite target bone "+str(index))
			samples += 1
	_expect(samples == 9,"All three requested clips sampled at startup/contact/recovery")
	_expect(worst < 0.0001,"Mapped limb direction error below 0.0001 radians")
	print("RETARGET MATHEMATICS: samples=",samples," worst_direction_error_radians=",worst," failures=",failures)
	model.free()
	target.free()
	quit(0 if failures == 0 else 1)
