extends SceneTree
## Real-render Kaizen review and short gameplay check. Requires a display.
## The closeup and threequarter shots deliberately reframe existing game assets;
## the menu and battle images use the normal shipped cameras and UI.
var game: Node3D
var failures: int = 0
var output := "res://docs/review/phase1_kaizen"
var prefix := "after"

func _initialize() -> void:
	call_deferred("_run")

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _expect(value: bool, message: String) -> void:
	if value:
		print("PASS: ",message)
	else:
		failures += 1
		printerr("FAIL: ",message)

func _capture(name: String, viewport: Viewport = root) -> void:
	await RenderingServer.frame_post_draw
	var screenshot := viewport.get_texture().get_image()
	if screenshot == null or screenshot.is_empty():
		_expect(false,"Nonempty rendered image: "+name)
		return
	var path := output+"/"+prefix+"_"+name+".png"
	var result: Error = screenshot.save_png(path)
	_expect(result == OK,"Saved "+path)
	print("KAIZEN CAPTURE: ",screenshot.get_width(),"x",screenshot.get_height()," ",path)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: graphical rendering is required to review Kaizen")
		quit(1)
		return
	var requested := OS.get_environment("ASTRAL_REVIEW_PREFIX")
	if requested in ["before","after"]:
		prefix = requested
	DirAccess.make_dir_recursive_absolute(output)
	var ignored := FileAccess.open(output+"/.gdignore",FileAccess.WRITE)
	if ignored != null:
		ignored.close()
	root.size = Vector2i(1280,720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(12)
	print("KAIZEN RENDER DEVICE: ",RenderingServer.get_video_adapter_name())
	game.ui._select_character(0)
	await _frames(8)
	_expect(game.ui.preview_model.identity == "kaizen" and game.ui.preview_model.skeleton != null,"Kaizen's imported skeletal mesh is loaded in the menu")
	await _capture("menu")
	# Native 900px render of the same in-menu model and lights, reframed to
	# inspect face/hair/upper-body details. This is not a separate offline model.
	var preview_camera := game.ui.preview_stage.find_children("*","Camera3D",true,false)[0] as Camera3D
	var saved_camera: Transform3D = preview_camera.transform
	var saved_fov: float = preview_camera.fov
	game.ui.preview_container.stretch = false
	game.ui.preview_viewport.size = Vector2i(900,900)
	game.ui.preview_viewport.transparent_bg = false
	preview_camera.position = Vector3(0.30,1.92,-2.0)
	preview_camera.fov = 26.0
	preview_camera.look_at(Vector3(0,1.82,0))
	await _frames(4)
	await _capture("closeup",game.ui.preview_viewport)
	preview_camera.transform = saved_camera
	preview_camera.fov = saved_fov
	game.ui.preview_viewport.transparent_bg = true
	game.ui.preview_viewport.size = Vector2i(360,364)
	game.ui.preview_container.stretch = true
	game.ui.settings.show_touch = false
	game.ui.settings.training_attack = false
	game.ui.start_match.emit({"player":0,"enemy":1,"arena":0,"difficulty":0,"mode":"training"})
	_expect(game.player.combat_locked and not game.player.request_action("attack"),"Countdown prevents early Kaizen attacks")
	# Keep rendering the real countdown, at a smaller window while waiting. All
	# review captures and active control checks use the full 1280px viewport.
	root.size = Vector2i(640,360)
	await _frames(240)
	root.size = Vector2i(1280,720)
	await _frames(3)
	_expect(not game.player.combat_locked and game.countdown_remaining <= 0.0,"Normal three-second countdown finishes and unlocks combat")
	_expect(game.ai.training and game.player.hp == game.player.max_hp,"Training opponent remains passive")
	var old_position: Vector3 = game.player.position
	Input.action_press("right")
	await _frames(12)
	Input.action_release("right")
	await _frames(2)
	_expect(game.player.position.distance_to(old_position) > 0.05,"Keyboard action moves Kaizen through the normal player controller")
	game.player.position = Vector3.ZERO
	game.enemy.position = Vector3(0,0,-1.50)
	game.player.velocity = Vector3.ZERO
	game.enemy.velocity = Vector3.ZERO
	game.player.rotation.y = 0.0
	game.enemy.rotation.y = PI
	game.camera.snap()
	await _frames(15)
	var health_before: float = game.enemy.hp
	_expect(game.player.request_action("attack"),"Kaizen accepts a normal melee attack")
	await _frames(10)
	print("KAIZEN BATTLE CAPTURE STATE: ",game.player.state," progress=",game.player.state_time)
	await _capture("battle")
	await _frames(30)
	_expect(game.enemy.hp < health_before,"Kaizen's animated melee attack deals actual damage")
	# Explicitly staged threequarter angle: active game, same rendered fighter,
	# same arena lighting; only camera position is fixed to show the outfit front.
	game.player.position = Vector3.ZERO
	game.enemy.position = Vector3(1.50,0,-0.80)
	game.player.velocity = Vector3.ZERO
	game.enemy.velocity = Vector3.ZERO
	await _frames(12)
	game.camera.set_process(false)
	game.camera.position = Vector3(1.1,1.95,-4.5)
	game.camera.fov = 39.0
	game.camera.look_at(Vector3(0.30,1.1,-0.20))
	await _frames(3)
	await _capture("battle_threequarter")
	game.camera.set_process(true)
	game.queue_free()
	await _frames(4)
	print("KAIZEN PHASE1 RENDER CHECK: ","passed" if failures == 0 else "failed",", failures=",failures)
	quit(0 if failures == 0 else 1)
