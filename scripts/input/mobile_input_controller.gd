extends Control
## Pointer-owned controls: moving one finger never releases another button.
var button_scale := 1.0
var sensitivity := 1.0
var layout_preset := 1
var layout_scale := 1.0
var joystick_center := Vector2(119,593)
var joystick_radius := 59.0
var joystick_pointer := -99
var joystick_origin := Vector2.ZERO
var joystick_vector := Vector2.ZERO
var pointers: Dictionary = {}
var pressed: Dictionary = {}
var edges: Dictionary = {}
var button_defs: Array[Dictionary] = []
var enabled := true
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_layout()
	resized.connect(_layout)

func _layout() -> void:
	var w := get_viewport_rect().size.x
	var h := get_viewport_rect().size.y
	var fit := minf(w/1280.0,h/720.0)
	var offset := Vector2((w-1280.0*fit)*0.5,h-720.0*fit)
	var spread: float = [0.92,1.0,1.10][clampi(layout_preset,0,2)]
	var s := clampf(button_scale, 0.75, 1.3)*spread
	layout_scale = fit
	joystick_center = offset+Vector2(119,593)*fit
	joystick_radius = 59.0*fit
	var safe_left := 0.0
	var safe_right := w
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var screen: Vector2i = DisplayServer.screen_get_size()
		if screen.x > 0 and safe.size.x > 0:
			safe_left = float(safe.position.x)/float(screen.x)*w
			safe_right = float(safe.end.x)/float(screen.x)*w
	joystick_center.x = maxf(joystick_center.x,safe_left+84.0*fit)
	button_defs = [
		{"action":"attack","label":"STRIKE","key":"J / X","pos":Vector2(1280-155,720-123),"r":40.0*s,"color":Color("64e8ff")},
		{"action":"heavy","label":"HEAVY","key":"K / Y","pos":Vector2(1280-77,720-191),"r":31.0*s,"color":Color("ffcb75")},
		{"action":"blast","label":"BLAST","key":"L / B","pos":Vector2(1280-73,720-67),"r":30.0*s,"color":Color("64e8ff")},
		{"action":"guard","label":"GUARD","key":"Q / LB","pos":Vector2(1280-238,720-65),"r":30.0*s,"color":Color("c2cbe6")},
		{"action":"dodge","label":"VANISH","key":"X / A","pos":Vector2(1280-237,720-176),"r":28.0*s,"color":Color("c2cbe6")},
		{"action":"dash","label":"DASH","key":"SHIFT / RB","pos":Vector2(1280-321,720-120),"r":28.0*s,"color":Color("64e8ff")},
		{"action":"special","label":"BEAM","key":"E / LS","pos":Vector2(1280-154,720-248),"r":31.0*s,"color":Color("ffcb75")},
		{"action":"charge","label":"CHARGE","key":"C / DOWN","pos":Vector2(1280-321,720-235),"r":28.0*s,"color":Color("64e8ff")},
		{"action":"transform","label":"AWAKEN","key":"T / UP","pos":Vector2(1280-404,720-177),"r":28.0*s,"color":Color("ffcb75")},
		{"action":"lock","label":"LOCK","key":"TAB / RS","pos":Vector2(1280-405,720-66),"r":25.0*s,"color":Color("c2cbe6")},
		{"action":"ascend","label":"RISE","key":"SPACE / RT","pos":Vector2(247,720-160),"r":27.0*s,"color":Color("64e8ff")},
		{"action":"descend","label":"FALL","key":"CTRL / LT","pos":Vector2(247,720-75),"r":27.0*s,"color":Color("c2cbe6")}
	]
	# Expand the action cluster as a unit so larger targets never overlap.
	for b in button_defs:
		if b.pos.x > 640.0:
			b.pos = Vector2(1280.0+(b.pos.x-1280.0)*s,720.0+(b.pos.y-720.0)*s)
		b.pos = offset+b.pos*fit
		b.r *= fit
		if b.pos.x > w*0.5:
			b.pos.x -= maxf(0.0,w-safe_right)
		else:
			b.pos.x += safe_left
	queue_redraw()

func apply_settings(settings: Dictionary) -> void:
	button_scale = float(settings.get("button_scale", 1.0))
	sensitivity = float(settings.get("sensitivity", 1.0))
	layout_preset = clampi(int(settings.get("touch_layout",1)),0,2)
	reset()
	_layout()

func movement() -> Vector2:
	return joystick_vector

