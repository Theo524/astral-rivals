extends RefCounted
var form: int = 0
const COSTS = [30.0, 55.0]

func can_transform(energy: float) -> bool:
	return form < 2 and energy >= COSTS[form]

func damage_multiplier() -> float:
	return [1.0, 1.17, 1.36][form]

func speed_multiplier() -> float:
	return [1.0, 1.12, 1.22][form]
