extends Node
## Intent-based opponent with a fair opening, observable reaction delays and
## bounded attack cadence. It uses the player's exact action/damage path.

var fighter: Node
var target: Node
var difficulty: int = 1
var training: bool = false
var rng := RandomNumberGenerator.new()
var active_combat_time: float = 0.0
var opening_grace: float = 1.0
var beam_unlock_time: float = 6.0
var ranged_unlock_time: float = 3.0

var _decision_time: float = 0.3
var _guard_time: float = 0.0
var _charge_time: float = 0.0
var _attack_time: float = 0.0
var _ranged_time: float = 0.0
var _defense_time: float = 0.0
var _strafe: float = 1.0
var _combo_remaining: int = 0
var _combo_time: float = 0.0
var _target_state: String = ""
var _target_state_time: float = 0.0
var _responded: bool = false
var _last_attack: String = ""
var _melee_committed: bool = false
var _was_locked: bool = false
var _was_training: bool = false

func _ready() -> void:
	rng.seed = 9037
	reset_opening()

func reset_opening() -> void:
	active_combat_time = 0.0
	_decision_time = 0.3
	_guard_time = 0.0
	_charge_time = 0.0
	_attack_time = 0.0
	_ranged_time = 0.0
	_defense_time = 0.0
	_combo_remaining = 0
	_combo_time = 0.0
	_last_attack = ""
	_melee_committed = false
	_target_state = ""
	_target_state_time = 0.0
	_responded = false

func _physics_process(delta: float) -> void:
	if not is_instance_valid(fighter) or not is_instance_valid(target):
		return
	if fighter.hp<=0.0 or target.hp<=0.0:
		fighter.intent = {"move":Vector3.ZERO}
		return
	if fighter.combat_locked:
		fighter.intent = {"move":Vector3.ZERO}
		_was_locked = true
		_combo_remaining = 0
		return
	if training:
		fighter.intent = {"move":Vector3.ZERO,"guard":false,"charge":false}
		_was_training = true
		_combo_remaining = 0
		return
	if _was_locked or _was_training:
		reset_opening()
		_was_locked = false
		_was_training = false
	active_combat_time += delta
	_guard_time = maxf(0.0,_guard_time-delta)
	_charge_time = maxf(0.0,_charge_time-delta)
	_attack_time = maxf(0.0,_attack_time-delta)
	_ranged_time = maxf(0.0,_ranged_time-delta)
	_defense_time = maxf(0.0,_defense_time-delta)
	_combo_time = maxf(0.0,_combo_time-delta)
	_decision_time -= delta
	var observed: String = target.state
	if observed!=_target_state:
		_target_state = observed
		_target_state_time = 0.0
		_responded = false
	else:
		_target_state_time += delta
	var offset: Vector3 = target.global_position-fighter.global_position
	var distance: float = offset.length()
	var toward := Vector3(offset.x,0.0,offset.z).normalized()
	var side := toward.cross(Vector3.UP)*_strafe
	var move := Vector3.ZERO
	if _charge_time<=0.0 and _guard_time<=0.0:
		if distance>2.6:
			move = toward
		elif distance<1.25:
			move = -toward*0.45
		elif fighter.state=="idle":
			move = side*0.25
		if absf(offset.y)>0.4:
			move.y = clampf(offset.y*0.65,-1.0,1.0)
	if move.length()>1.0:
		move = move.normalized()
	fighter.intent = {"move":move,"ascend":move.y>0.2,"descend":move.y< -0.2,"guard":_guard_time>0.0,"charge":_charge_time>0.0}
	var grace: float = opening_grace+[0.35,0.0,-0.2][clampi(difficulty,0,2)]
	if active_combat_time<maxf(grace,0.6):
		return
	if _combo_remaining>0 and _combo_time<=0.0:
		_combo_time = 0.19
		if distance>4.0 or fighter.state in ["hurt","guard","dodge","dead"]:
			_combo_remaining = 0
		elif not fighter.combo.queued and fighter.request_action("attack"):
			_combo_remaining -= 1
			_attack_time = [0.9,0.65,0.5][clampi(difficulty,0,2)]
	if _decision_time<=0.0:
		_decision_time = [0.45,0.30,0.20][clampi(difficulty,0,2)]+rng.randf_range(0.0,0.1)
		_decide(distance)

func _decide(distance: float) -> void:
	var skill: int = clampi(difficulty,0,2)
	# Reaction time starts when a tell is observed. One defensive response is
	# allowed per tell; the AI never reads a player's future input.
	var incoming: bool = _target_state in ["light","heavy","beam","blast","ultimate"] and (distance<4.5 or _target_state in ["beam","blast","ultimate"])
	if incoming and not _responded and _defense_time<=0.0 and _target_state_time >= [0.32,0.21,0.13][skill]:
		_responded = true
		if rng.randf()<[0.20,0.45,0.68][skill]:
			_charge_time = 0.0
			_defense_time = 0.8
			if _target_state in ["beam","ultimate"] or rng.randf()<0.25:
				fighter.request_action("dodge")
				_strafe *= -1.0
			else:
				_guard_time = rng.randf_range(0.25,0.42)
			return
	if not fighter.can_act() or _attack_time>0.0 or _combo_remaining>0:
		return
	if _charge_time>0.0:
		if distance<4.0:
			_charge_time = 0.0
		else:
			return
	if active_combat_time>5.0 and fighter.form<2 and fighter.energy>=66.0 and fighter.hp/fighter.max_hp<(0.75-fighter.form*0.22):
		_try_action("transform")
		return
	if fighter.energy<22.0 and distance>7.0:
		_charge_time = rng.randf_range(0.65,1.2)
		return
	if rng.randf()<0.12:
		_strafe *= -1.0
	if distance<3.0:
		if rng.randf()<[0.66,0.83,0.94][skill]:
			var use_heavy: bool = _last_attack!="heavy" and rng.randf()<0.24
			if _try_action("heavy" if use_heavy else "attack"):
				_melee_committed = true
				if not use_heavy:
					_combo_remaining = skill+1
					_combo_time = 0.19
		else:
			_guard_time = 0.3
		return
	# Melee-first opening. A beam can never be the first spawn attack even at
	# full energy, and ranged moves have a separate shared spacing timer.
	var range_allowed: bool = active_combat_time>=ranged_unlock_time and (_melee_committed or active_combat_time>8.0) and _ranged_time<=0.0
	if range_allowed and active_combat_time>=beam_unlock_time+float(2-skill) and distance>7.0:
		if fighter.form==2 and fighter.energy>=85.0 and _last_attack!="ultimate" and rng.randf()<0.12:
			_try_action("ultimate")
			return
		if fighter.energy>=40.0 and _last_attack!="special" and rng.randf()<[0.10,0.18,0.25][skill]:
			_try_action("special")
			return
	if range_allowed and distance>4.0 and fighter.energy>18.0 and rng.randf()<0.32:
		var shot: String = "blast"
		if _last_attack=="blast":
			shot = "homing" if skill>0 else "sphere"
		elif skill>0 and fighter.energy>35.0 and rng.randf()<0.25:
			shot = "sphere"
		_try_action(shot)
	elif distance>8.0 and rng.randf()<0.35:
		_try_action("dash")

func _try_action(action: String) -> bool:
	if not fighter.request_action(action):
		return false
	_last_attack = action
	_attack_time = [0.95,0.72,0.55][clampi(difficulty,0,2)]
	if action in ["blast","homing","sphere","special","ultimate"]:
		_ranged_time = [2.6,2.1,1.65][clampi(difficulty,0,2)]
	return true