func held(action: String) -> bool:
	return enabled and int(pressed.get(action,0)) > 0

func consume(action: String) -> bool:
	if not enabled:
		return false
	var result := bool(edges.get(action,false))
	edges[action] = false
	return result

func reset() -> void:
	pointers.clear()
	pressed.clear()
	edges.clear()
	joystick_pointer = -99
	joystick_vector = Vector2.ZERO
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not enabled or not visible:
		return
	# Godot can emit an emulated mouse event for the first touch.
	if event is InputEventMouse and event.device == -1:
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			_pointer_down(event.index, event.position)
		else:
			if event.canceled and pointers.has(event.index):
				var action: String = pointers[event.index]
				edges.erase(action)
			_pointer_up(event.index)
	elif event is InputEventScreenDrag:
		_pointer_move(event.index,event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_down(-1,event.position)
		else:
			_pointer_up(-1)
	elif event is InputEventMouseMotion and pointers.has(-1):
		_pointer_move(-1,event.position)

func _pointer_down(id: int, pos: Vector2) -> void:
	if pointers.has(id):
		_pointer_up(id)
	for b in button_defs:
		if pos.distance_to(b.pos) <= b.r + 5:
			pointers[id] = b.action
			pressed[b.action] = int(pressed.get(b.action,0)) + 1
			edges[b.action] = true
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
	if pos.distance_to(joystick_center) <= 98.0*layout_scale and joystick_pointer == -99:
		joystick_pointer = id
		joystick_origin = joystick_center
		pointers[id] = "joystick"
		_pointer_move(id,pos)
		get_viewport().set_input_as_handled()

func _pointer_move(id: int, pos: Vector2) -> void:
	if id == joystick_pointer:
		joystick_vector = ((pos-joystick_origin) / (joystick_radius / sensitivity)).limit_length(1.0)
		queue_redraw()

func _pointer_up(id: int) -> void:
	if not pointers.has(id):
		return
	var action: String = pointers[id]
	pointers.erase(id)
	if id == joystick_pointer:
		joystick_pointer = -99
		joystick_vector = Vector2.ZERO
	else:
		pressed[action] = maxi(0,int(pressed.get(action,0))-1)
	queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT,NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		reset()

func _draw() -> void:
	if _font == null:
		return
	var center := joystick_center
	draw_circle(center,72*layout_scale,Color(0.03,0.08,0.14,0.48))
	draw_arc(center,71*layout_scale,0,TAU,48,Color(0.37,0.83,0.96,0.4),1.5,true)
	draw_arc(center,49*layout_scale,0,TAU,48,Color(0.37,0.83,0.96,0.12),1,true)
	for n in 4:
		var dir := Vector2.RIGHT.rotated(n*PI/2)
		draw_line(center+dir*77*layout_scale,center+dir*83*layout_scale,Color(0.37,0.83,0.96,0.5),2,true)
	draw_circle(center+joystick_vector*47*layout_scale,24*layout_scale,Color(0.16,0.48,0.6,0.45))
	draw_arc(center+joystick_vector*47*layout_scale,24*layout_scale,0,TAU,32,Color(0.5,0.93,1.0,0.7),1.5,true)
	var foot := "MOVE  ·  WASD / LEFT STICK"
	draw_string(_font,joystick_center+Vector2(-96,98)*layout_scale,foot,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(0.63,0.76,0.86,0.8))
	for b in button_defs:
		var active := held(b.action)
		var color: Color = b.color
		var bg := Color(0.025,0.06,0.11,0.66)
		if active:
			bg = Color(color,0.30)
		draw_circle(b.pos,b.r,bg)
		draw_arc(b.pos,b.r,0,TAU,40,Color(color,0.90 if active else 0.55),2 if active else 1.2,true)
		draw_arc(b.pos,b.r-4,-PI*0.95,-PI*0.12,16,Color(color,0.22),2,true)
		var label_size := 10 if str(b.label).length() > 6 else 11
		var text_size := _font.get_string_size(b.label,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size)
		draw_string(_font,b.pos+Vector2(-text_size.x/2,1),b.label,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size,color)
		var keys_size := _font.get_string_size(b.key,HORIZONTAL_ALIGNMENT_LEFT,-1,8)
		draw_string(_font,b.pos+Vector2(-keys_size.x/2,13),b.key,HORIZONTAL_ALIGNMENT_LEFT,-1,8,Color(0.65,0.75,0.85,0.8))
