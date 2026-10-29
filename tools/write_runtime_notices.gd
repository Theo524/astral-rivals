extends SceneTree
## Generate notices from the exact Godot runtime being distributed.
func _initialize() -> void:
	var destination: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "res://build/GODOT_AND_THIRD_PARTY_NOTICES.txt"
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var output := FileAccess.open(destination,FileAccess.WRITE)
	if output == null:
		printerr("Cannot write runtime notices: ",destination)
		quit(1)
		return
	output.store_line("Astral Rivals uses Godot "+str(Engine.get_version_info().string)+".\n")
	output.store_line(Engine.get_license_text())
	output.store_line("\nCOPYRIGHT INFORMATION\n")
	output.store_line(JSON.stringify(Engine.get_copyright_info(),"  "))
	output.store_line("\nTHIRD-PARTY LICENSE TEXTS\n")
	var licenses: Dictionary = Engine.get_license_info()
	for name in licenses:
		output.store_line("\n"+str(name)+"\n"+str(licenses[name]))
	output.close()
	print("Runtime notices written: ",destination)
	quit(0)
