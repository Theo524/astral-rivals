extends RefCounted
## Phase 1E upper-body correction, after legacy leg/hip retargeting.
## Uses existing humanoid joints and measured arm lengths; never edits meshes.
## Skeleton coordinates: +Y up, +Z forward. Finger curling is a separate layer.

const CONTACT: float = 0.41
const REQUIRED := ["Hips","Spine","Chest","Neck","Head",
	"LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand"]
var skeleton: Skeleton3D
var missing := PackedStringArray()
var bones: Dictionary = {}
var rest: Dictionary = {}
var lengths: Dictionary = {}
var body_frame := Basis.IDENTITY
var stature: float = 1.0

func setup(value: Skeleton3D) -> PackedStringArray:
	skeleton = value
	missing.clear()
	bones.clear()
	rest.clear()
	lengths.clear()
	if skeleton == null:
		missing.append("Skeleton3D required")
		return missing
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i)
		bones[name] = i
		rest[name] = skeleton.get_bone_global_rest(i)
	for name in REQUIRED:
		if not bones.has(name): missing.append(name)
	if not missing.is_empty(): return missing
	stature = maxf(0.1,Transform3D(rest.Head).origin.y)
	for side in ["Left","Right"]:
		var a: Vector3 = Transform3D(rest[side+"UpperArm"]).origin
		var b: Vector3 = Transform3D(rest[side+"LowerArm"]).origin
		var c: Vector3 = Transform3D(rest[side+"Hand"]).origin
		lengths[side] = Vector2(a.distance_to(b),b.distance_to(c))
	return missing

func _pose(name: String) -> Transform3D:
	return skeleton.get_bone_global_pose(int(bones[name]))

func _rest_local(name: String, rotation := Quaternion.IDENTITY) -> void:
	if not bones.has(name): return
	var i: int = bones[name]
	var local := skeleton.get_bone_rest(i)
	skeleton.set_bone_pose_position(i,local.origin)
	skeleton.set_bone_pose_rotation(i,(local.basis*Basis(rotation)).get_rotation_quaternion())

func _global_rotation(name: String, desired: Basis) -> bool:
	var i: int = bones[name]
	var parent: int = skeleton.get_bone_parent(i)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var q := (parent_basis.orthonormalized().inverse()*desired).get_rotation_quaternion().normalized()
	if not q.is_finite(): return false
	skeleton.set_bone_pose_rotation(i,q)
	return true

func _swing(name: String, child: String, direction: Vector3) -> bool:
	var original: Vector3 = Transform3D(rest[child]).origin-Transform3D(rest[name]).origin
	var reference: Basis = body_frame*Transform3D(rest[name]).basis.orthonormalized()
	var from: Vector3 = (body_frame*original).normalized()
	var swing := Quaternion(from,direction.normalized())
	return _global_rotation(name,Basis(swing)*reference)

func _hand(side: String, direction: Vector3, palm: Vector3) -> bool:
	var hand := side+"Hand"
	var middle := side+"MiddleProximal"
	var index := side+"IndexProximal"
	var little := side+"LittleProximal"
	if not rest.has(middle) or not rest.has(index) or not rest.has(little):
		return true
	var hand_rest: Transform3D = rest[hand]
	var forward: Vector3 = (Transform3D(rest[middle]).origin-hand_rest.origin).normalized()
	var across: Vector3 = Transform3D(rest[index]).origin-Transform3D(rest[little]).origin
	var normal: Vector3 = forward.cross(across).normalized()*(1.0 if side == "Left" else -1.0)
	var original := _frame(forward,normal)
	var correction: Basis = hand_rest.basis.orthonormalized().inverse()*original
	return _global_rotation(hand,_frame(direction,palm)*correction.inverse())

func _frame(direction: Vector3, palm: Vector3) -> Basis:
	var y := direction.normalized()
	var z := palm-y*palm.dot(y)
	if z.length_squared() < 0.0001:
		z = Vector3.BACK-y*Vector3.BACK.dot(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x,y,x.cross(y).normalized())

func _arm(side: String, wrist: Vector3, hint: Vector3, finger_direction: Vector3, palm: Vector3) -> bool:
	var upper := side+"UpperArm"
	var lower := side+"LowerArm"
	var hand := side+"Hand"
	var start := _pose(upper).origin
	var limb: Vector2 = lengths[side]
	var aim := wrist-start
	var distance := clampf(aim.length(),absf(limb.x-limb.y)+0.001,(limb.x+limb.y)*0.97)
	var direction := aim.normalized()
	var pole := hint-start-direction*(hint-start).dot(direction)
	if pole.length_squared() < 0.0001: pole = Vector3.DOWN-direction*Vector3.DOWN.dot(direction)
	pole = pole.normalized()
	var projection: float = (limb.x*limb.x-limb.y*limb.y+distance*distance)/(2.0*distance)
	var height: float = sqrt(maxf(0.0,limb.x*limb.x-projection*projection))
	var elbow: Vector3 = start+direction*projection+pole*height
	var wanted: Vector3 = start+direction*distance
	var good := _swing(upper,lower,elbow-start)
	good = _swing(lower,hand,wanted-elbow) and good
	return _hand(side,finger_direction,palm) and good

