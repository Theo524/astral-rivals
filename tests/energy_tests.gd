extends SceneTree
## Reproducible deterministic smoke tests for the independent pooled energy layer.
## Run: godot --headless --audio-driver Dummy --path . --script tests/energy_tests.gd
const Projectiles = preload("res://scripts/combat/projectile_system.gd")
const Audio = preload("res://scripts/effects/audio_manager.gd")
const Camera = preload("res://scripts/world/lock_on_camera.gd")
const ScreenEffects = preload("res://scripts/effects/screen_effects.gd")

class Dummy:
	extends Node3D
	var hp := 5000.0
	var target: Node
	var color := Color.CYAN
	var form := 0
	var state := "idle"
	var data := {"id": "kaizen", "energy_rate": 1.0}
	var hits := 0
	func damage_multiplier() -> float:
		return 1.0
	func receive_hit(amount: float, _knockback: Vector3, _source: Node, _kind: String) -> bool:
		hp -= amount
		hits += 1
		return true

var failures := 0
var checks := 0
var stage: Node3D
var attacker: Dummy
var defender: Dummy
var projectiles: Node

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: ", message)

func _reset(distance: float = 8.0) -> void:
	for item in projectiles.projectiles:
		projectiles._retire(item)
	for item in projectiles.beams:
		projectiles._retire(item)
	for item in projectiles.effects:
		projectiles._retire(item)
	attacker.position = Vector3.ZERO
	defender.position = Vector3(0.0, 0.0, -distance)
	attacker.hp = 5000.0
	defender.hp = 5000.0
	attacker.state = "idle"
	attacker.hits = 0
	defender.hits = 0
	attacker.data.energy_rate = 1.0

