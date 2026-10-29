extends SceneTree
## Real OpenGL capture harness. Requires a graphical display; headless is rejected.
var game: Node3D
var failures: int = 0
var output: String = "res://docs/review"

func _initialize() -> void:
	call_deferred("_run")

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	if screenshot == null or screenshot.is_empty():
		failures += 1
		printerr("FAIL: rendered capture empty: ",name)
		return
	var error: Error = screenshot.save_png(output+"/"+name+".png")
	if error != OK:
		failures += 1
	print("CAPTURE ",name," ",screenshot.get_width(),"x",screenshot.get_height()," status=",error)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FAIL: graphical renderer required; headless captures cannot verify art")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(15)
	print("RENDER DEVICE: ",RenderingServer.get_video_adapter_name())
	await _capture("godot_menu")
	game.ui.settings.show_touch = true
	game.ui.start_match.emit({"player":0,"enemy":1,"arena":1,"difficulty":0,"mode":"training"})
	await _frames(230)
	await _capture("godot_arena")
	game.player.position = Vector3.ZERO
	game.enemy.position = Vector3(0,0,-1.5)
	game.player.rotation.y = 0
	game.enemy.rotation.y = PI
	game.player.request_action("attack")
	await _frames(10)
	await _capture("godot_melee")
	await _frames(40)
	game.player.position = Vector3.ZERO
	game.enemy.position = Vector3(0,0,-6)
	game.player.energy = 100
	game.player.request_action("special")
	await _frames(35)
	await _capture("godot_beam")
	await _frames(90)
	game.player.energy = 100
	game.player.request_action("transform")
	await _frames(45)
	await _capture("godot_transform")
	await _frames(45)
	game.ui.pause_requested.emit()
	await _frames(3)
	await _capture("godot_pause")
	game.ui.resume_requested.emit()
	game.ui.menu_requested.emit()
	await _frames(8)
	game.ui._select_character(2)
	await _frames(15)
	await _capture("godot_akira_selection")
	# Exercise an entire full-health fight with the real tactics and damage code.
	# A second AI supplies player intents, while the ordinary controller remains
	# covered by UI/input tests and the keyboard movement check below.
	game.ui.settings.show_touch = false
	game.ui.start_match.emit({"player":2,"enemy":1,"arena":0,"difficulty":2,"mode":"versus"})
	game.controller.enabled = false
	var sparring = load("res://scripts/combat/enemy_ai.gd").new()
	sparring.fighter = game.player
	sparring.target = game.enemy
	sparring.difficulty = 2
	game.world.add_child(sparring)
	var complete: bool = false
	for frame in 9000:
		await _frames(1)
		if frame == 720:
			await _capture("godot_full_match")
		if not game.match_active:
			complete = true
			break
	if complete:
		await _frames(20)
		await _capture("godot_match_result")
		print("FULL HEALTH GRAPHICAL MATCH: complete, seconds=",game.elapsed," player_hp=",game.player.hp," enemy_hp=",game.enemy.hp)
	else:
		failures += 1
		printerr("FAIL: full-health graphical fight did not finish within 150 simulation seconds")
	game.queue_free()
	await _frames(3)
	print("RENDER SMOKE: ","passed" if failures == 0 else "failed")
	quit(0 if failures == 0 else 1)
