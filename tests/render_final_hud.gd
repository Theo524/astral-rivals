extends SceneTree
## Short rendered fixture for final HUD inspection. The separate render_smoke
## test exercises the complete countdown and a full-health fight.
func _initialize() -> void:
	call_deferred("_run")

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png("res://docs/review/"+name+".png")
	assert(result == OK)
	print("FINAL RENDER CAPTURE: ",name)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(8)
	await _save("godot_menu_final")
	game.ui.settings.show_touch = true
	game.ui.start_match.emit({"player":0,"enemy":1,"arena":1,"difficulty":0,"mode":"training"})
	# Explicitly staged close-range render fixture; not a countdown test.
	game.countdown_remaining = 0.0
	game.player.combat_locked = false
	game.enemy.combat_locked = false
	game.ui.set_countdown("")
	game.show_notice("TRAINING  /  MELEE PRACTICE",3.0)
	game.player.position = Vector3.ZERO
	game.enemy.position = Vector3(0,0,-1.5)
	game.player.rotation.y = 0.0
	game.enemy.rotation.y = PI
	game.camera.snap()
	await _frames(4)
	game.player.request_action("attack")
	await _frames(10)
	await _save("godot_melee_final")
	game.queue_free()
	await _frames(3)
	print("FINAL RENDER FIXTURE: passed")
	quit(0)
