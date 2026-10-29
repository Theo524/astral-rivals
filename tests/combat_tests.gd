extends SceneTree
## Regression suite against real fighter and projectile implementations.
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/combat_tests.gd
## No input synthesis, mocks, renderer, imported assets, or third-party test addon.

const Fighter = preload("res://scripts/combat/fighter.gd")
const Roster = preload("res://scripts/data/character_data.gd")
const Projectiles = preload("res://scripts/combat/projectile_system.gd")
const AI = preload("res://scripts/combat/enemy_ai.gd")

var stage: Node3D
var attacker: CharacterBody3D
var defender: CharacterBody3D
var projectiles: Node3D
var ai: Node
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)


func _frames(count: int) -> void:
	for i in count:
		# physics_frame fires before simulation; process_frame observes its result.
		await physics_frame
		await process_frame


func _create_world() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 0.2, 100.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.1
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	attacker = Fighter.new()
	defender = Fighter.new()
	stage.add_child(attacker)
	stage.add_child(defender)
	attacker.setup(Roster.roster()[0], false)
	defender.setup(Roster.roster()[1], false)
	attacker.position = Vector3.ZERO
	defender.position = Vector3(0.0,0.0,-2.2)
	attacker.target = defender
	defender.target = attacker
	projectiles = Projectiles.new()
	stage.add_child(projectiles)
	projectiles.fighters = [attacker, defender]
	attacker.projectiles = projectiles
	defender.projectiles = projectiles
	ai = AI.new()
	stage.add_child(ai)
	ai.fighter = attacker
	ai.target = defender
	ai.set_physics_process(false)


func _reset(distance: float = 2.2) -> void:
	ai.set_physics_process(false)
	ai.training = false
	ai.reset_opening()
	projectiles.set_physics_process(true)
	for shot in projectiles.projectiles:
		projectiles._retire(shot)
	for beam in projectiles.beams:
		projectiles._retire(beam)
	for fighter in [attacker, defender]:
		fighter.set_physics_process(true)
		fighter.enabled = true
		fighter.combat_locked = false
		fighter.hp = fighter.max_hp
		fighter.energy = 60.0
		fighter.form = 0
		fighter.visual.set_form(0)
		fighter._change_state("idle")
		fighter.invulnerability = 0.0
		fighter.counter_timer = 0.0
		fighter.guard_pressure = 0.0
		fighter.velocity = Vector3.ZERO
		fighter.knockback = Vector3.ZERO
		fighter.intent = {"move": Vector3.ZERO}
		fighter.cooldowns.clear()
		fighter.combo.step = 0
		fighter.combo.hits = 0
		fighter.combo.window = 0.0
		fighter.combo.queued = false
		fighter.combo.hit_timeout = 0.0
		fighter.total_damage = 0.0
		fighter.flying = false
		fighter.locked = true
	attacker.position = Vector3.ZERO
	defender.position = Vector3(0.0, 0.0, -distance)
	attacker.rotation = Vector3.ZERO
	defender.rotation = Vector3(0.0, PI, 0.0)


func _test_melee_and_combo() -> void:
	_reset()
	await _frames(2)
	var hp_before: float = defender.hp
	_expect(attacker.request_action("attack"), "idle fighter accepts a light attack")
	await _frames(6)
	_expect(is_equal_approx(defender.hp, hp_before), "melee has no damage during its startup frames")
	await _frames(4)
	_expect(defender.hp < hp_before, "melee deals damage when its active frame arrives")
	_expect(attacker.combo.hits == 1, "a confirmed light attack increments the combo counter")
	_expect(attacker.request_action("attack") and attacker.combo.queued, "light attack accepts a buffered combo input")
	await _frames(13)
	_expect(attacker.attack_step == 2 and attacker.state == "light", "buffered input starts the second combo animation")
	_expect(not attacker.combo.queued, "starting the next combo step consumes the buffered input")
	await _frames(8)
	_expect(attacker.combo.hits >= 2, "the second combo step independently connects and confirms")


