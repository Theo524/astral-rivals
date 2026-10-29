extends RefCounted
## One authoritative state clock. Hit confirms and interrupts use simulation time.
var state: String = "idle"
var elapsed: float = 0.0
var duration: float = 0.0

func transition(next: String, length: float = 0.0) -> void:
	state = next
	elapsed = 0.0
	duration = length

func tick(delta: float) -> bool:
	elapsed += delta
	return duration > 0.0 and elapsed >= duration

func accepts_action() -> bool:
	return state in ["idle", "charge", "guard"]