func _step(frames: int = 1, delta: float = 1.0 / 60.0) -> void:
	for i in frames:
		projectiles._physics_process(delta)

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	attacker = Dummy.new()
	defender = Dummy.new()
	stage.add_child(attacker)
	stage.add_child(defender)
	attacker.target = defender
	defender.target = attacker
	projectiles = Projectiles.new()
	projectiles.quality = 2
	stage.add_child(projectiles)
	projectiles.set_physics_process(false)
	projectiles.fighters = [attacker, defender]

	_reset()
	projectiles.fire(attacker, "blast")
	_step(1, 0.25)
	_expect(defender.hits == 1 and is_equal_approx(defender.hp, 4970.0), "swept blast connects across a large timestep for exactly 30 damage")
	_expect(projectiles.active_count() == 0, "spent blast immediately returns to its pool")

	_reset()
	projectiles.fire(attacker, "sphere", 1.5)
	_step(30)
	_expect(is_equal_approx(defender.hp, 4857.5), "charged sphere scales 95 damage by charge 1.5")

	_reset(12.0)
	projectiles.fire(attacker, "homing")
	defender.position.x = 3.0
	_step(70)
	_expect(defender.hits == 1, "homing blast turns to hit a target that moved after firing")

	_reset()
	projectiles.fire(attacker, "nova")
	_expect(is_equal_approx(defender.hp, 4890.0), "nova applies 110 damage inside its nine-unit area")
	_reset(12.0)
	projectiles.fire(attacker, "nova")
	_expect(defender.hits == 0, "nova leaves targets outside its area unharmed")

	_reset()
	attacker.data.energy_rate = 1.25
	projectiles.fire(attacker, "blast")
	_step(1, 0.25)
	_expect(is_equal_approx(defender.hp, 4962.5), "Akira data-driven energy multiplier amplifies blast damage by 25 percent")

	_reset(20.0)
	projectiles.fire(attacker, "blast")
	projectiles.fire(defender, "blast")
	_step(35)
	_expect(attacker.hits == 0 and defender.hits == 0 and projectiles.active_count() == 0, "opposing swept projectiles clash and both return to their pools")

	_reset(16.0)
	projectiles.fire(attacker, "beam")
	_step(25)
	_expect(defender.hits >= 3 and defender.hp <= 4946.0, "beam persists and deals repeated 18-damage ticks")
	_step(80)
	_expect(projectiles.active_count() == 0, "expired beam returns to its fixed pool")

	_reset(16.0)
	projectiles.fire(attacker, "beam")
	attacker.state = "hurt"
	_step()
	_expect(projectiles.active_count() == 0 and defender.hits == 0, "hit stun interrupts a channelled beam before its damage tick")
	_reset(16.0)
	projectiles.fire(attacker, "beam")
	attacker.hp = 0.0
	_step()
	_expect(projectiles.active_count() == 0, "defeating a beam owner stops its channel")

	_reset(16.0)
	projectiles.fire(attacker, "beam")
	projectiles.fire(defender, "beam")
	_step(30)
	_expect(attacker.hits == 0 and defender.hits == 0, "opposing beams meet and protect both shooters during the clash")
	var clipped := true
	for beam in projectiles.beams:
		if beam.active:
			clipped = clipped and beam.shell.scale.y < 9.0
	_expect(clipped, "beam clash geometry ends at the meeting point instead of passing through")

	_reset(1000.0)
	for i in 200:
		projectiles.fire(attacker, "blast")
		projectiles.fire(attacker, "beam")
		projectiles.burst(Vector3.ZERO, Color.CYAN)
	_expect(projectiles.projectiles.size() == 36 and projectiles.beams.size() == 4 and projectiles.effects.size() == 48, "stress firing never grows the fixed projectile, beam, or effects pools")
	_expect(projectiles.active_count() == 40, "overflow requests remain bounded at 36 projectiles and four beams")
	_step(240)
	_expect(projectiles.active_count() == 0, "all pooled energy objects expire after stress firing")

	var saver := Projectiles.new()
	saver.quality = 0
	stage.add_child(saver)
	saver.set_physics_process(false)
	_expect(saver.projectiles.size() == 12 and saver.beams.size() == 2 and saver.effects.size() == 16,"low quality creates smaller fixed pools before allocation")
	_expect(saver.get_child_count() == 30,"low quality energy layer creates only thirty pooled roots")
	saver.queue_free()

	var camera := Camera.new()
	stage.add_child(camera)
	camera.player = attacker
	camera.enemy = defender
	_reset(10.0)
	camera.snap()
	var near_distance: float = camera.global_position.distance_to(attacker.global_position)
	defender.position = Vector3(0.0,18.0,-30.0)
	camera.snap()
	_expect(camera.global_position.is_finite() and camera.fov >= 60.0,"camera remains finite during a tall aerial separation")
	_expect(camera.global_position.distance_to(attacker.global_position) > near_distance,"camera widens framing during aerial separation")
	_expect(camera.is_position_in_frustum(attacker.global_position+Vector3.UP) and camera.is_position_in_frustum(defender.global_position+Vector3.UP),"aerial framing keeps both fighter centers inside the camera frustum")
	var base_position: Vector3 = camera.global_position
	camera.kick(50.0)
	camera._update_camera(1.0/60.0,false)
	_expect(camera._shake <= 0.22 and camera._base_position.is_equal_approx(base_position),"camera shake is bounded and never feeds back into base movement")
	var screen := ScreenEffects.new()
	stage.add_child(screen)
	screen.set_quality(0)
	screen.impact(3.0,Color.CYAN)
	screen.pursuit(40.0)
	_expect(screen._flash <= 1.7 and screen.quality == 0,"screen accents clamp flash strength and support low quality")
	for i in 180:
		screen._process(1.0/60.0)
	_expect(screen._flash == 0.0 and screen._speed < 0.01,"temporary screen accents fade and stop redrawing")

	var audio = Audio.new()
	stage.add_child(audio)
	_expect(audio.sounds.size() == 14, "all 14 original synthesized sound cues build successfully")
	audio.play("hit")
	audio.play("ultimate")
	audio.set_volume(0.1)
	audio.set_suspended(true)
	_expect(audio.music.stream_paused,"audio suspends for app background without reallocating resources")
	audio.set_suspended(false)
	audio.set_music_enabled(false)
	audio.queue_free()
	await process_frame
	await process_frame
	stage.queue_free()
	await process_frame
	await process_frame
	print("ENERGY_TESTS: ", checks - failures, "/", checks, " checks passed")
	quit(1 if failures > 0 else 0)