func _test_guard_and_parry() -> void:
	_reset()
	defender.intent = {"move": Vector3.ZERO, "guard": true}
	await _frames(2)
	var before: float = defender.hp
	var accepted: bool = defender.receive_hit(40.0, Vector3.FORWARD * 4.0, attacker, "melee")
	_expect(not accepted and is_equal_approx(defender.hp, before), "a newly raised guard parries melee without health damage")
	_expect(attacker.state == "hurt" and defender.counter_timer > 0.0, "parry staggers the attacker and opens a counter window")
	_reset()
	defender.intent = {"move": Vector3.ZERO, "guard": true}
	await _frames(14)
	before = defender.hp
	accepted = defender.receive_hit(100.0, Vector3.FORWARD * 4.0, attacker, "melee")
	_expect(not accepted and is_equal_approx(before - defender.hp, 8.0), "established guard reduces a strike to 8 percent chip damage")
	_expect(defender.state == "guard" and defender.energy < 60.0, "blocking consumes energy and preserves the guard state")
	before = defender.hp
	accepted = defender.receive_hit(100.0, Vector3.FORWARD * 4.0, attacker, "heavy")
	_expect(accepted and defender.state == "hurt", "sustained guard pressure breaks the guard")
	_expect(is_equal_approx(before - defender.hp, 125.0), "guard break applies the documented damage multiplier")

func _test_skeletal_contact_alignment() -> void:
	_reset(3.0)
	var before: float = defender.hp
	attacker.request_action("attack")
	attacker.machine.elapsed = 0.15
	attacker._update_attacks()
	_expect(defender.hp==before,"a punch cannot damage a rival three metres away without physically closing the gap")
	_reset(3.0)
	attacker.request_action("heavy")
	attacker.machine.elapsed = 0.3
	attacker._update_attacks()
	_expect(defender.hp==defender.max_hp,"a heavy kick also respects the shorter physical contact reach")
	_reset(1.3)
	attacker.combo.step = 3
	attacker.combo.window = 0.9
	_expect(attacker.request_action("attack") and attacker.attack_step==4,"the fourth buffered strike selects the roundhouse finisher")
	attacker.machine.elapsed = 0.15
	attacker._update_attacks()
	_expect(defender.hp==defender.max_hp,"roundhouse startup does not incorrectly connect at the earlier punch contact time")
	attacker.machine.elapsed = 0.21
	attacker._update_attacks()
	_expect(defender.hp<defender.max_hp-50.0,"roundhouse connects at the imported clip's forty-one percent contact pose")
	_reset(2.2)
	attacker.request_action("attack")
	await _frames(8)
	_expect(attacker.global_position.distance_to(defender.global_position)<1.72,"attack anticipation physically closes to glove contact distance before the active frame")
	await _frames(2)
	_expect(defender.hp<defender.max_hp,"close-range lunge and actual contact timing still form a working melee attack")
	_reset(0.0)
	await _frames(60)
	_expect(attacker.global_position.y<5.0 and defender.global_position.y<5.0 and absf(attacker.velocity.y)<10.0 and absf(defender.velocity.y)<10.0,"stacked fighters cannot feed moving-platform velocity into an upward launch loop")


func _test_dodge_and_launcher() -> void:
	_reset()
	await _frames(2)
	var before: float = attacker.hp
	_expect(attacker.request_action("dodge"), "dodge starts when energy is available")
	var accepted: bool = attacker.receive_hit(80.0, Vector3.BACK * 4.0, defender, "blast")
	_expect(not accepted and is_equal_approx(attacker.hp, before), "dodge invulnerability rejects an incoming hit")
	await _frames(25)
	accepted = attacker.receive_hit(80.0, Vector3.BACK * 4.0, defender, "blast")
	_expect(accepted and attacker.hp < before, "dodge invulnerability expires and later hits damage the fighter")
	_reset()
	await _frames(2)
	_expect(attacker.request_action("heavy"), "heavy attack starts with sufficient energy")
	await _frames(12)
	_expect(is_equal_approx(defender.hp, defender.max_hp), "heavy attack has a visible startup before damage")
	await _frames(8)
	_expect(defender.hp < defender.max_hp and defender.flying, "heavy attack damages and launches the defender")
	_expect(defender.global_position.y > 0.1 and defender.velocity.y > 0.0, "launcher causes an actual upward physics reaction")


