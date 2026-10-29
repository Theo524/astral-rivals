extends Node3D
## Match lifecycle, progression, and system wiring; no combat logic lives in UI.
const CharacterData = preload("res://scripts/data/character_data.gd")
const Fighter = preload("res://scripts/combat/fighter.gd")
const Arena = preload("res://scripts/world/arena_manager.gd")
const Projectiles = preload("res://scripts/combat/projectile_system.gd")
const Audio = preload("res://scripts/effects/audio_manager.gd")
const Camera = preload("res://scripts/world/lock_on_camera.gd")
const PlayerInput = preload("res://scripts/input/player_controller.gd")
const AI = preload("res://scripts/combat/enemy_ai.gd")
const UI = preload("res://scripts/ui/game_ui.gd")
const ScreenEffects = preload("res://scripts/effects/screen_effects.gd")
const SessionLog = preload("res://scripts/diagnostics/session_log.gd")

var ui: CanvasLayer
var audio: Node
var screen_effects: CanvasLayer
var diagnostics: Node
var world: Node3D
var arena: Node3D
var projectiles: Node3D
var camera: Camera3D
var player: CharacterBody3D
var enemy: CharacterBody3D
var controller: Node
var ai: Node
var config: Dictionary = {}
var match_active: bool = false
var elapsed: float = 0.0
var round_index: int = 1
var slow_remaining: float = 0.0
var notice: String = ""
var notice_remaining: float = 0.0
var training_reset: float = 0.0
var wins: int = 0
var best_survival: int = 0
var countdown_remaining: float = 0.0
var fight_label_remaining: float = 0.0
var settings: Dictionary = {"quality":1,"fps":60,"shake":true,"volume":0.7,"sensitivity":1.0,"fullscreen":false,"resolution":0,"training_attack":false}
var _display_settings: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure_input()
	_load_progress()
	get_tree().auto_accept_quit = false
	diagnostics = SessionLog.new()
	add_child(diagnostics)
	audio = Audio.new()
	add_child(audio)
	screen_effects = ScreenEffects.new()
	add_child(screen_effects)
	ui = UI.new()
	ui.start_match.connect(_new_match)
	ui.rematch_requested.connect(_restart)
	ui.menu_requested.connect(_menu)
	ui.pause_requested.connect(_pause)
	ui.resume_requested.connect(_resume)
	ui.continue_requested.connect(_continue_round)
	ui.settings_changed.connect(_apply_settings)
	add_child(ui)
	ui.set_records(wins,best_survival)
	# Respect loaded/mobile defaults before a CLI quickstart allocates its pools.
	_apply_settings(ui.settings)
	# Convenient reproducible launch for screenshots/manual QA; normal launch is menu.
	for arg in OS.get_cmdline_user_args():
		if arg == "--quickstart":
			_new_match({"player":0,"enemy":1,"arena":1,"difficulty":1,"mode":"versus"})
		elif arg == "--training":
			_new_match({"player":0,"enemy":1,"arena":0,"difficulty":0,"mode":"training"})

