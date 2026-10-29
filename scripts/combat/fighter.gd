extends CharacterBody3D
## Shared player/AI combatant. Inputs request actions; the simulation owns timing.
signal hit_landed(victim: Node, damage: float, kind: String)
signal knocked_out(fighter: Node)
signal feedback(cue: String, position: Vector3, strength: float)

const StateMachine = preload("res://scripts/combat/combat_state_machine.gd")
const Combo = preload("res://scripts/combat/combo_system.gd")
const Energy = preload("res://scripts/combat/energy_system.gd")
const Forms = preload("res://scripts/combat/transformation_system.gd")
const Hits = preload("res://scripts/combat/hit_detection.gd")
const Damage = preload("res://scripts/combat/damage_system.gd")
const Visual = preload("res://scripts/visuals/warrior_visual.gd")

var data: Dictionary = {}
var is_player: bool = false
var target: Node3D
var game: Node
var projectiles: Node
var visual: Node3D
var machine = StateMachine.new()
var combo = Combo.new()
var energy_system = Energy.new()
var transformations = Forms.new()
var hp: float = 1100.0
var max_hp: float = 1100.0
var max_energy: float = 100.0
var energy: float:
	get: return energy_system.value
	set(value): energy_system.value = clampf(value, 0.0, 100.0)
var form: int:
	get: return transformations.form
	set(value): transformations.form = clampi(value, 0, 2)
var state: String:
	get: return machine.state
var state_time: float:
	get: return machine.elapsed
var color: Color = Color.CYAN
var locked: bool = true
var flying: bool = false
var intent: Dictionary = {"move":Vector3.ZERO}
var cooldowns: Dictionary = {}
var invulnerability: float = 0.0
var counter_timer: float = 0.0
var hit_done: bool = false
var guard_pressure: float = 0.0
var attack_step: int = 0
var shot_kind: String = "blast"
var knockback: Vector3 = Vector3.ZERO
var dash_direction: Vector3 = Vector3.FORWARD
var total_damage: float = 0.0
var enabled: bool = true
## Countdown/action lock preserves movement without buffering attacks.
var combat_locked: bool = false
var _wall_impact_cooldown: float = 0.0

func setup(character: Dictionary, player_controlled: bool) -> void:
	data = character.duplicate(true)
	is_player = player_controlled
	color = data.color
	max_hp = float(data.hp)
	hp = max_hp
	collision_layer = 2
	# Arena collision stays in CharacterBody3D. Rival separation is handled in
	# the horizontal plane below: symmetric capsule recovery can otherwise push
	# two coincident airborne fighters upward together indefinitely.
	collision_mask = 1
	platform_floor_layers = 1
	platform_wall_layers = 0
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.48
	capsule.height = 2.15
	collision.shape = capsule
	collision.position.y = 1.075
	add_child(collision)
	visual = Visual.new()
	add_child(visual)
	visual.setup(data)
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.3

func can_act() -> bool:
	return enabled and not combat_locked and hp > 0.0 and machine.accepts_action()

func damage_multiplier() -> float:
	return transformations.damage_multiplier() * float(data.get("power", 1.0))

