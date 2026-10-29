extends SceneTree
## Isolated GLB import experiment. Never loads or replaces a playable fighter.
## godot --headless --path . --script res://tools/kaizen_base_intake.gd -- input.glb output.json

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Expected -- input.glb output.json")
		quit(1)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result: Error = document.append_from_file(args[0],state)
	if result != OK:
		printerr("GLB intake failed: ",error_string(result))
		quit(1)
		return
	var model := document.generate_scene(state)
	if model == null:
		printerr("GLB intake generated no scene")
		quit(1)
		return
	root.add_child(model)
	var skeletons := model.find_children("*","Skeleton3D",true,false)
	var players := model.find_children("*","AnimationPlayer",true,false)
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	var skinned: int = 0
	for mesh in meshes:
		if mesh.skin != null:
			skinned += 1
	var report := {
		"engine": Engine.get_version_info().string,
		"input": args[0],
		"import_error": int(result),
		"mesh_instances": meshes.size(),
		"skeletons": skeletons.size(),
		"skinned_meshes": skinned,
		"animation_players": players.size(),
		"meets_current_warrior_rig_preconditions": not skeletons.is_empty() and not players.is_empty() and skinned > 0,
		"scope": "Import only; not graphical, deformation, combat or art-quality verification"
	}
	var file := FileAccess.open(args[1],FileAccess.WRITE)
	if file == null:
		model.free()
		printerr("Could not write intake report")
		quit(1)
		return
	file.store_string(JSON.stringify(report,"\t")+"\n")
	file.close()
	print("BASE INTAKE: ",JSON.stringify(report))
	model.free()
	# The fixed official candidate must import as three meshes but must not be
	# misrepresented as a working skinned fighter simply because GLB loads.
	quit(0 if meshes.size() == 3 and skeletons.is_empty() and skinned == 0 and players.is_empty() else 1)