func _weight(phase: float, points: Array[Vector2]) -> float:
	for i in range(1,points.size()):
		if phase <= points[i].x:
			var t := inverse_lerp(points[i-1].x,points[i].x,phase)
			return lerpf(points[i-1].y,points[i].y,smoothstep(0.0,1.0,t))
	return points[-1].y

func apply(clip: String, phase: float) -> bool:
	if not missing.is_empty() or skeleton == null: return false
	if clip not in ["idle","walk","punch_1"]: return false
	phase = clampf(phase,0.0,1.0)
	var punch := clip == "punch_1"
	var walk := clip == "walk"
	var wind: float = _weight(phase,[Vector2(0,0),Vector2(0.20,1),Vector2(CONTACT,0),Vector2(1,0)]) if punch else 0.0
	var drive: float = _weight(phase,[Vector2(0,0),Vector2(0.20,0),Vector2(CONTACT,1),Vector2(0.49,0.98),Vector2(0.76,0),Vector2(1,0)]) if punch else 0.0
	var cycle := phase*TAU
	var yaw: float = sin(cycle)*0.045 if walk else -0.10-wind*0.20+drive*0.35
	# Remove inherited shoulder roll/twist. Trunk rotation is authored once per
	# sample from rest, so pausing or changing clips cannot accumulate rotations.
	_rest_local("Spine",Quaternion(Vector3.UP,yaw*0.35))
	_rest_local("Chest",Quaternion(Vector3.UP,yaw*0.45)*Quaternion(Vector3.RIGHT,0.025))
	_rest_local("UpperChest",Quaternion(Vector3.UP,yaw*0.20))
	_rest_local("Neck",Quaternion(Vector3.UP,-yaw*0.35))
	_rest_local("Head",Quaternion(Vector3.UP,-yaw*0.65)*Quaternion(Vector3.RIGHT,0.035))
	for side in ["Left","Right"]: _rest_local(side+"Shoulder")
	if punch and bones.has("LeftShoulder"):
		# Protract the clavicle with the straight punch rather than rotating the
		# upper arm alone against a static shirt/shoulder attachment. A slightly
		# lower strike keeps the humerus clear of the top sleeve seam. This is
		# a pose correction, not a guarantee for every garment's skin weights.
		var shoulder_basis := _pose("LeftShoulder").basis.orthonormalized()
		_global_rotation("LeftShoulder",Basis(Vector3.UP,-0.24*drive)*shoulder_basis)
	var chest_name := "UpperChest" if bones.has("UpperChest") else "Chest"
	body_frame = _pose(chest_name).basis.orthonormalized()*Transform3D(rest[chest_name]).basis.orthonormalized().inverse()
	var head := _pose("Head").origin
	var scale: float = stature/1.55
	var good: bool = true
	for side in ["Left","Right"]:
		var sign: float = 1.0 if side == "Left" else -1.0
		var start := _pose(side+"UpperArm").origin
		var limb: Vector2 = lengths[side]
		var length: float = limb.x+limb.y
		var wrist := Vector3(head.x+sign*0.17*scale,head.y-(0.13 if side == "Left" else 0.065)*scale,head.z+(0.29 if side == "Left" else 0.21)*scale)
		var hint := start+Vector3(sign*0.25,-0.29,0.09)*scale
		var fingers := Vector3(sign*0.04,0.92,0.35).normalized()
		var palm := Vector3(0,0,-1)
		if walk:
			var swing: float = -cos(cycle)*sign*length*0.24
			wrist = start+Vector3(sign*length*0.19,-length*0.91,swing)
			hint = start+Vector3(sign*0.20,-0.22,swing*0.35)*scale
			fingers = (wrist-start).normalized()
			palm = Vector3(-sign,0,0)
		elif punch and side == "Left":
			var chamber := Vector3(start.x+0.06*scale,head.y-0.22*scale,start.z+0.13*scale)
			wrist = wrist.lerp(chamber,wind)
			var impact := start+Vector3(-0.08,-0.12,1).normalized()*length*0.95
			wrist = wrist.lerp(impact,drive)
			fingers = fingers.lerp(Vector3.BACK,drive).normalized()
			palm = palm.lerp(Vector3.DOWN,drive).normalized()
		good = _arm(side,wrist,hint,fingers,palm) and good
	return good