func request_action(action: String) -> bool:
	if not enabled or combat_locked or hp <= 0.0:
		return false
	if action == "attack" and state == "light" and state_time > 0.07:
		combo.queued = true
		return true
	if action in ["dash", "dodge"]:
		if state in ["hurt", "dead", "transform", "beam", "ultimate"] or cooldowns.get(action, 0.0) > 0.0:
			return false
		var cost: float = 12.0 if action == "dodge" else 7.0
		if not energy_system.spend(cost):
			return false
		var movement: Vector3 = intent.get("move", Vector3.ZERO)
		dash_direction = movement.normalized() if movement.length() > 0.1 else -global_basis.z
		# Pursuit follows a launched rival vertically; sideways/backward input
		# continues to produce a deliberate directional dash.
		if action == "dash" and locked and is_instance_valid(target):
			var to_target: Vector3 = target.global_position-global_position
			var toward: Vector3 = to_target.normalized()
			if to_target.length()>2.0 and (movement.length()<0.1 or movement.normalized().dot(toward)>0.45):
				dash_direction = toward
				if absf(to_target.y)>0.5:
					flying = true
		if action == "dodge":
			dash_direction = global_basis.x * (1.0 if movement.dot(global_basis.x) >= 0.0 else -1.0)
			invulnerability = 0.34
			counter_timer = 0.0
		cooldowns[action] = 0.65 if action == "dodge" else 0.45
		_change_state("dodge" if action == "dodge" else "dash", 0.24)
		feedback.emit("dodge" if action == "dodge" else "dash", global_position + Vector3.UP, 0.2)
		return true
	if not can_act() or cooldowns.get(action, 0.0) > 0.0:
		return false
	if action == "transform":
		if not transformations.can_transform(energy):
			return false
		energy_system.spend(transformations.COSTS[form])
		form += 1
		_change_state("transform", 1.3)
		invulnerability = 1.3
		visual.set_form(form)
		feedback.emit("transform", global_position + Vector3.UP, 1.2)
		return true
	if action == "attack":
		attack_step = combo.next()
		_change_state("light", 0.34 if attack_step < 4 else 0.5)
		return true
	if action == "heavy":
		if not energy_system.spend(5.0):
			return false
		_change_state("heavy", 0.64)
		cooldowns.heavy = 0.75
		return true
	var costs: Dictionary = {"blast":7.0,"sphere":22.0,"homing":16.0,"special":38.0,"ultimate":85.0,"nova":30.0}
	if not costs.has(action):
		return false
	if action == "ultimate" and form < 2:
		return false
	if not energy_system.spend(float(costs[action])):
		return false
	shot_kind = {"special":"beam"}.get(action, action)
	_change_state("beam" if action == "special" else ("ultimate" if action == "ultimate" else "blast"), 1.6 if action == "special" else (2.6 if action == "ultimate" else 0.38))
	if action in ["special", "ultimate"]:
		feedback.emit("beam_charge",global_position+Vector3.UP,1.4 if action == "ultimate" else 0.6)
	cooldowns[action] = {"blast":0.24,"sphere":1.0,"homing":0.7,"special":3.0,"ultimate":8.0,"nova":2.0}[action]
	return true

func _change_state(next: String, duration: float = 0.0) -> void:
	machine.transition(next, duration)
	hit_done = false

func _physics_process(delta: float) -> void:
	if data.is_empty():
		return
	_wall_impact_cooldown = maxf(0.0,_wall_impact_cooldown-delta)
	if not enabled:
		_animate_visual(delta,0.0)
		return
	for key in cooldowns.keys():
		cooldowns[key] = maxf(0.0, float(cooldowns[key]) - delta)
	invulnerability = maxf(0.0, invulnerability - delta)
	counter_timer = maxf(0.0, counter_timer - delta)
	guard_pressure = maxf(0.0, guard_pressure - delta * 14.0)
	combo.tick(delta)
	var finished: bool = machine.tick(delta)
	if hp <= 0.0:
		velocity = knockback
		velocity.y -= 12.0 * delta
		knockback = knockback.move_toward(Vector3.ZERO, delta * 10.0)
		move_and_slide()
		_animate_visual(delta,0.0)
		return
	if finished:
		var chained: bool = state == "light" and combo.queued
		_change_state("idle")
		if chained:
			request_action("attack")
	var guard: bool = not combat_locked and bool(intent.get("guard",false))
	var charge: bool = not combat_locked and bool(intent.get("charge",false))
	if machine.accepts_action():
		var next: String = "guard" if guard else ("charge" if charge else "idle")
		if state != next:
			_change_state(next)
			if next == "charge":
				feedback.emit("charge",global_position+Vector3.UP,0.1)
	energy_system.regenerate(delta, state == "charge", float(data.energy_rate), form)
	if state == "guard":
		energy_system.value = maxf(0.0, energy - delta * 2.0)
	if locked and is_instance_valid(target) and target.hp > 0.0:
		var direction: Vector3 = target.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 18.0, 1.0))
	_update_movement(delta)
	_update_attacks()
	_animate_visual(delta,Vector2(velocity.x,velocity.z).length())

