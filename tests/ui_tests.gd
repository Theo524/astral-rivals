extends SceneTree
## Real UI/input regression suite; no combat or rendering is needed.
## Run from the project directory with isolated writable user data:
## XDG_DATA_HOME=/tmp/astral-ui-tests/data XDG_CONFIG_HOME=/tmp/astral-ui-tests/config \
## XDG_CACHE_HOME=/tmp/astral-ui-tests/cache godot --headless --path . --script res://tests/ui_tests.gd
## The test also isolates its settings filename and deletes it on completion.
const GameUI = preload("res://scripts/ui/game_ui.gd")
const PlayerInput = preload("res://scripts/input/player_controller.gd")
var ui
var checks: int = 0
var failures: Array[String] = []
var requests: Array[Dictionary] = []
var pauses: int = 0
var settings_events: int = 0
var temporary_settings: String

class FighterDisplay extends Node:
	var data: Dictionary = {"name":"Kaizen"}
	var hp: float = 720.0
	var max_hp: float = 1000.0
	var energy: float = 64.0
	var max_energy: float = 100.0
	var form: int = 1

class InputTarget extends Node3D:
	var hp: float = 100.0
	var energy: float = 100.0
	var form: int = 0
	var locked: bool = true
	var intent: Dictionary = {}
	var requests: Array[String] = []
	func request_action(action: String) -> void:
		requests.append(action)

class InputCamera extends Camera3D:
	var locked: bool = true

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ",message)
	else:
		failures.append(message)
		printerr("FAIL: ",message)

func _frames(count: int=2) -> void:
	for i in count:
		await process_frame

func _mouse_click(position_at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position_at
	motion.global_position = position_at
	root.push_input(motion,true)
	await _frames(1)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position_at
		event.global_position = position_at
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event,true)
		await _frames(1)

