extends RefCounted
## Experimental pose transfer only; no character files or combat dependencies.
## Both raw glTF skeleton spaces must face +Z, with +Y up. Call after advancing
## the source AnimationPlayer. Extra target finger/face bones remain untouched.

const BONES := {
	"hips":"Hips", "spine":"Spine", "chest":"Chest", "neck":"Neck", "head":"Head",
	"upper_arm.L":"LeftUpperArm", "forearm.L":"LeftLowerArm", "hand.L":"LeftHand",
	"upper_arm.R":"RightUpperArm", "forearm.R":"RightLowerArm", "hand.R":"RightHand",
	"thigh.L":"LeftUpperLeg", "shin.L":"LeftLowerLeg", "foot.L":"LeftFoot",
	"thigh.R":"RightUpperLeg", "shin.R":"RightLowerLeg", "foot.R":"RightFoot"
}
const CHILDREN := {
	"upper_arm.L":"forearm.L", "forearm.L":"hand.L",
	"upper_arm.R":"forearm.R", "forearm.R":"hand.R",
	"thigh.L":"shin.L", "shin.L":"foot.L",
	"thigh.R":"shin.R", "shin.R":"foot.R"
}
var source: Skeleton3D
var target: Skeleton3D
var mappings: Array[Dictionary] = []
var missing := PackedStringArray()
var height_ratio: float = 1.0

func setup(from: Skeleton3D, to: Skeleton3D) -> PackedStringArray:
	source = from
	target = to
	mappings.clear()
	missing.clear()
	if source == null or target == null:
		missing.append("Source and target Skeleton3D are required")
		return missing
	for name: String in BONES:
		var s: int = source.find_bone(name)
		var t: int = target.find_bone(BONES[name])
		if s < 0 or t < 0:
			missing.append(name+" -> "+str(BONES[name]))
			continue
		var sr: Basis = source.get_bone_global_rest(s).basis.orthonormalized()
		var tr: Basis = target.get_bone_global_rest(t).basis.orthonormalized()
		var correction: Basis = sr.inverse()*tr
		if CHILDREN.has(name):
			var sc: int = source.find_bone(CHILDREN[name])
			var tc: int = target.find_bone(BONES[CHILDREN[name]])
			if sc >= 0 and tc >= 0:
				correction = _axis_correction(s,t,sc,tc)
		elif name.begins_with("hand."):
			# Source hands have no finger children: their +Y bone axis follows the
			# forearm. The donor's middle-finger root supplies its hand direction.
			var finger: int = target.find_bone("LeftMiddleProximal" if name.ends_with("L") else "RightMiddleProximal")
			if finger >= 0:
				var td := target.get_bone_global_rest(finger).origin-target.get_bone_global_rest(t).origin
				correction = (sr.inverse()*_frame(sr.y))*(tr.inverse()*_frame(td)).inverse()
		mappings.append({"source":s,"target":t,"name":name,"correction":correction})
	mappings.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return _depth(int(a.target)) < _depth(int(b.target)))
	var sh: int = source.find_bone("hips")
	var th: int = target.find_bone("Hips")
	if sh >= 0 and th >= 0:
		height_ratio = target.get_bone_global_rest(th).origin.y/maxf(source.get_bone_global_rest(sh).origin.y,0.01)
	return missing

func _depth(index: int) -> int:
	var value: int = 0
	while index >= 0:
		index = target.get_bone_parent(index)
		value += 1
	return value

func _frame(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var z := Vector3.BACK-y*Vector3.BACK.dot(y)
	if z.length_squared() < 0.0001:
		z = Vector3.UP-y*Vector3.UP.dot(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x,y,x.cross(y).normalized())

func _axis_correction(s: int,t: int,sc: int,tc: int) -> Basis:
	var sr := source.get_bone_global_rest(s)
	var tr := target.get_bone_global_rest(t)
	var sd := source.get_bone_global_rest(sc).origin-sr.origin
	var td := target.get_bone_global_rest(tc).origin-tr.origin
	# Canonical frames are measured in each bone's LOCAL coordinates. At an
	# A/T-pose mismatch this aligns actual posed limb directions, rather than
	# copying local quaternions and leaving the donor's arms 45 degrees away.
	var sa := sr.basis.orthonormalized().inverse()*_frame(sd)
	var ta := tr.basis.orthonormalized().inverse()*_frame(td)
	return sa*ta.inverse()

func apply_pose() -> bool:
	if not missing.is_empty() or mappings.is_empty():
		return false
	for item in mappings:
		var s: int = item.source
		var t: int = item.target
		var desired: Basis = source.get_bone_global_pose(s).basis.orthonormalized()*Basis(item.correction)
		var parent: int = target.get_bone_parent(t)
		var parent_pose := target.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
		var rest := target.get_bone_rest(t)
		# Godot 4 bone poses are complete local transforms, not deltas added to
		# rest. Multiplying by inverse(rest) here would apply the correction twice.
		var local_rotation: Basis = parent_pose.basis.orthonormalized().inverse()*desired
		var rotation := local_rotation.get_rotation_quaternion().normalized()
		if not rotation.is_finite():
			return false
		target.set_bone_pose_rotation(t,rotation)
		var position := rest.origin
		if item.name == "hips":
			var offset := source.get_bone_global_pose(s).origin-source.get_bone_global_rest(s).origin
			var hip_position := target.get_bone_global_rest(t).origin+offset*height_ratio
			position = parent_pose.affine_inverse()*hip_position
		target.set_bone_pose_position(t,position)
	return true