func _animate_visual(delta: float, speed: float) -> void:
	if not is_instance_valid(visual):
		return
	if visual.has_method("anim_context"):
		visual.anim_context(attack_step,velocity,-global_basis.z)
	var progress: float = state_time / machine.duration if machine.duration > 0.0 else 0.0
	visual.animate(delta,state,speed,progress,form,flying)

func _update_movement(delta: float) -> void:
	var movement: Vector3 = intent.get("move", Vector3.ZERO)
	if bool(intent.get("ascend",false)):
		movement.y = 1.0
	if bool(intent.get("descend",false)):
		movement.y = -1.0
	if movement.y > 0.1:
		flying = true
	if movement.y < -0.1 and global_position.y < 0.2:
		flying = false
	var speed: float = float(data.speed) * transformations.speed_multiplier()
	var move_factor: float = 1.0 if state == "idle" else (0.28 if state in ["guard","charge"] else 0.1)
	if movement.length() > 1.0:
		movement = movement.normalized()
	var desired: Vector3 = movement * speed * move_factor
	var movement_acceleration: float = 80.0
	if not locked and movement.length() > 0.15:
		rotation.y = lerp_angle(rotation.y, atan2(-movement.x,-movement.z), minf(14.0*delta,1.0))
	if state in ["dash","dodge"]:
		desired = dash_direction * (38.0 if state == "dash" else 30.0)
		if is_instance_valid(projectiles):
			projectiles.trail(global_position + Vector3.UP, color)
	elif state == "hurt":
		desired = knockback
		knockback = knockback.move_toward(Vector3.ZERO, delta * 20.0)
	elif state in ["light","heavy"] and state_time < (0.22 if state=="light" and attack_step==4 else 0.16) and is_instance_valid(target):
		var distance: float = global_position.distance_to(target.global_position)
		if distance>1.18 and distance<5.0:
			# Close to actual glove/foot contact distance during anticipation.
			# This is physical travel; it never extends the strike's hit reach.
			var approach_speed: float = minf(18.0 if state=="heavy" else 16.0,(distance-1.18)/maxf(delta,0.001))
			desired = (target.global_position-global_position).normalized()*approach_speed
			movement_acceleration = 140.0
			if absf(target.global_position.y-global_position.y)>0.5:
				flying = true
	velocity.x = move_toward(velocity.x,desired.x,delta*movement_acceleration)
	velocity.z = move_toward(velocity.z,desired.z,delta*movement_acceleration)
	if state == "hurt" or (state in ["dash","dodge"] and flying):
		velocity.y = desired.y
	elif flying:
		velocity.y = move_toward(velocity.y, desired.y, delta * 35.0)
	else:
		velocity.y = maxf(velocity.y - delta * 24.0, -25.0)
	move_and_slide()
	_separate_from_rival()
	# Rebound against actual props/cliffs rather than pinning a hurt fighter.
	if state=="hurt" and knockback.length()>9.0 and _wall_impact_cooldown<=0.0:
		for slide_index in get_slide_collision_count():
			var normal: Vector3 = get_slide_collision(slide_index).get_normal()
			if absf(normal.y)<0.45 and knockback.dot(normal)< -2.0:
				knockback = knockback.bounce(normal)*0.4
				_wall_impact_cooldown = 0.45
				feedback.emit("impact",global_position+Vector3.UP,0.65)
				break
	var horizontal := Vector2(position.x, position.z)
	if horizontal.length() > 41.0:
		horizontal = horizontal.normalized() * 41.0
		position.x = horizontal.x
		position.z = horizontal.y
		if state == "hurt" and knockback.length() > 8.0:
			hp = maxf(1.0, hp - 15.0)
			knockback *= -0.4
			feedback.emit("impact",global_position+Vector3.UP,0.8)
	position.y = clampf(position.y, 0.0, 23.0)
	if position.y<=0.01 and movement.y<=0.0 and velocity.y<=0.05 and state!="dash":
		flying = false

