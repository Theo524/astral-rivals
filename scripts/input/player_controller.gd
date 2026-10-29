extends Node
## Keyboard, gamepad, and multitouch feed the exact same action path.
var fighter: Node
var camera: Camera3D
var touch: Node
var enabled: bool = true

func _physics_process(_delta: float) -> void:
	if not enabled or not is_instance_valid(fighter) or not is_instance_valid(camera) or fighter.hp <= 0.0:
		return
	var stick: Vector2 = Input.get_vector("left","right","forward","back")
	if is_instance_valid(touch):
		var mobile: Vector2 = touch.movement()
		if mobile.length() > stick.length():
			stick = mobile
	var forward: Vector3 = -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var movement: Vector3 = right*stick.x-forward*stick.y
	fighter.intent = {"move":movement,"ascend":_held("ascend"),"descend":_held("descend"),"guard":_held("guard"),"charge":_held("charge")}
	if _pressed("lock"):
		fighter.locked = not fighter.locked
		camera.locked = fighter.locked
	for action in ["attack","heavy","blast","special","dash","dodge","transform","sphere","homing","ultimate","nova"]:
		if _pressed(action):
			var resolved: String = action
			if action == "blast" and _held("charge"):
				resolved = "sphere"
			elif action == "blast" and _held("guard"):
				resolved = "homing"
			elif action == "heavy" and _held("charge"):
				resolved = "nova"
			elif action == "special" and fighter.form == 2 and fighter.energy >= 85.0:
				resolved = "ultimate"
			fighter.request_action(resolved)

func _held(action: String) -> bool:
	return (InputMap.has_action(action) and Input.is_action_pressed(action)) or (is_instance_valid(touch) and touch.held(action))

func _pressed(action: String) -> bool:
	var keyboard: bool = InputMap.has_action(action) and Input.is_action_just_pressed(action)
	var mobile: bool = is_instance_valid(touch) and touch.consume(action)
	return keyboard or mobile