func _touch(id: int, position_at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = position_at
	event.pressed = down
	root.push_input(event,true)

func _drag(id: int, position_at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = id
	event.position = position_at
	root.push_input(event,true)

func _key(key: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = down
	root.push_input(event,true)

func _action_position(action: String) -> Vector2:
	for definition in ui.touch.button_defs:
		if definition.action == action:
			return definition.pos
	return Vector2(-999,-999)

func _test_menu() -> void:
	_expect(ui.menu.visible and not ui.battle.visible,"launch displays the menu and hides the combat HUD")
	_expect(not ui.touch.enabled and not ui.touch.visible,"menu disables all combat touch input")
	await _mouse_click(ui.character_cards[2].global_position+ui.character_cards[2].size*0.5)
	_expect(ui.selected_character == 2,"a real mouse click selects Akira's character card")
	ui.mode_choice.select(2)
	ui.arena_choice.select(2)
	ui.enemy_choice.select(0)
	ui.difficulty_choice.select(2)
	await _mouse_click(Vector2(980,545))
	_expect(requests.size() == 1,"the start button emits exactly one match request")
	if not requests.is_empty():
		var selected: Dictionary = requests[0]
		_expect(selected == {"player":2,"enemy":0,"arena":2,"difficulty":2,"mode":"arcade"},"match request contains actual character, arena, difficulty and mode selections")
	ui.set_records(17,6)
	_expect("17" in ui.records_label.text and "06" in ui.records_label.text,"career wins and best survival are visible in the menu")

func _test_hud_and_focus() -> void:
	ui.character_cards[2].grab_focus()
	ui.show_battle({"mode":"training","difficulty":0})
	await _frames()
	_expect(ui.battle.visible and not ui.menu.visible and ui.touch.enabled,"entering combat shows the HUD and enables touch controls")
	_expect(root.gui_get_focus_owner() == null,"starting combat releases menu keyboard and gamepad focus")
	var dummy := FighterDisplay.new()
	root.add_child(dummy)
	ui.update_hud(dummy,dummy,5,125.0,"TEST NOTICE")
	_expect(is_equal_approx(ui.player_hp.value,720.0) and is_equal_approx(ui.player_energy.value,64.0),"HUD health and energy bars reflect fighter values")
	_expect(ui.player_energy.size.y <= 8.0 and ui.enemy_energy.size.y <= 8.0,"energy bars retain their compact height and cannot cover the numeric HUD labels")
	_expect(ui.player_form.text == "AWAKENED" and ui.time_label.text == "02:05","HUD displays actual form and elapsed time")
	_expect("05" in ui.combo_label.text and ui.status_label.text == "TEST NOTICE","HUD displays confirmed hit count and combat notices")
	for node in ui.battle.find_children("*","Button",true,false):
		_expect(node.focus_mode == Control.FOCUS_NONE,"combat HUD buttons cannot trap Space, Tab or gamepad A")
	var before: int = requests.size()
	_key(KEY_SPACE,true)
	await _frames(1)
	_key(KEY_SPACE,false)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	root.push_input(pad,true)
	await _frames(1)
	pad = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = false
	root.push_input(pad,true)
	await _frames()
	_expect(pauses == 0 and requests.size() == before,"Space and gamepad A in battle never activate a UI button")
	dummy.queue_free()

func _test_real_multitouch() -> void:
	var origin: Vector2 = ui.touch.joystick_center
	var strike := _action_position("attack")
	var charge := _action_position("charge")
	var blast := _action_position("blast")
	_touch(0,origin,true)
	_drag(0,origin+Vector2(55,-12))
	_touch(1,strike,true)
	_touch(2,charge,true)
	_touch(3,blast,true)
	await _frames()
	_expect(ui.touch.movement().length() > 0.8,"screen drag produces full virtual joystick movement")
	_expect(ui.touch.held("attack") and ui.touch.held("charge") and ui.touch.held("blast"),"three simultaneous action fingers remain held alongside movement")
	_expect(ui.touch.consume("blast") and not ui.touch.consume("blast"),"one touch press produces exactly one consumable action edge")
	_touch(2,charge,false)
	await _frames()
	_expect(not ui.touch.held("charge") and ui.touch.held("attack") and ui.touch.held("blast"),"releasing charge preserves the other fingers' attack buttons")
	_drag(1,Vector2(600,300))
	await _frames()
	_expect(ui.touch.held("attack"),"a finger owns its action until release even when dragged outside the button")
	_touch(0,origin,false)
	await _frames()
	_expect(ui.touch.movement() == Vector2.ZERO and ui.touch.held("attack"),"releasing the joystick clears movement without releasing attack")
	_touch(1,strike,false)
	_touch(3,blast,false)
	await _frames()
	_expect(not ui.touch.held("attack") and not ui.touch.held("blast"),"releasing action fingers clears their held states")
	# Ignore the emulated mouse event generated by Godot for the first touch.
	_touch(4,strike,true)
	var ghost := InputEventMouseButton.new()
	ghost.device = -1
	ghost.button_index = MOUSE_BUTTON_LEFT
	ghost.position = strike
	ghost.pressed = true
	root.push_input(ghost,true)
	await _frames()
	_expect(ui.touch.pressed.get("attack",0) == 1,"touch-to-mouse emulation cannot duplicate an attack press")
	_touch(4,strike,false)
	await _frames()
	_expect(not ui.touch.held("attack"),"a real touch release cannot leave an emulated mouse button stuck")
	_touch(5,charge,true)
	await _frames()
	ui.touch.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_expect(not ui.touch.held("charge") and ui.touch.pointers.is_empty(),"losing window focus clears all finger ownership and held inputs")

func _test_controller_combinations() -> void:
	# The isolated harness does not instantiate GameManager, which normally registers these.
	for action in ["left","right","forward","back"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	ui.show_battle({"mode":"training"})
	var target := InputTarget.new()
	var camera := InputCamera.new()
	var controller := PlayerInput.new()
	root.add_child(target)
	root.add_child(camera)
	root.add_child(controller)
	controller.set_physics_process(false)
	controller.fighter = target
	controller.camera = camera
	controller.touch = ui.touch
	# Exercise the real player's input adapter, including context combinations.
	for combination in [["charge","blast","sphere"],["guard","blast","homing"],["charge","heavy","nova"]]:
		ui.touch.reset()
		_touch(0,_action_position(combination[0]),true)
		_touch(1,_action_position(combination[1]),true)
		await _frames()
		controller._physics_process(1.0/60.0)
		_expect(not target.requests.is_empty() and target.requests[-1] == combination[2],"real PlayerController resolves touch " + combination[0] + " + " + combination[1] + " into " + combination[2])
		_touch(0,_action_position(combination[0]),false)
		_touch(1,_action_position(combination[1]),false)
		await _frames()
	ui.touch.reset()
	target.form = 2
	target.energy = 100.0
	_touch(0,_action_position("special"),true)
	await _frames()
	controller._physics_process(1.0/60.0)
	_expect(target.requests[-1] == "ultimate","ultimate form and sufficient energy resolve the Beam touch button into an ultimate")
	_touch(0,_action_position("special"),false)
	ui.touch.reset()
	target.energy = 50.0
	_touch(0,_action_position("special"),true)
	await _frames()
	controller._physics_process(1.0/60.0)
	_expect(target.requests[-1] == "special","lower energy preserves the standard beam action instead of forcing an unavailable ultimate")
	_touch(0,_action_position("special"),false)
	ui.touch.reset()
	_touch(0,_action_position("lock"),true)
	await _frames()
	controller._physics_process(1.0/60.0)
	_expect(not target.locked and not camera.locked,"Lock touch button updates both fighter and camera lock state")
	_touch(0,_action_position("lock"),false)
	ui.touch.reset()
	var origin: Vector2 = ui.touch.joystick_center
	_touch(0,origin,true)
	_drag(0,origin+Vector2(50,0))
	_touch(1,_action_position("ascend"),true)
	await _frames()
	controller._physics_process(1.0/60.0)
	_expect(target.intent.move.x > 0.5 and target.intent.ascend,"the real player adapter combines camera-relative joystick movement and ascent")
	var count: int = target.requests.size()
	controller.enabled = false
	_touch(2,_action_position("attack"),true)
	await _frames()
	controller._physics_process(1.0/60.0)
	_expect(target.requests.size() == count,"a disabled player controller gates touch combat requests")
	ui.touch.reset()
	controller.queue_free()
	target.queue_free()
	camera.queue_free()
	await _frames()

func _test_pause_and_results() -> void:
	_touch(6,_action_position("attack"),true)
	await _frames()
	ui.show_pause()
	await _frames()
	_expect(ui.mode == "pause" and ui.overlay != null and not ui.touch.visible,"pause displays a panel and hides combat touch controls")
	_expect(not ui.touch.enabled and not ui.touch.held("attack"),"pausing clears held attacks and gates further input")
	_touch(7,_action_position("blast"),true)
	await _frames()
	_expect(not ui.touch.held("blast"),"screen touches while paused cannot fire combat abilities")
	ui.hide_pause()
	await _frames()
	_expect(ui.mode == "battle" and ui.touch.enabled and root.gui_get_focus_owner() == null,"resuming restores combat input and releases pause-menu focus")
	var continued := [0]
	ui.continue_requested.connect(func(): continued[0] += 1)
	ui.show_result(true,"ARCADE / ROUND 1",true)
	await _frames()
	_expect(ui.mode == "result" and not ui.touch.enabled,"victory disables combat input and displays results")
	await _mouse_click(Vector2(640,408))
	_expect(continued[0] == 1,"the next challenger button emits the continuation request")
	var rematches := [0]
	ui.rematch_requested.connect(func(): rematches[0] += 1)
	ui.show_result(false,"Return stronger.",false)
	await _frames()
	await _mouse_click(Vector2(640,408))
	_expect(rematches[0] == 1,"defeat's fight again button emits the rematch request")
	ui.show_menu()
	await _frames()
	_expect(ui.menu.visible and ui.overlay == null and not ui.touch.enabled,"returning to the menu clears overlays and gates combat input")

func _test_settings_persistence() -> void:
	ui._open_settings()
	await _frames()
	_expect(ui.settings_overlay != null,"settings opens a functional customization panel")
	var sliders: Array[Node] = ui.settings_overlay.find_children("*","HSlider",true,false)
	_expect(sliders.size() == 3,"settings provides volume, touch size and joystick sensitivity sliders")
	if sliders.size() == 3:
		sliders[0].value = 0.35
		sliders[1].value = 1.25
		sliders[2].value = 1.4
	var choices: Array[Node] = ui.settings_overlay.find_children("*","OptionButton",true,false)
	if choices.size() >= 2:
		ui.settings_overlay.get_node("Setting_quality").select(0)
		ui.settings_overlay.get_node("Setting_quality").item_selected.emit(0)
		ui.settings_overlay.get_node("Setting_fps").select(0)
		ui.settings_overlay.get_node("Setting_fps").item_selected.emit(0)
	var toggles: Array[Node] = ui.settings_overlay.find_children("*","CheckButton",true,false)
	if not toggles.is_empty():
		ui.settings_overlay.get_node("Setting_shake").button_pressed = false
	await _frames()
	_expect(settings_events >= 6,"changing settings emits live updates for every adjusted control")
	_expect(ui.settings.quality == 0 and ui.settings.fps == 30 and not ui.settings.shake,"graphics, frame rate and camera shake controls update stored settings")
	_expect(is_equal_approx(ui.touch.button_scale,1.25) and is_equal_approx(ui.touch.sensitivity,1.4),"touch settings immediately reach the actual input controller")
	var overlap := false
	var definitions: Array[Dictionary] = ui.touch.button_defs
	for i in definitions.size():
		for j in range(i+1,definitions.size()):
			if definitions[i].pos.distance_to(definitions[j].pos) < definitions[i].r+definitions[j].r:
				overlap = true
	_expect(not overlap,"enlarged touch buttons retain separate non-overlapping hit targets")
	var saved := ConfigFile.new()
	_expect(saved.load(temporary_settings) == OK,"settings are written to the isolated test configuration file")
	_expect(is_equal_approx(float(saved.get_value("settings","volume",0)),0.35),"audio customization survives ConfigFile serialization")
	ui.queue_free()
	await _frames()
	ui = GameUI.new()
	ui.settings_path = temporary_settings
	root.add_child(ui)
	await _frames()
	_expect(ui.settings.quality == 0 and ui.settings.fps == 30 and not ui.settings.shake,"a fresh UI instance reloads saved graphics and shake settings")
	_expect(is_equal_approx(ui.settings.button_scale,1.25) and is_equal_approx(ui.settings.sensitivity,1.4),"a fresh UI instance reloads saved touch customization")
	_expect(is_equal_approx(ui.settings.volume,0.35),"a fresh UI instance reloads saved audio volume")
	ui._open_settings()
	await _frames()
	await _mouse_click(Vector2(1110,64))
	_expect(ui.settings_overlay == null,"settings Done button closes the customization panel")

func _test_new_presentation_and_controls() -> void:
	ui.show_menu()
	await _frames()
	_expect(ui.preview_viewport != null and ui.preview_model != null,"menu owns a real isolated 3D warrior preview")
	_expect(ui.preview_viewport.own_world_3d and ui.preview_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"menu preview has its own world and only renders while visible")
	var previous: Node3D = ui.preview_model
	ui._select_character((ui.selected_character+1)%3)
	await _frames()
	_expect(not is_instance_valid(previous) and ui.preview_stage.find_children("*","Node3D",false,false).size() <= 5,"changing character frees the previous preview instead of accumulating models")
	ui._open_tutorial()
	await _frames()
	_expect(ui.tutorial_overlay != null and ui.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"tutorial displays real lessons and suspends the hidden 3D preview")
	await _mouse_click(Vector2(1100,660))
	_expect(ui.tutorial_overlay == null,"tutorial Ready button closes the field guide")
	ui._open_settings()
	await _frames()
	_expect(ui.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"settings disables hidden preview rendering")
	for entry in [["resolution",2],["touch_layout",2]]:
		var choice: OptionButton = ui.settings_overlay.get_node("Setting_"+entry[0])
		choice.select(entry[1])
		choice.item_selected.emit(entry[1])
	ui.settings_overlay.get_node("Setting_fullscreen").button_pressed = true
	ui.settings_overlay.get_node("Setting_training_attack").button_pressed = true
	ui.settings_overlay.get_node("Setting_show_touch").button_pressed = false
	await _frames()
	_expect(ui.settings.fullscreen and ui.settings.resolution == 2,"fullscreen and resolution controls emit persisted PC display settings")
	_expect(ui.settings.training_attack and ui.settings.touch_layout == 2,"practice aggression and wide layout are independently configurable")
	ui._close_settings()
	ui.show_battle({"mode":"training"})
	await _frames()
	_expect(not ui.touch.visible and not ui.touch.enabled,"desktop can hide all touchscreen controls while retaining combat HUD")
	_expect(ui.preview_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"battle disables all selection-preview rendering")
	ui.set_countdown("3")
	_expect(ui.countdown_label.visible and ui.countdown_label.text == "3","match countdown has a central readable presentation")
	ui.set_countdown("")
	_expect(not ui.countdown_label.visible,"countdown clears after the fight begins")
	ui.settings.show_touch = true
	ui._save_settings()
	await _frames()
	_expect(ui.touch.visible and ui.touch.enabled,"touch controls can be enabled immediately on a desktop for testing")
	for preset in range(3):
		ui.touch.apply_settings({"touch_layout":preset,"button_scale":1.3,"sensitivity":1.0})
		var overlap := false
		var definitions: Array[Dictionary] = ui.touch.button_defs
		for i in definitions.size():
			for j in range(i+1,definitions.size()):
				if definitions[i].pos.distance_to(definitions[j].pos) < definitions[i].r+definitions[j].r:
					overlap = true
		_expect(not overlap,"layout %d keeps enlarged touch buttons separated" % preset)
	var position_at := _action_position("attack")
	_touch(10,position_at,true)
	var canceled := InputEventScreenTouch.new()
	canceled.index = 10
	canceled.position = position_at
	canceled.pressed = false
	canceled.canceled = true
	root.push_input(canceled,true)
	await _frames()
	_expect(not ui.touch.held("attack") and not ui.touch.consume("attack"),"OS-canceled touches cannot leave a held action or a queued attack")
	_touch(11,_action_position("charge"),true)
	ui.touch.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_expect(ui.touch.pointers.is_empty() and not ui.touch.held("charge"),"mobile application pause clears every held touch")
	ui.show_menu()
	await _frames()
	_expect(ui.preview_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"returning to selection restores the single 3D preview")

func _run() -> void:
	temporary_settings = "user://ui-tests-%d.cfg" % OS.get_process_id()
	ui = GameUI.new()
	ui.settings_path = temporary_settings
	ui.settings.show_touch = true
	ui.start_match.connect(func(config: Dictionary): requests.append(config))
	ui.pause_requested.connect(func(): pauses += 1)
	ui.settings_changed.connect(func(_settings: Dictionary): settings_events += 1)
	root.add_child(ui)
	await _frames(3)
	await _test_menu()
	await _test_hud_and_focus()
	await _test_real_multitouch()
	await _test_controller_combinations()
	await _test_pause_and_results()
	await _test_settings_persistence()
	await _test_new_presentation_and_controls()
	ui.queue_free()
	await _frames()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_settings))
	print("UI_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
