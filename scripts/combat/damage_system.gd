extends RefCounted
static func scaled(base: float, power: float, form_multiplier: float, counter: bool) -> float:
	return base * power * form_multiplier * (1.4 if counter else 1.0)

static func facing_source(victim: Node3D, source: Node3D) -> bool:
	if not is_instance_valid(source):
		return true
	var toward: Vector3 = source.global_position - victim.global_position
	return toward.length() < 0.1 or (-victim.global_basis.z).dot(toward.normalized()) > -0.1
