extends SceneTree
## End-to-end lifecycle checks against the real main scene and UI signals.
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/game_tests.gd
var game: Node3D
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ",message)
	else:
		failures.append(message)
		printerr("FAIL: ",message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _start(mode: String = "versus", character: int = 0, arena_index: int = 0, difficulty: int = 0) -> void:
	game.ui.settings.show_touch = true
	game.ui.start_match.emit({"player":character,"enemy":(character+1)%3,"arena":arena_index,"difficulty":difficulty,"mode":mode})
	await _frames(190)

func _countdown_and_mobile_lifecycle() -> void:
	game.ui.settings.show_touch = true
	game.ui.start_match.emit({"player":0,"enemy":1,"arena":1,"difficulty":2,"mode":"versus"})
	await _frames(3)
	_expect(game.countdown_remaining>2.8 and game.player.combat_locked and game.enemy.combat_locked,"a real round starts with both fighters protected by a three-second countdown")
	var before_hp: float = game.player.hp
	_expect(not game.enemy.request_action("special") and not game.player.request_action("attack"),"neither player nor AI can launch an attack during countdown")
	var origin: Vector3 = game.player.position
	Input.action_press("forward")
	await _frames(12)
	Input.action_release("forward")
	_expect(game.player.position.distance_to(origin)>0.3 and game.player.hp==before_hp,"countdown lets the player establish movement without receiving damage")
	var before_countdown: float = game.countdown_remaining
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(20)
	_expect(paused and is_equal_approx(game.countdown_remaining,before_countdown) and not game.ui.touch.enabled,"app focus loss pauses the countdown and releases touch input")
	game.ui.resume_requested.emit()
	await _frames(200)
	_expect(not paused and not game.player.combat_locked and not game.enemy.combat_locked and game.countdown_remaining==0.0,"resume completes countdown and opens combat through the real lifecycle")
	_expect(game.enemy.state not in ["beam","ultimate"] and game.player.hp==before_hp,"hard AI cannot open with a beam immediately after FIGHT")
	await _start("training")
	_expect(game.ai.training,"training dummy starts passive")
	game.ui.settings_changed.emit({"training_attack":true})
	await _frames(2)
	_expect(not game.ai.training and game.ai.active_combat_time<0.1,"training attack setting enables AI with a fresh fair opening")
	game.ui.settings_changed.emit({"training_attack":false})
	await _frames(2)
	_expect(game.ai.training,"training attack setting returns the dummy to passive practice")
	_expect(FileAccess.file_exists("user://logs/session.log"),"persistent bounded diagnostic session log is created")

func _disable_ai() -> void:
	game.ai.set_physics_process(false)
	game.enemy.intent = {"move":Vector3.ZERO}

func _position_for_attack() -> void:
	game.player.position = Vector3.ZERO
	game.enemy.position = Vector3(0.0,0.0,-2.2)
	game.player.velocity = Vector3.ZERO
	game.enemy.velocity = Vector3.ZERO
	game.player.rotation = Vector3.ZERO
	game.enemy.rotation = Vector3(0.0,PI,0.0)
	game.player.invulnerability = 0.0
	game.enemy.invulnerability = 0.0

func _win_with_real_attack() -> void:
	_disable_ai()
	# Continuation deliberately starts a new protected countdown. Exercise that
	# lifecycle rather than injecting a hit through its protection.
	while game.countdown_remaining > 0.0:
		await _frames(1)
	_position_for_attack()
	game.enemy.hp = 20.0
	game.player._change_state("idle")
	game.player.request_action("attack")
	for i in 45:
		await _frames(1)
		if not game.match_active:
			break

func _has_result_button(fragment: String) -> bool:
	if game.ui.overlay == null:
		return false
	for button in game.ui.overlay.find_children("*","Button",true,false):
		if fragment in button.text:
			return true
	return false

func _selection_matrix() -> void:
	var names := ["KAIZEN","RYUZEN","AKIRA"]
	for character in 3:
		for arena_index in 3:
			await _start("versus",character,arena_index)
			_disable_ai()
			_expect(game.player.data.name == names[character] and game.enemy.data.name == names[(character+1)%3],"selection creates correct player and enemy (%d/%d)" % [character,arena_index])
			_expect(game.arena.current_index == arena_index and game.match_active and game.ui.mode == "battle","selection starts the chosen arena (%d/%d)" % [character,arena_index])
			_expect(game.projectiles.fighters == [game.player,game.enemy] and game.player.target == game.enemy and game.enemy.target == game.player,"selection wires shared combat targets and projectile opponents (%d/%d)" % [character,arena_index])

func _hud_and_pause() -> void:
	await _start()
	_disable_ai()
	game.player.hp = 777.0
	game.player.energy = 42.0
	game.player.form = 1
	game.player.combo.hits = 3
	game.player.combo.hit_timeout = 2.0
	await _frames(3)
	_expect(game.ui.player_hp.value == 777.0 and game.ui.player_energy.value >= 42.0,"HUD displays live fighter health and energy")
	_expect(game.ui.player_form.text == "AWAKENED" and "03" in game.ui.combo_label.text,"HUD displays transformation and combo count")
	game.ui.pause_requested.emit()
	var before: float = game.elapsed
	var position_before: Vector3 = game.player.position
	await _frames(20)
	_expect(paused and game.ui.mode == "pause" and not game.ui.touch.enabled,"pause signal suspends the match and touchscreen inputs")
	_expect(is_equal_approx(game.elapsed,before) and game.player.position.is_equal_approx(position_before),"simulation time and fighter position remain unchanged while paused")
	game.ui.resume_requested.emit()
	await _frames(5)
	_expect(not paused and game.ui.mode == "battle" and game.elapsed > before and game.ui.touch.enabled,"resume signal restores match simulation and inputs")
	Input.action_press("pause")
	await _frames(1)
	Input.action_release("pause")
	await _frames(2)
	_expect(paused and game.ui.mode == "pause","pause input action opens the pause menu")
	Input.action_press("pause")
	await _frames(1)
	Input.action_release("pause")
	await _frames(2)
	_expect(not paused and game.ui.mode == "battle","pause input action also resumes a paused match")
	if paused:
		game.ui.resume_requested.emit()

func _settings_and_menu() -> void:
	game.ui.settings_changed.emit({"quality":0,"fps":30,"shake":false,"volume":0.25,"sensitivity":1.25})
	await _frames(2)
	_expect(Engine.max_fps == 30 and is_equal_approx(game.get_viewport().scaling_3d_scale,0.7),"settings apply 30 FPS cap and reduced 3D resolution")
	_expect(not game.camera.shake_enabled and game.projectiles.quality == 0 and is_equal_approx(game.audio.volume,0.25),"settings reach camera, effects and audio systems")
	_expect(is_equal_approx(game.camera.sensitivity,1.25),"camera sensitivity settings reach the active camera")
	game.ui.settings_changed.emit({"quality":1,"fps":60,"shake":true,"volume":0.0,"sensitivity":1.0})
	var old_world: Node = game.world
	game.ui.menu_requested.emit()
	await _frames(3)
	_expect(not game.match_active and game.ui.mode == "menu" and not game.ui.touch.enabled,"return-to-menu exits battle and disables touch actions")
	_expect(not is_instance_valid(old_world),"return-to-menu releases the old match world")

func _victory_rematch_and_ai_defeat() -> void:
	await _start()
	var wins_before: int = game.wins
	await _win_with_real_attack()
	_expect(game.enemy.hp == 0.0 and not game.match_active and game.ui.mode == "result","a real melee KO ends versus mode with a result screen")
	_expect(game.wins == wins_before+1 and _has_result_button("FIGHT AGAIN"),"victory records progression and provides a rematch action")
	game.ui.rematch_requested.emit()
	await _frames(3)
	_expect(game.match_active and game.player.hp == game.player.max_hp and game.enemy.hp == game.enemy.max_hp and game.round_index == 1,"rematch restores both fighters and begins a fresh first round")
	# This is an actual AI fight, not an injected receive_hit: a vulnerable player
	# stands still while the original AI must approach and land a damaging action.
	game.player.hp = 22.0
	game.player.energy = 0.0
	var enemy_start: Vector3 = game.enemy.position
	for i in 1500:
		await _frames(1)
		if not game.match_active:
			break
	_expect(not game.match_active and game.player.hp == 0.0,"an AI opponent pursues and defeats an idle player through real combat")
	_expect(game.enemy.position.distance_to(enemy_start)>1.0 and game.wins == wins_before+1,"AI traveled from spawn and a defeat does not award a win")
	_expect(game.ui.mode == "result" and _has_result_button("FIGHT AGAIN"),"defeat presents a functional retry result")

func _training_reset() -> void:
	await _start("training")
	_expect(game.ai.training,"training mode configures a passive AI")
	var hp_before: float = game.player.hp
	await _frames(120)
	_expect(game.player.hp == hp_before,"training opponent does not damage the player")
	_position_for_attack()
	game.enemy.hp = 20.0
	game.player.request_action("attack")
	var old_fighter: Node = game.enemy
	for i in 210:
		await _frames(1)
		if not is_instance_valid(old_fighter):
			break
	_expect(not is_instance_valid(old_fighter) and game.match_active and game.ui.mode == "battle","training KO resets the practice world instead of ending the session")
	_expect(game.enemy.hp == game.enemy.max_hp and game.player.hp == game.player.max_hp,"training reset restores both fighters to full health")

func _full_health_ai_match() -> void:
	await _start("versus",0,1,2)
	var initial_hp: float = game.player.hp
	for i in 9000:
		await _frames(1)
		if not game.match_active:
			break
	_expect(initial_hp == game.player.max_hp and game.player.hp == 0.0 and not game.match_active,"AI completes a full-health match through repeated melee and energy damage")
	_expect(game.ui.mode == "result" and not game.enemy.hp <= 0.0,"full-health combat recovers into a stable defeat result")

func _arcade() -> void:
	await _start("arcade")
	for round_number in range(1,4):
		game.player.hp = 400.0
		game.player.energy = 50.0
		game.player.form = 1
		await _win_with_real_attack()
		_expect(game.round_index == round_number and game.ui.mode == "result","arcade round %d produces a KO result" % round_number)
		if round_number < 3:
			_expect(_has_result_button("NEXT CHALLENGER"),"arcade round %d offers the next challenger" % round_number)
			var expected_hp: float = 400.0+game.player.max_hp*0.22
			game.ui.continue_requested.emit()
			await _frames(3)
			_disable_ai()
			_expect(game.round_index == round_number+1 and game.match_active,"arcade continuation advances to round %d" % (round_number+1))
			_expect(is_equal_approx(game.player.hp,expected_hp) and game.player.form == 1 and game.player.energy >= 50.0,"arcade continuation carries health with recovery, energy and form")
		else:
			_expect(not _has_result_button("NEXT CHALLENGER") and _has_result_button("FIGHT AGAIN"),"arcade finishes after its third opponent")

func _survival() -> void:
	await _start("survival")
	for round_number in range(1,4):
		_expect(game.round_index == round_number and is_equal_approx(game.enemy.max_hp,float(game.enemy.data.hp)*(1.0+0.08*(round_number-1))),"survival round %d increases enemy health by its round multiplier" % round_number)
		await _win_with_real_attack()
		_expect(_has_result_button("NEXT CHALLENGER"),"survival round %d allows continuation" % round_number)
		game.ui.continue_requested.emit()
		await _frames(3)
		_disable_ai()
	_expect(game.round_index == 4 and game.ai.difficulty == 1,"survival increases AI difficulty after three cleared rounds")
	_expect(game.best_survival >= 3,"survival records the highest cleared round")
	var file := ConfigFile.new()
	_expect(file.load("user://progress.cfg") == OK and int(file.get_value("records","wins",0)) == game.wins and int(file.get_value("records","survival",0)) == game.best_survival,"wins and survival record are persisted to the user save")

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(3)
	game.audio.set_volume(0.0)
	_expect(game.ui.mode == "menu" and not game.match_active,"normal main-scene launch opens the animated menu")
	await _countdown_and_mobile_lifecycle()
	await _selection_matrix()
	await _hud_and_pause()
	await _settings_and_menu()
	await _victory_rematch_and_ai_defeat()
	await _full_health_ai_match()
	await _training_reset()
	await _arcade()
	await _survival()
	paused = false
	Engine.time_scale = 1.0
	game.queue_free()
	await _frames(3)
	print("GAME TESTS: %d/%d passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
