extends RefCounted
var value: float = 60.0
var maximum: float = 100.0

func spend(cost: float) -> bool:
	if value + 0.001 < cost:
		return false
	value -= cost
	return true

func regenerate(delta: float, charging: bool, rate: float, form: int) -> void:
	var gain: float = (25.0 * rate if charging else 3.0) - float(form) * 0.65
	value = clampf(value + delta * gain, 0.0, maximum)