func _configure_input() -> void:
	var keys: Dictionary = {"left":[KEY_A,KEY_LEFT],"right":[KEY_D,KEY_RIGHT],"forward":[KEY_W,KEY_UP],"back":[KEY_S,KEY_DOWN],"attack":[KEY_J],"heavy":[KEY_K],"blast":[KEY_L],"guard":[KEY_Q],"dodge":[KEY_X],"dash":[KEY_SHIFT],"ascend":[KEY_SPACE],"descend":[KEY_CTRL],"charge":[KEY_C],"special":[KEY_E],"transform":[KEY_T],"lock":[KEY_TAB],"sphere":[KEY_V],"homing":[KEY_H],"nova":[KEY_O],"ultimate":[KEY_R],"pause":[KEY_ESCAPE,KEY_P]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action,0.18)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action,event)
	var buttons: Dictionary = {"attack":JOY_BUTTON_X,"heavy":JOY_BUTTON_Y,"blast":JOY_BUTTON_B,"dodge":JOY_BUTTON_A,"guard":JOY_BUTTON_LEFT_SHOULDER,"dash":JOY_BUTTON_RIGHT_SHOULDER,"charge":JOY_BUTTON_DPAD_DOWN,"transform":JOY_BUTTON_DPAD_UP,"ascend":JOY_BUTTON_DPAD_RIGHT,"descend":JOY_BUTTON_DPAD_LEFT,"lock":JOY_BUTTON_RIGHT_STICK,"pause":JOY_BUTTON_START,"special":JOY_BUTTON_LEFT_STICK}
	for action in buttons:
		var event := InputEventJoypadButton.new()
		event.button_index = buttons[action]
		InputMap.action_add_event(action,event)
	for mapping in [["left",JOY_AXIS_LEFT_X,-1.0],["right",JOY_AXIS_LEFT_X,1.0],["forward",JOY_AXIS_LEFT_Y,-1.0],["back",JOY_AXIS_LEFT_Y,1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = mapping[1]
		event.axis_value = mapping[2]
		InputMap.action_add_event(mapping[0],event)
	# Trigger axes are normalized by Godot and can be held simultaneously.
	for mapping in [["ascend",JOY_AXIS_TRIGGER_RIGHT],["descend",JOY_AXIS_TRIGGER_LEFT]]:
		var event := InputEventJoypadMotion.new()
		event.axis = mapping[1]
		event.axis_value = 1.0
		InputMap.action_add_event(mapping[0],event)

func _new_match(next: Dictionary) -> void:
	config = next.duplicate()
	round_index = 1
	_begin_round()

func _begin_round(health_carry: float = -1.0, energy_carry: float = 60.0, form_carry: int = 0) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	slow_remaining = 0.0
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = Node3D.new()
	world.name = "Match"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	arena = Arena.new()
	world.add_child(arena)
	arena.build(int(config.get("arena",0)),int(settings.quality))
	projectiles = Projectiles.new()
	projectiles.quality = int(settings.quality)
	world.add_child(projectiles)
	projectiles.arena = arena
	projectiles.impact.connect(_energy_impact)
	projectiles.sound_requested.connect(audio.play)
	var roster: Array[Dictionary] = CharacterData.roster()
	player = Fighter.new()
	world.add_child(player)
	player.setup(roster[int(config.get("player",0))],true)
	player.position = Vector3(-5,0,0)
	player.rotation.y = -PI/2.0
	enemy = Fighter.new()
	world.add_child(enemy)
	enemy.setup(roster[int(config.get("enemy",1))],false)
	enemy.position = Vector3(5,0,0)
	enemy.rotation.y = PI/2.0
	if config.get("mode", "versus") == "survival":
		enemy.max_hp *= 1.0 + minf(float(round_index-1)*0.08,0.8)
		enemy.hp = enemy.max_hp
	if health_carry > 0.0:
		player.hp = minf(player.max_hp,health_carry)
	player.energy = energy_carry
	player.form = form_carry
	player.visual.set_form(form_carry)
	for fighter in [player,enemy]:
		fighter.combat_locked = true
		fighter.target = enemy if fighter == player else player
		fighter.game = self
		fighter.projectiles = projectiles
		fighter.feedback.connect(_feedback.bind(fighter))
		fighter.knocked_out.connect(_knockout)
	projectiles.fighters = [player,enemy]
	camera = Camera.new()
	world.add_child(camera)
	camera.player = player
	camera.enemy = enemy
	camera.shake_enabled = bool(settings.shake)
	camera.sensitivity = float(settings.sensitivity)
	camera.snap()
	controller = PlayerInput.new()
	controller.fighter = player
	controller.camera = camera
	controller.touch = ui.touch
	world.add_child(controller)
	ai = AI.new()
	ai.fighter = enemy
	ai.target = player
	ai.difficulty = mini(2,int(config.get("difficulty",1))+(round_index-1)/3)
	ai.training = config.get("mode", "versus") == "training" and not bool(settings.training_attack)
	world.add_child(ai)
	match_active = true
	training_reset = 0.0
	elapsed = 0.0
	countdown_remaining = 3.0
	fight_label_remaining = 0.0
	ui.show_battle(config)
	ui.set_countdown("3")
	_apply_settings(settings)
	show_notice("MOVE TO GET READY  •  ATTACKS UNLOCK AT FIGHT",3.0)
	diagnostics.event("round_start",{"mode":config.get("mode","versus"),"player":player.data.id,"enemy":enemy.data.id,"arena":config.get("arena",0),"quality":settings.quality,"round":round_index})
	audio.play("menu")

func _process(delta: float) -> void:
	var real_delta: float = delta/maxf(Engine.time_scale,0.1)
	if slow_remaining > 0.0:
		slow_remaining -= real_delta
		if slow_remaining <= 0.0:
			Engine.time_scale = 1.0
	if match_active and Input.is_action_just_pressed("pause"):
		if get_tree().paused:
			_resume()
		else:
			_pause()
		return
	if not match_active or get_tree().paused:
		return
	if countdown_remaining > 0.0:
		countdown_remaining = maxf(0.0,countdown_remaining-delta)
		if countdown_remaining > 0.0:
			ui.set_countdown(str(int(ceil(countdown_remaining))))
		else:
			player.combat_locked = false
			enemy.combat_locked = false
			ai.reset_opening()
			ui.touch.reset()
			ui.set_countdown("FIGHT")
			fight_label_remaining = 0.75
			show_notice("TRAINING  /  DUMMY PASSIVE • ENABLE ATTACKS IN SETTINGS" if ai.training else "MELEE FIRST  •  CHARGE ENERGY TO POWER UP",3.0)
			diagnostics.event("fight_unlocked")
		ui.update_hud(player,enemy,0,0.0,notice)
		return
	if fight_label_remaining > 0.0:
		fight_label_remaining = maxf(0.0,fight_label_remaining-delta)
		if fight_label_remaining <= 0.0:
			ui.set_countdown("")
	elapsed += delta
	screen_effects.pursuit(player.velocity.length())
	notice_remaining = maxf(0.0,notice_remaining-delta)
	if training_reset > 0.0:
		training_reset -= delta
		if training_reset <= 0.0:
			_begin_round()
			return
	if is_instance_valid(arena):
		arena.update(delta)
	var status: String = notice if notice_remaining > 0.0 else ("LOCKED ON" if player.locked else "FREE CAMERA  •  TAB TO LOCK")
	ui.update_hud(player,enemy,player.combo.hits,elapsed,status)

func show_notice(message: String, duration: float = 2.0) -> void:
	notice = message
	notice_remaining = duration

func _feedback(cue: String, position_at: Vector3, strength: float, fighter: Node) -> void:
	if not is_instance_valid(projectiles):
		return
	var sound: String = {"impact":"heavy" if strength > 0.7 else "hit","guard_break":"explosion","swing":"dash","beam_charge":"charge","evade":"dodge"}.get(cue,cue)
	audio.play(sound)
	if cue != "swing":
		projectiles.burst(position_at,Color.WHITE if cue == "parry" else fighter.color,maxf(strength,0.3))
	camera.kick(strength)
	if cue in ["impact","guard_break","transform","evade"]:
		screen_effects.impact(strength,fighter.color)
	if cue == "impact" and strength >= 0.7:
		Engine.time_scale = 0.35
		slow_remaining = 0.085
		arena.impact(position_at,2.4,strength*55.0)
		camera.cinematic(0.26,"impact")
	elif cue == "transform":
		camera.cinematic(1.3,"transform")
		show_notice("%s  /  %s" % [fighter.data.name,fighter.data.form_names[fighter.form]],2.0)
	elif cue == "beam_charge":
		camera.cinematic(2.5 if fighter.state == "ultimate" else 1.3)
		show_notice(fighter.data.ultimate if fighter.state == "ultimate" else fighter.data.special,1.8)
	elif cue == "guard_break":
		show_notice("GUARD BREAK",1.0)
	elif cue == "parry":
		show_notice("PERFECT PARRY  •  COUNTER READY",1.0)
	elif cue == "evade":
		show_notice("PERFECT EVADE  •  COUNTER READY",1.0)

func _energy_impact(_position_at: Vector3, power: float) -> void:
	if is_instance_valid(camera):
		camera.kick(power)
		screen_effects.impact(power,Color("b9e7ff"))

func _knockout(fighter: Node) -> void:
	if not match_active:
		return
	if config.get("mode", "versus") == "training":
		training_reset = 1.5
		show_notice("KNOCKOUT  /  RESETTING PRACTICE",1.5)
		return
	match_active = false
	Engine.time_scale = 1.0
	player.enabled = false
	enemy.enabled = false
	controller.enabled = false
	ai.set_physics_process(false)
	var won: bool = fighter == enemy
	player.visual.set_presentation("victory" if won else "defeat")
	enemy.visual.set_presentation("defeat" if won else "victory")
	diagnostics.event("knockout",{"winner":player.data.id if won else enemy.data.id,"seconds":elapsed,"round":round_index})
	if won:
		wins += 1
		if config.mode == "survival":
			best_survival = maxi(best_survival,round_index)
	_save_progress()
	ui.set_records(wins,best_survival)
	var can_continue: bool = won and (config.mode == "survival" or (config.mode == "arcade" and round_index < 3))
	var subtitle: String = "%s • %d wins recorded" % [player.data.name,wins] if won else "Recover, charge your energy, and return stronger."
	if config.mode in ["arcade","survival"]:
		subtitle = "%s  /  ROUND %d%s" % [str(config.mode).to_upper(),round_index," • NEXT CHALLENGER READY" if can_continue else ""]
	ui.show_result(won,subtitle,can_continue)
	audio.play("win" if won else "lose")

func _continue_round() -> void:
	var carry_hp: float = minf(player.max_hp,player.hp+player.max_hp*0.22)
	var carry_energy: float = maxf(35.0,player.energy)
	var carry_form: int = player.form
	round_index += 1
	config.enemy = (int(config.enemy)+1)%3
	config.arena = (int(config.arena)+1)%3
	_begin_round(carry_hp,carry_energy,carry_form)

func _restart() -> void:
	round_index = 1
	_begin_round()

func _menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	match_active = false
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	ui.show_menu()
	ui.set_countdown("")
	ui.set_records(wins,best_survival)
	screen_effects.pursuit(0.0)
	diagnostics.event("menu")
	audio.play("menu")

func _pause() -> void:
	if match_active:
		get_tree().paused = true
		Engine.time_scale = 1.0
		slow_remaining = 0.0
		ui.show_pause()
		diagnostics.event("pause")

func _resume() -> void:
	get_tree().paused = false
	ui.hide_pause()
	audio.set_suspended(false)
	diagnostics.event("resume")

func _apply_settings(next: Dictionary) -> void:
	settings.merge(next,true)
	Engine.max_fps = int(settings.fps)
	get_viewport().scaling_3d_scale = [0.7,0.85,1.0][int(settings.quality)]
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if int(settings.quality) == 0 else Viewport.MSAA_2X
	audio.set_volume(float(settings.volume))
	screen_effects.set_quality(int(settings.quality))
	var display_key: String = str(settings.fullscreen)+str(settings.resolution)
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless" and display_key != _display_settings:
		_display_settings = display_key
		var sizes: Array[Vector2i] = [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED)
		if not bool(settings.fullscreen):
			DisplayServer.window_set_size(sizes[clampi(int(settings.resolution),0,2)])
	if is_instance_valid(camera):
		camera.shake_enabled = bool(settings.shake)
		camera.sensitivity = float(settings.sensitivity)
	if is_instance_valid(projectiles):
		projectiles.quality = int(settings.quality)
	for fighter in [player,enemy]:
		if is_instance_valid(fighter):
			fighter.visual.set_quality(int(settings.quality))
	if is_instance_valid(ai):
		var passive: bool = config.get("mode","versus") == "training" and not bool(settings.training_attack)
		if ai.training != passive:
			ai.training = passive
			ai.reset_opening()
	if is_instance_valid(world):
		for light in world.find_children("*","DirectionalLight3D",true,false):
			light.shadow_enabled = int(settings.quality) == 2

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(diagnostics):
			diagnostics.event("window_close")
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if match_active and not get_tree().paused:
			_pause()
		elif match_active:
			_menu()
		else:
			get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if is_instance_valid(ui):
			ui.touch.reset()
		if match_active and not get_tree().paused:
			_pause()
		if is_instance_valid(audio):
			audio.set_suspended(true)
		if is_instance_valid(diagnostics):
			diagnostics.event("app_suspended")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		if not match_active and is_instance_valid(audio):
			audio.set_suspended(false)
		if is_instance_valid(diagnostics):
			diagnostics.event("app_foreground")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not OS.has_feature("mobile"):
		if event.physical_keycode == KEY_F11 or (event.physical_keycode == KEY_ENTER and event.alt_pressed):
			ui.settings.fullscreen = not bool(settings.fullscreen)
			ui._save_settings()
			get_viewport().set_input_as_handled()

func _load_progress() -> void:
	var save := ConfigFile.new()
	if save.load("user://progress.cfg") == OK:
		wins = int(save.get_value("records","wins",0))
		best_survival = int(save.get_value("records","survival",0))

func _save_progress() -> void:
	var save := ConfigFile.new()
	save.set_value("records","wins",wins)
	save.set_value("records","survival",best_survival)
	save.save("user://progress.cfg")
