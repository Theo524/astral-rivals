extends Node
## Bounded diagnostic evidence; never account or credential data.
var log_path: String = "user://logs/session.log"
var _sample_elapsed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("user://logs")
	if FileAccess.file_exists(log_path):
		DirAccess.copy_absolute(log_path,"user://logs/previous-session.log")
	var file := FileAccess.open(log_path,FileAccess.WRITE)
	if file != null:
		file.store_line("ASTRAL RIVALS SESSION " + Time.get_datetime_string_from_system(true))
	event("startup",{"engine":Engine.get_version_info().get("string",""),"os":OS.get_name(),"os_version":OS.get_version(),"display":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"mobile":OS.has_feature("mobile")})

func event(kind: String, details: Dictionary = {}) -> void:
	var file := FileAccess.open(log_path,FileAccess.READ_WRITE)
	if file == null:
		return
	if file.get_length() > 262144:
		file.close()
		file = FileAccess.open(log_path,FileAccess.WRITE)
	else:
		file.seek_end()
	file.store_line(JSON.stringify({"ms":Time.get_ticks_msec(),"event":kind,"details":details}))

func _process(delta: float) -> void:
	_sample_elapsed += delta
	if _sample_elapsed >= 15.0:
		_sample_elapsed = 0.0
		event("monitors",{"fps":Engine.get_frames_per_second(),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"static_memory":OS.get_static_memory_usage()})

func _exit_tree() -> void:
	event("orderly_shutdown")
