extends RefCounted
## Evaluated once during an attack's active frame, never from visual overlap.
static func melee_connects(attacker: Node3D, target: Node3D, reach: float, facing: Vector3) -> bool:
	var delta: Vector3 = target.global_position - attacker.global_position
	if absf(delta.y) > 2.5 or delta.length() > reach:
		return false
	return delta.length() < 0.5 or facing.dot(delta.normalized()) > 0.1
