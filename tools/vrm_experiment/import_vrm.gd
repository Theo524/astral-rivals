extends SceneTree
## VRM 1.0 through the pinned importer; all outputs stay in the private project.

var extensions: Array[GLTFDocumentExtension] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# First-priority registration prepends: reverse the dependency order so
	# humanoid setup runs before spring bones, and all VRM work before meshes.
	for filename in ["VRMC_materials_mtoon","VRMC_materials_hdr_emissiveMultiplier","VRMC_springBone","VRMC_node_constraint","VRMC_vrm"]:
		var extension: GLTFDocumentExtension = load("res://addons/vrm/1.0/"+filename+".gd").new()
		extensions.append(extension)
		# VRM post-processing must precede Godot's built-in importer-mesh
		# converter; otherwise its scene-node references have already been freed.
		GLTFDocument.register_gltf_document_extension(extension,true)
	var legacy: GLTFDocumentExtension = load("res://addons/vrm/vrm_extension.gd").new()
	extensions.append(legacy)
	GLTFDocument.register_gltf_document_extension(legacy,true)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED
	# Godot 4.6 logs a dictionary error when an absent additional-data key is
	# read. Upstream uses NIL as the initial sentinel, so seed it explicitly.
	state.set_additional_data(&"vrm/already_processed",null)
	state.set_additional_data(&"vrm/head_hiding_method",5)
	var result := document.append_from_file("res://user_assets/kaizen.vrm",state,EditorSceneFormatImporter.IMPORT_USE_NAMED_SKIN_BINDS)
	if result != OK:
		printerr("VRM import failed: ",error_string(result))
		quit(1)
		return
	var model := document.generate_scene(state)
	for extension in extensions:
		GLTFDocument.unregister_gltf_document_extension(extension)
	if model == null:
		printerr("VRM scene generation failed")
		quit(1)
		return
	var skeletons := model.find_children("*","Skeleton3D",true,false)
	var players := model.find_children("*","AnimationPlayer",true,false)
	var blend_shapes: int = 0
	var skinned: int = 0
	var shader_surfaces: int = 0
	var invalid_binds: int = 0
	var textured_surfaces: int = 0
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if mesh.skin != null:
			skinned += 1
			var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
			for bind in mesh.skin.get_bind_count():
				var name: StringName = mesh.skin.get_bind_name(bind)
				if skeleton == null or (name != &"" and skeleton.find_bone(name) < 0) or (name == &"" and (mesh.skin.get_bind_bone(bind) < 0 or mesh.skin.get_bind_bone(bind) >= skeleton.get_bone_count())):
					invalid_binds += 1
		blend_shapes += mesh.mesh.get_blend_shape_count()
		for surface in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(surface)
			if material is ShaderMaterial:
				shader_surfaces += 1
				for uniform in material.shader.get_shader_uniform_list():
					if material.get_shader_parameter(uniform.name) is Texture2D:
						textured_surfaces += 1
						break
	var clips: Array = []
	for player in players:
		clips.append_array(Array(player.get_animation_list()))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://user_assets/source_manifest.json"))
	var missing_expressions: Array = []
	for expression in manifest.expressions:
		if not clips.has(expression): missing_expressions.append(expression)
	var valid: bool = not skeletons.is_empty() and skinned > 0 and blend_shapes == int(manifest.morph_targets) and missing_expressions.is_empty() and invalid_binds == 0 and textured_surfaces > 0
	if not valid:
		printerr("Imported VRM did not preserve the required skin/morph/expression/material contract")
		model.free()
		quit(1)
		return
	var packed := PackedScene.new()
	result = packed.pack(model)
	if result == OK:
		result = ResourceSaver.save(packed,"res://user_assets/candidate.scn",ResourceSaver.FLAG_COMPRESS)
	if result != OK:
		printerr("Private native scene save failed: ",error_string(result))
		model.free()
		quit(1)
		return
	var report := {"native_scene_saved":true,"skeletons":skeletons.size(),"bones":skeletons[0].get_bone_count() if not skeletons.is_empty() else 0,"skinned_meshes":skinned,"blend_shapes":blend_shapes,"source_morphs_preserved":true,"invalid_skin_binds":invalid_binds,"shader_surfaces":shader_surfaces,"textured_surfaces":textured_surfaces,"missing_expressions":missing_expressions,"expression_clips":clips}
	var file := FileAccess.open("res://results/import.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PRIVATE VRM IMPORT: scene saved; skeletons=",skeletons.size()," skinned=",skinned," morphs=",blend_shapes)
	model.free()
	quit(0)