func _test_energy_and_forms() -> void:
	_reset()
	attacker.energy = 0.0
	for action in ["heavy", "blast", "sphere", "homing", "special", "nova", "dash", "dodge", "transform"]:
		_expect(not attacker.request_action(action), "insufficient energy rejects " + action)
	_expect(attacker.state == "idle", "rejected abilities leave the combat state unchanged")
	attacker.energy = 100.0
	_expect(not attacker.request_action("ultimate"), "base form cannot activate an ultimate")
	var base_damage: float = attacker.damage_multiplier()
	var base_speed: float = attacker.transformations.speed_multiplier()
	_expect(attacker.request_action("transform"), "base form can transform when it can pay the cost")
	_expect(attacker.form == 1 and is_equal_approx(attacker.energy, 70.0), "awakening changes form and spends 30 energy")
	_expect(attacker.damage_multiplier() > base_damage and attacker.transformations.speed_multiplier() > base_speed, "awakening increases both damage and movement multipliers")
	_expect(attacker.state == "transform" and attacker.invulnerability > 1.0, "transformation has a timed cinematic state and protection")
	await _frames(82)
	_expect(attacker.state == "idle", "transformation returns control after its cinematic")
	attacker.energy = 100.0
	_expect(attacker.request_action("transform") and attacker.form == 2, "awakened form can reach ultimate form")
	_expect(is_equal_approx(attacker.energy, 45.0), "ultimate transformation spends 55 energy")
	await _frames(82)
	attacker.energy = 100.0
	_expect(not attacker.request_action("transform"), "ultimate form cannot transform past the final form")
	_expect(attacker.request_action("ultimate"), "ultimate form unlocks the ultimate attack")
	_expect(is_equal_approx(attacker.energy, 15.0), "ultimate attack spends its 85 energy cost")


func _test_projectiles_and_beams() -> void:
	_reset(5.0)
	await _frames(2)
	projectiles.set_physics_process(false)
	var before: float = defender.hp
	projectiles.fire(attacker, "blast")
	var active_shot: Dictionary = {}
	for shot in projectiles.projectiles:
		if shot.active:
			active_shot = shot
			break
	_expect(not active_shot.is_empty(), "firing acquires an active projectile from the pool")
	if not active_shot.is_empty():
		# Cross the target completely in one simulation step. Endpoint overlap
		# would miss this, so this specifically exercises swept hit detection.
		active_shot.velocity = Vector3.FORWARD * 900.0
		projectiles._physics_process(1.0 / 60.0)
		_expect(defender.hp < before, "swept projectile detects a target crossed between frame endpoints")
		_expect(not active_shot.active, "a projectile retires immediately after its hit")
	_reset(10.0)
	await _frames(2)
	before = defender.hp
	projectiles.fire(attacker, "beam")
	await _frames(50)
	_expect(defender.hp < before - 12.0, "beam applies repeated real damage ticks along its line")
	_expect(projectiles.active_count() > 0, "beam persists for its configured duration")
	await _frames(50)
	_expect(projectiles.active_count() == 0, "completed beams return to their fixed pool")


func _test_ko() -> void:
	_reset()
	var knockout_count := [0]
	var callback := func(_fighter: Node) -> void: knockout_count[0] += 1
	defender.knocked_out.connect(callback)
	var accepted: bool = defender.receive_hit(defender.hp + 100.0, Vector3.FORWARD * 4.0, attacker, "ultimate")
	_expect(accepted and defender.hp == 0.0 and defender.state == "dead", "lethal damage reaches zero health and the dead state")
	_expect(knockout_count[0] == 1, "lethal damage emits exactly one knockout signal")
	_expect(not defender.request_action("attack"), "a knocked-out fighter cannot request attacks")
	_expect(not defender.receive_hit(20.0, Vector3.ZERO, attacker, "blast") and knockout_count[0] == 1, "later hits cannot damage or repeat a knockout")
	defender.knocked_out.disconnect(callback)