func _separate_from_rival() -> void:
	if not is_instance_valid(target) or target.hp<=0.0 or absf(global_position.y-target.global_position.y)>1.7:
		return
	var difference: Vector3 = global_position-target.global_position
	difference.y = 0.0
	var distance: float = difference.length()
	var body_spacing: float = 0.96
	if distance>=body_spacing:
		return
	# Use opposite deterministic directions for a coincident pair, avoiding
	# vertical recovery and a divide-by-zero without any random teleport.
	var outward: Vector3 = difference/distance if distance>0.001 else (Vector3.RIGHT if get_instance_id()<target.get_instance_id() else Vector3.LEFT)
	global_position += outward*(body_spacing-distance)
	var inward_speed: float = velocity.dot(outward)
	if inward_speed<0.0:
		velocity -= outward*inward_speed

func _update_attacks() -> void:
	if hit_done or combat_locked:
		return
	if state in ["light","heavy"]:
		# Imported punch clips contact at ~41% of 0.34s. The fourth roundhouse
		# is a longer 0.5s clip, so its contact is 0.205s rather than 0.14s.
		var active_at: float = 0.28 if state=="heavy" else (0.205 if attack_step==4 else 0.14)
		if state_time < active_at:
			return
		hit_done = true
		feedback.emit("swing",global_position+Vector3.UP,0.1)
		if not is_instance_valid(target) or target.hp <= 0.0:
			return
		var reach: float = 1.85 if state=="heavy" or attack_step==4 else 1.72
		if not Hits.melee_connects(self,target,reach,-global_basis.z):
			return
		var heavy: bool = state == "heavy"
		var finisher: bool = attack_step == 4
		var base: float = 92.0 if heavy else (52.0 if finisher else 29.0)
		var amount: float = Damage.scaled(base,float(data.power),transformations.damage_multiplier(),counter_timer>0.0)
		var force: Vector3 = (target.global_position - global_position).normalized() * (21.0 if heavy or finisher else 4.0)
		if heavy:
			force.y = 15.0
		elif finisher:
			force.y = 5.0
		if target.receive_hit(amount,force,self,"heavy" if heavy else "melee"):
			combo.confirm()
			total_damage += amount
			energy = minf(100.0,energy+3.0)
			hit_landed.emit(target,amount,state)
			counter_timer = 0.0
	elif state in ["blast","beam","ultimate"] and state_time >= (0.52 if state == "ultimate" else (0.32 if state == "beam" else 0.16)):
		hit_done = true
		if is_instance_valid(projectiles):
			projectiles.fire(self,shot_kind,1.0+float(form)*0.15)

func receive_hit(damage: float, force: Vector3, source: Node, kind: String) -> bool:
	if hp <= 0.0 or not enabled or combat_locked:
		return false
	if invulnerability > 0.0:
		if state == "dodge" and state_time <= 0.16:
			counter_timer = 1.1
			energy = minf(100.0,energy+4.0)
			feedback.emit("evade",global_position+Vector3.UP,0.5)
		return false
	if state == "guard" and Damage.facing_source(self,source):
		if state_time < 0.15 and kind in ["melee","heavy"]:
			energy = minf(100.0,energy+9.0)
			counter_timer = 1.0
			if is_instance_valid(source) and source.has_method("stagger"):
				source.stagger(0.55)
			feedback.emit("parry",global_position+Vector3.UP,0.55)
			return false
		guard_pressure += damage
		energy = maxf(0.0,energy-damage*0.13)
		if guard_pressure < 170.0 and energy > 0.0:
			hp = maxf(1.0,hp-damage*0.08)
			knockback = force*0.12
			feedback.emit("guard",global_position+Vector3.UP,0.2)
			return false
		guard_pressure = 0.0
		damage *= 1.25
		feedback.emit("guard_break",global_position+Vector3.UP,0.9)
	hp = maxf(0.0,hp-damage)
	knockback = force
	if force.y > 2.0:
		flying = true
	combo.queued = false
	_change_state("hurt",0.28 if damage < 65.0 else 0.55)
	invulnerability = 0.07
	feedback.emit("impact",global_position+Vector3.UP,clampf(damage/100.0,0.2,1.5))
	if hp <= 0.0:
		_change_state("dead")
		knocked_out.emit(self)
	return true

func stagger(duration: float) -> void:
	if hp > 0.0:
		_change_state("hurt",duration)
		knockback = global_basis.z*4.0
