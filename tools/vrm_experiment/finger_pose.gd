extends RefCounted
## Anatomy-derived finger curling for an existing humanoid rig. No mesh edits.
## setup() measures the rest hand; apply() writes absolute poses, without drift.

const FINGERS := ["Index","Middle","Ring","Little"]
const JOINTS := ["Proximal","Intermediate","Distal"]
var skeleton: Skeleton3D
var joints: Array[Dictionary] = []
var thumbs: Array[Dictionary] = []
var missing := PackedStringArray()

func setup(value: Skeleton3D) -> PackedStringArray:
	skeleton = value
	joints.clear()
	thumbs.clear()
	missing.clear()
	if skeleton == null:
		missing.append("Finger controller requires Skeleton3D")
		return missing
	for side in ["Left","Right"]:
		var hand: int = skeleton.find_bone(side+"Hand")
		var middle: int = skeleton.find_bone(side+"MiddleProximal")
		var index: int = skeleton.find_bone(side+"IndexProximal")
		var little: int = skeleton.find_bone(side+"LittleProximal")
		if mini(mini(hand,middle),mini(index,little)) < 0:
			missing.append(side+" hand landmarks")
			continue
		var forward: Vector3 = (_origin(middle)-_origin(hand)).normalized()
		var across: Vector3 = (_origin(index)-_origin(little)).normalized()
		var palm: Vector3 = forward.cross(across).normalized()*(1.0 if side == "Left" else -1.0)
		for finger_index in FINGERS.size():
			for joint_index in JOINTS.size():
				var name: String = side+FINGERS[finger_index]+JOINTS[joint_index]
				var bone: int = skeleton.find_bone(name)
				if bone < 0:
					missing.append(name)
					continue
				var direction: Vector3 = _direction(bone)
				var angle: float = [70.0+finger_index*2.0,95.0,55.0][joint_index]
				_add(bone,side,direction.cross(palm).normalized(),angle)
		var thumb_names := ["ThumbMetacarpal","ThumbProximal","ThumbDistal"]
		var chain: Array[int] = []
		for joint_index in thumb_names.size():
			var name: String = side+thumb_names[joint_index]
			var bone: int = skeleton.find_bone(name)
			if bone < 0:
				missing.append(name)
				continue
			_add(bone,side,Vector3.RIGHT,0.0)
			chain.append(bone)
		if chain.size() == 3:
			var inverse: Basis = skeleton.get_bone_global_rest(hand).basis.orthonormalized().inverse()
			var tip_children := skeleton.get_bone_children(chain[2])
			var terminal: float = _origin(chain[2]).distance_to(_origin(tip_children[0])) if not tip_children.is_empty() else _origin(chain[2]).distance_to(_origin(chain[1]))*0.7
			thumbs.append({"hand":hand,"index":index,"middle":middle,"chain":chain,"left":side == "Left",
				"index_pip":skeleton.find_bone(side+"IndexIntermediate"),"middle_pip":skeleton.find_bone(side+"MiddleIntermediate"),
				"palm":inverse*palm,"forward":inverse*forward,"span":_origin(hand).distance_to(_origin(middle)),"tip_length":terminal})
	return missing

func _origin(bone: int) -> Vector3:
	return skeleton.get_bone_global_rest(bone).origin

func _direction(bone: int) -> Vector3:
	var children := skeleton.get_bone_children(bone)
	if not children.is_empty():
		return (_origin(children[0])-_origin(bone)).normalized()
	# A distal phalanx may have no tip helper. Its parent segment gives a
	# stable anatomical direction independent of Blender/VRM bone-axis roll.
	var parent: int = skeleton.get_bone_parent(bone)
	return (_origin(bone)-_origin(parent)).normalized()

func _add(bone: int,side: String,world_axis: Vector3,degrees: float) -> void:
	var rest_global: Basis = skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	joints.append({"bone":bone,"left":side == "Left",
		"rest":skeleton.get_bone_rest(bone).basis.get_rotation_quaternion(),
		"axis":(rest_global.inverse()*world_axis).normalized(),
		"angle":deg_to_rad(degrees)})

func apply(left_amount: float,right_amount: float) -> bool:
	if skeleton == null or not missing.is_empty():
		return false
	for joint in joints:
		var amount: float = clampf(left_amount if joint.left else right_amount,0.0,1.0)
		var curl := Quaternion(Vector3(joint.axis),float(joint.angle)*amount)
		var rotation: Quaternion = (Quaternion(joint.rest)*curl).normalized()
		if not rotation.is_finite():
			return false
		skeleton.set_bone_pose_rotation(int(joint.bone),rotation)
	for thumb in thumbs:
		_fit_thumb(thumb,clampf(left_amount if thumb.left else right_amount,0.0,1.0))
	return true

func _posed(bone: int) -> Vector3:
	return skeleton.get_bone_global_pose(bone).origin

func _thumb_swing(hand: int,bone: int,rest_direction: Vector3,direction: Vector3,amount: float) -> void:
	var hand_delta: Basis = skeleton.get_bone_global_pose(hand).basis.orthonormalized()*skeleton.get_bone_global_rest(hand).basis.orthonormalized().inverse()
	var swing := Quaternion((hand_delta*rest_direction).normalized(),direction.normalized())
	var desired: Basis = Basis(swing)*hand_delta*skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	var parent: int = skeleton.get_bone_parent(bone)
	var local: Quaternion = (skeleton.get_bone_global_pose(parent).basis.orthonormalized().inverse()*desired).get_rotation_quaternion().normalized()
	var rest_q := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone,rest_q.slerp(local,amount).normalized())

func _fit_thumb(thumb: Dictionary,amount: float) -> void:
	if amount <= 0.0: return
	var chain: Array = thumb.chain
	var hand_basis := skeleton.get_bone_global_pose(int(thumb.hand)).basis.orthonormalized()
	var palm: Vector3 = hand_basis*Vector3(thumb.palm)
	var forward: Vector3 = hand_basis*Vector3(thumb.forward)
	var span: float = thumb.span
	# Fit existing segments to the outside of the finger roll. A scalar curl
	# chain made the thumb point away from the fist; these targets are measured
	# from the actual index/middle knuckles and preserve all three bone lengths.
	var base: Vector3 = _posed(chain[0])
	var first_target: Vector3 = _posed(thumb.index)-forward*span*0.35+palm*span*0.20
	_thumb_swing(thumb.hand,chain[0],_origin(chain[1])-_origin(chain[0]),first_target-base,amount)
	var start: Vector3 = _posed(chain[1])
	var target: Vector3 = (_posed(thumb.index_pip)+_posed(thumb.middle_pip))*0.5-forward*span*0.12+palm*span*0.10
	var l1: float = _origin(chain[2]).distance_to(_origin(chain[1]))
	var l2: float = thumb.tip_length
	var aim: Vector3 = target-start
	var distance: float = clampf(aim.length(),absf(l1-l2)+0.0001,(l1+l2)*0.995)
	var direction := aim.normalized()
	var pole := (palm-direction*palm.dot(direction)).normalized()
	var projection: float = (l1*l1-l2*l2+distance*distance)/(2.0*distance)
	var elbow: Vector3 = start+direction*projection+pole*sqrt(maxf(0.0,l1*l1-projection*projection))
	_thumb_swing(thumb.hand,chain[1],_origin(chain[2])-_origin(chain[1]),elbow-start,amount)
	_thumb_swing(thumb.hand,chain[2],_direction(chain[2]),start+direction*distance-_posed(chain[2]),amount)