func _test_ai_and_training() -> void:
	_reset(12.0)
	await _frames(2)
	ai.difficulty = 2
	ai.rng.seed = 9037
	ai.set_physics_process(true)
	var before: float = defender.hp
	var initial_distance: float = attacker.position.distance_to(defender.position)
	var closest_distance: float = initial_distance
	for frame in 300:
		await _frames(1)
		closest_distance = minf(closest_distance, attacker.position.distance_to(defender.position))
	# Successful hits push the defender away again. Measure whether AI closes
	# a meaningful amount during combat, rather than requiring the final frame
	# to be closer after a launcher, beam, or knockback has moved its target.
	_expect(closest_distance < initial_distance - 2.0, "AI closes at least two metres toward its opponent during real combat")
	_expect(defender.hp < before, "AI chooses and connects attacks that damage its opponent")
	_reset(12.0)
	await _frames(2)
	ai.training = true
	ai.set_physics_process(true)
	before = defender.hp
	var start_position: Vector3 = attacker.position
	await _frames(100)
	_expect(is_equal_approx(defender.hp, before), "training AI does not attack or damage the player")
	_expect(attacker.position.distance_to(start_position) < 0.05 and attacker.state == "idle", "training AI remains stationary and passive")

func _test_fair_opening_and_pursuit() -> void:
	_reset()
	attacker.energy = 100.0
	attacker.combat_locked = true
	var before: float = defender.hp
	for action in ["attack","heavy","blast","sphere","homing","special","nova","dash","dodge","transform"]:
		_expect(not attacker.request_action(action),"countdown blocks "+action+" without buffering it")
	_expect(not attacker.combo.queued and attacker.state=="idle","countdown never queues a combo or changes state")
	defender.combat_locked = true
	_expect(not defender.receive_hit(500.0,Vector3.ZERO,attacker,"ultimate") and defender.hp==before,"countdown rejects even direct damage delivery")
	attacker.intent = {"move":Vector3.RIGHT,"charge":true,"guard":true}
	await _frames(8)
	_expect(attacker.global_position.x>0.2 and attacker.state=="idle","countdown permits movement while suppressing guard and charge")
	_reset(22.0)
	ai.difficulty = 2
	ai.rng.seed = 12011
	ai.set_physics_process(true)
	attacker.combat_locked = true
	before = defender.hp
	await _frames(180)
	_expect(ai.active_combat_time==0.0 and defender.hp==before,"AI opening clock does not advance during the countdown")
	attacker.combat_locked = false
	await _frames(30)
	_expect(attacker.state not in ["light","heavy","blast","beam","ultimate"] and defender.hp==before,"AI gives a human movement grace period after FIGHT")
	var early_ranged: bool = false
	var first_attack: String = ""
	for frame in 280:
		await _frames(1)
		if attacker.state in ["light","heavy","blast","beam","ultimate"] and first_attack=="":
			first_attack = attacker.state
		if ai.active_combat_time<3.0 and attacker.state in ["blast","beam","ultimate"]:
			early_ranged = true
	_expect(not early_ranged,"AI cannot open with ranged or beam spam in its first three active seconds")
	_expect(first_attack in ["light","heavy"],"AI commits to melee as its first offensive action")
	_expect(attacker.state not in ["beam","ultimate"] and ai.active_combat_time<6.0,"AI cannot channel a powerful beam before the six-second gate")
	_reset(8.0)
	defender.position.y = 8.0
	attacker.intent = {"move":Vector3.ZERO}
	_expect(attacker.request_action("dash") and attacker.flying and attacker.dash_direction.y>0.4,"lock-on pursuit dash follows a launched opponent into the air")
	await _frames(5)
	_expect(attacker.global_position.y>0.5,"aerial pursuit changes physical altitude rather than only the pose")


func _run() -> void:
	Engine.max_fps = 0
	_create_world()
	await _frames(3)
	await _test_melee_and_combo()
	await _test_guard_and_parry()
	await _test_skeletal_contact_alignment()
	await _test_dodge_and_launcher()
	await _test_energy_and_forms()
	await _test_projectiles_and_beams()
	await _test_ko()
	await _test_ai_and_training()
	await _test_fair_opening_and_pursuit()
	stage.queue_free()
	await process_frame
	print("COMBAT TESTS: ", checks - failures.size(), "/", checks, " passed")
	if not failures.is_empty():
		printerr("FAILED CHECKS: ", "; ".join(failures))
	quit(0 if failures.is_empty() else 1)
