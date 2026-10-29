extends RefCounted
var step: int = 0
var hits: int = 0
var window: float = 0.0
var queued: bool = false
var hit_timeout: float = 0.0

func tick(delta: float) -> void:
	window = maxf(0.0, window - delta)
	hit_timeout = maxf(0.0, hit_timeout - delta)
	if hit_timeout <= 0.0:
		hits = 0
	if window <= 0.0:
		step = 0

func next() -> int:
	step = step % 4 + 1
	window = 0.9
	queued = false
	return step

func confirm() -> void:
	hits += 1
	hit_timeout = 2.0
