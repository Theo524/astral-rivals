extends CanvasLayer
## The presentation layer only emits requests. Gameplay remains in GameManager.
signal start_match(config: Dictionary)
signal rematch_requested
signal menu_requested
signal pause_requested
signal resume_requested
signal continue_requested
signal settings_changed(settings: Dictionary)

const MobileInput = preload("res://scripts/input/mobile_input_controller.gd")
const Roster = preload("res://scripts/data/character_data.gd")
const WarriorVisual = preload("res://scripts/visuals/warrior_visual.gd")
const CYAN := Color("74e8ff")
const GOLD := Color("ffd28a")
const WHITE := Color("eef6ff")
const MUTED := Color("94a8c0")
const INK := Color("07121f")
const CHARACTERS := [
	{"name":"KAIZEN","title":"THE CELESTIAL WARRIOR","style":"BALANCED  /  BLUE ENERGY","color":Color("74e8ff"),"description":"A relentless skyward rush.\nBalanced speed, striking and energy."},
	{"name":"RYUZEN","title":"THE SHADOW CHAMPION","style":"CLOSE COMBAT  /  VOID ENERGY","color":Color("c3a1ff"),"description":"Close the gap. Break their guard.\nAggressive melee and heavy impact."},
	{"name":"AKIRA","title":"THE SOLAR GUARDIAN","style":"LONG RANGE  /  SOLAR ENERGY","color":Color("ffd28a"),"description":"Control the arena from a distance.\nPowerful blasts and radiant beams."}
]
var settings_path: String = "user://settings.cfg"
var records_label: Label
var settings: Dictionary = {"quality":0 if OS.has_feature("mobile") else 1,"fps":30 if OS.has_feature("mobile") else 60,"shake":true,"volume":0.7,"button_scale":1.0,"sensitivity":1.0,"fullscreen":false,"resolution":0,"training_attack":false,"touch_layout":1,"show_touch":OS.has_feature("mobile")}
var touch: Node
var root: Control
var design: Control
var menu: Control
var battle: Control
var overlay: Control
var settings_overlay: Control
var tutorial_overlay: Control
var preview_viewport: SubViewport
var preview_stage: Node3D
var preview_model: Node3D
var preview_container: SubViewportContainer
var preview_name: Label
var preview_title: Label
var countdown_label: Label
var _preview_clock: float = 0.0
var _preview_index: int = -1
var selected_character := 0
var character_cards: Array[Button] = []
var character_description: Label
var mode_choice: OptionButton
var enemy_choice: OptionButton
var arena_choice: OptionButton
var difficulty_choice: OptionButton
var player_hp: ProgressBar
var enemy_hp: ProgressBar
var player_energy: ProgressBar
var enemy_energy: ProgressBar
var player_name: Label
var enemy_name: Label
var player_form: Label
var enemy_form: Label
var health_text: Label
var enemy_health_text: Label
var combo_label: Label
var time_label: Label
var status_label: Label
var battle_mode: Label
var mode := "menu"
var _last_combo := 0
var _combo_timer := 0.0
var _notice_timer := 0.0

class MenuBackdrop extends Control:
	var elapsed := 0.0
	func _process(delta: float) -> void:
		elapsed += delta
		queue_redraw()
	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO,s),Color(0.015,0.035,0.065,0.96))
		for i in range(15):
			var x := fmod(i*121.0+elapsed*8.0,s.x+300)-150
			draw_line(Vector2(x,0),Vector2(x-400,s.y),Color(0.18,0.42,0.55,0.06),1.0,true)
		var glow := Vector2(s.x*0.43,s.y*0.31)
		for i in range(7,0,-1):
			draw_circle(glow,42.0+i*28.0,Color(0.10,0.43,0.58,0.012))
		draw_arc(glow,185,-1.2+elapsed*0.03,2.2+elapsed*0.03,60,Color(0.32,0.8,1.0,0.13),1.0,true)
		draw_arc(glow,177,2.3+elapsed*0.03,4.5+elapsed*0.03,40,Color(0.32,0.8,1.0,0.08),1.0,true)
		for i in range(38):
			var p := Vector2(fmod(i*197.0+25,s.x),fmod(i*97.0+elapsed*(2+i%4),s.y))
			draw_circle(p,1.0 if i%4 else 1.7,Color(0.58,0.84,1.0,0.2))
		draw_colored_polygon(PackedVector2Array([Vector2(s.x*0.59,0),Vector2(s.x*0.65,0),Vector2(s.x*0.4,s.y),Vector2(s.x*0.34,s.y)]),Color(0.15,0.6,0.8,0.025))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	design = Control.new()
	design.size = Vector2(1280,720)
	design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(design)
	_build_menu()
	_build_battle()
	touch = MobileInput.new()
	root.add_child(touch)
	touch.apply_settings(settings)
	touch.visible = false
	touch.enabled = false
	root.resized.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_resize()
	show_menu()
	settings_changed.emit.call_deferred(settings.duplicate())

func _resize() -> void:
	if design == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	root.size = viewport_size
	var fit := minf(viewport_size.x/1280.0,viewport_size.y/720.0)
	design.scale = Vector2.ONE*fit
	design.position = (viewport_size-Vector2(1280,720)*fit)*0.5

func _style(bg: Color, border: Color=Color.TRANSPARENT, width: int=1, radius: int=4) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(width)
	st.set_corner_radius_all(radius)
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	return st

func _panel(parent: Node, rect: Rect2, bg: Color, border: Color=Color.TRANSPARENT) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel",_style(bg,border))
	parent.add_child(p)
	return p

func _label(parent: Node, text_value: String, pos: Vector2, font_size: int=16, color: Color=WHITE, width: float=0) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0:
		label.custom_minimum_size.x = width
	parent.add_child(label)
	return label

func _button(parent: Node, text_value: String, rect: Rect2, accent: Color=CYAN, filled: bool=false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size",15)
	button.add_theme_color_override("font_color",INK if filled else accent)
	button.add_theme_color_override("font_hover_color",INK if filled else WHITE)
	button.add_theme_color_override("font_pressed_color",INK)
	button.add_theme_stylebox_override("normal",_style(accent if filled else Color(0.05,0.10,0.16,0.9),accent if filled else Color(accent,0.35),1,3))
	button.add_theme_stylebox_override("hover",_style(accent.lightened(0.12) if filled else Color(accent,0.18),accent,1,3))
	button.add_theme_stylebox_override("pressed",_style(accent,accent,1,3))
	button.add_theme_stylebox_override("focus",_style(Color.TRANSPARENT,Color(accent,0.9),2,3))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	return button

func _choice(parent: Node, items: Array, pos: Vector2, width: float=348) -> OptionButton:
	var option := OptionButton.new()
	option.position = pos
	option.size = Vector2(width,43)
	for item in items:
		option.add_item(str(item))
	option.add_theme_font_size_override("font_size",16)
	option.add_theme_color_override("font_color",WHITE)
	option.add_theme_color_override("font_hover_color",CYAN)
	option.add_theme_stylebox_override("normal",_style(Color("102337"),Color("27445a"),1,3))
	option.add_theme_stylebox_override("hover",_style(Color("17354a"),CYAN,1,3))
	option.add_theme_stylebox_override("pressed",_style(Color("17354a"),CYAN,1,3))
	option.get_popup().add_theme_font_size_override("font_size",17)
	option.get_popup().add_theme_stylebox_override("panel",_style(Color("0c1c2b"),Color("376179"),1,3))
	option.get_popup().add_theme_color_override("font_color",WHITE)
	option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(option)
	return option

func _build_menu() -> void:
	menu = Control.new()
	menu.size = Vector2(1280,720)
	design.add_child(menu)
	var backdrop := MenuBackdrop.new()
	backdrop.size = Vector2(1280,720)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(backdrop)
	_label(menu,"A / R",Vector2(48,27),24,CYAN)
	_label(menu,"ORIGINAL ANIME ARENA COMBAT",Vector2(139,37),12,MUTED)
	_label(menu,"PC  /  MOBILE",Vector2(1103,37),11,MUTED)
	_panel(menu,Rect2(48,76,1184,1),Color("23394b"))
	_label(menu,"BEYOND THE LIMIT.",Vector2(63,109),15,GOLD)
	_label(menu,"ASTRAL",Vector2(60,133),54,WHITE)
	_label(menu,"RIVALS",Vector2(60,187),54,CYAN)
	_label(menu,"The sky is your arena.",Vector2(65,261),16,MUTED)
	_panel(menu,Rect2(64,309,38,3),CYAN)
	_label(menu,"SELECT YOUR WARRIOR",Vector2(112,300),11,MUTED)
	for i in 3:
		var card := _button(menu,"",Rect2(64,340+i*72,244,61),CHARACTERS[i].color)
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.pressed.connect(_select_character.bind(i))
		character_cards.append(card)
		_label(card,"0%d" % (i+1),Vector2(12,11),10,Color(CHARACTERS[i].color,0.7))
		_label(card,CHARACTERS[i].name,Vector2(42,8),22,CHARACTERS[i].color)
		var short_titles := ["CELESTIAL WARRIOR","SHADOW CHAMPION","SOLAR GUARDIAN"]
		_label(card,short_titles[i],Vector2(43,35),9,MUTED)
	_build_preview()
	character_description = _label(menu,"",Vector2(341,555),13,MUTED)
	records_label = _label(menu,"CAREER WINS  00    /    SURVIVAL BEST  00",Vector2(65,633),11,GOLD)
	_button(menu,"HOW TO PLAY",Rect2(64,572,244,37),MUTED).pressed.connect(_open_tutorial)
	_panel(menu,Rect2(752,106,460,544),Color(0.035,0.075,0.12,0.95),Color("294359"))
	_label(menu,"BATTLE SETUP",Vector2(782,128),22,WHITE)
	_label(menu,"02  /  SET THE STAGE",Vector2(783,162),11,MUTED)
	_label(menu,"GAME MODE",Vector2(783,197),11,CYAN)
	mode_choice = _choice(menu,["VERSUS AI","TRAINING","ARCADE — THREE RIVALS","SURVIVAL — ENDLESS"],Vector2(783,217),397)
	_label(menu,"ARENA",Vector2(783,277),11,CYAN)
	arena_choice = _choice(menu,["ROCKY WASTELAND","CELESTIAL TOURNAMENT","RUINED FUTURE CITY"],Vector2(783,297),397)
	_label(menu,"OPPONENT",Vector2(783,357),11,CYAN)
	enemy_choice = _choice(menu,["KAIZEN","RYUZEN","AKIRA"],Vector2(783,377),188)
	enemy_choice.select(1)
	_label(menu,"DIFFICULTY",Vector2(991,357),11,CYAN)
	difficulty_choice = _choice(menu,["EASY","NORMAL","HARD"],Vector2(991,377),189)
	difficulty_choice.select(1)
	var info := _label(menu,"Choose your pace. Each fight opens with a countdown.\nTraining starts with a passive practice partner.",Vector2(784,443),12,MUTED)
	info.add_theme_constant_override("line_spacing",5)
	var launch := _button(menu,"ENTER THE ARENA   →",Rect2(782,515,398,62),CYAN,true)
	launch.add_theme_font_size_override("font_size",20)
	launch.pressed.connect(_launch_match)
	_button(menu,"SETTINGS & CONTROLS",Rect2(783,590,397,37),MUTED).pressed.connect(_open_settings)
	_label(menu,"BUILT FOR THE NEXT CHALLENGER.",Vector2(48,681),10,MUTED)
	_label(menu,"THREE WARRIORS   /   THREE FORMS",Vector2(955,681),10,MUTED)
	_select_character(0)

func _build_preview() -> void:
	_panel(menu,Rect2(326,106,397,430),Color(0.02,0.065,0.11,0.75),Color("28475b"))
	preview_container = SubViewportContainer.new()
	preview_container.position = Vector2(344,117)
	preview_container.size = Vector2(360,364)
	preview_container.stretch = true
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(preview_container)
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(360,364)
	preview_viewport.own_world_3d = true
	preview_viewport.transparent_bg = true
	preview_viewport.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("mobile") else Viewport.MSAA_2X
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	preview_container.add_child(preview_viewport)
	preview_stage = Node3D.new()
	preview_viewport.add_child(preview_stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018,0.045,0.075,0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a6bfd2")
	environment.ambient_light_energy = 0.4
	environment_node.environment = environment
	preview_stage.add_child(environment_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35,-35,0)
	key.light_color = Color("fff1db")
	key.light_energy = 0.9
	key.shadow_enabled = false
	preview_stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15,145,0)
	rim.light_color = Color("70d7ff")
	rim.light_energy = 0.35
	preview_stage.add_child(rim)
	var camera := Camera3D.new()
	camera.position = Vector3(0.3,1.25,-4.8)
	camera.fov = 31.0
	camera.near = 0.1
	camera.far = 30.0
	preview_stage.add_child(camera)
	camera.look_at(Vector3(0,1.15,0))
	camera.current = true
	preview_name = _label(menu,"",Vector2(346,485),20,WHITE)
	preview_title = _label(menu,"",Vector2(347,514),10,CYAN)

func _refresh_preview(index: int) -> void:
	if preview_stage == null or _preview_index == index:
		return
	_preview_index = index
	if is_instance_valid(preview_model):
		preview_stage.remove_child(preview_model)
		preview_model.queue_free()
	preview_model = WarriorVisual.new()
	preview_stage.add_child(preview_model)
	preview_model.setup(Roster.roster()[index])
	# Kaizen's taller swept hair and revised boots stay inside the preview while
	# his eyes/outfit gain useful pixels. Keep the other fighters' framing intact.
	var portrait_camera := preview_stage.find_children("*","Camera3D",true,false)[0] as Camera3D
	portrait_camera.position = Vector3(0.30,1.31,-4.35) if index == 0 else Vector3(0.3,1.25,-4.8)
	portrait_camera.look_at(Vector3(0,1.17 if index == 0 else 1.15,0))
	preview_name.text = CHARACTERS[index].name
	preview_title.text = CHARACTERS[index].title
	preview_title.add_theme_color_override("font_color",CHARACTERS[index].color)
	_preview_clock = 0.0
	_update_preview_visibility()

func _update_preview_visibility() -> void:
	if preview_viewport == null:
		return
	var active := mode == "menu" and settings_overlay == null and tutorial_overlay == null
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if is_instance_valid(preview_model):
		preview_model.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

func _select_character(index: int) -> void:
	selected_character = index
	for i in character_cards.size():
		var color: Color = CHARACTERS[i].color
		character_cards[i].add_theme_stylebox_override("normal",_style(Color(color,0.13) if i == index else Color("0b1928"),color if i == index else Color("263b4d"),2 if i == index else 1,3))
	character_description.text = CHARACTERS[index].description
	_refresh_preview(index)

func _launch_match() -> void:
	var modes := ["versus","training","arcade","survival"]
	start_match.emit({"player":selected_character,"enemy":enemy_choice.selected,"arena":arena_choice.selected,"difficulty":difficulty_choice.selected,"mode":modes[mode_choice.selected]})

func _make_bar(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := _style(Color(0.02,0.05,0.09,0.85),Color(color,0.25),1,2)
	var fill := _style(color,Color.TRANSPARENT,0,1)
	# Button padding made a requested 7px energy bar expand over the labels.
	# Bars need zero content margins; verified in actual viewport captures.
	for side in 4:
		background.set_content_margin(side,0.0)
		fill.set_content_margin(side,0.0)
	bar.add_theme_stylebox_override("background",background)
	bar.add_theme_stylebox_override("fill",fill)
	parent.add_child(bar)
	# Setting size before disabling the default percentage theme clamps it to
	# that theme's 27px minimum. Reapply after the new styles take effect.
	bar.set_deferred("size",rect.size)
	return bar

func _build_battle() -> void:
	battle = Control.new()
	battle.size = Vector2(1280,720)
	battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design.add_child(battle)
	_panel(battle,Rect2(25,23,455,110),Color(0.02,0.05,0.09,0.78),Color(0.25,0.48,0.60,0.3)).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel(battle,Rect2(800,23,455,110),Color(0.02,0.05,0.09,0.78),Color(0.50,0.25,0.55,0.3)).mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_name = _label(battle,"KAIZEN",Vector2(43,30),24,WHITE)
	enemy_name = _label(battle,"RYUZEN",Vector2(819,30),24,WHITE)
	player_form = _label(battle,"BASE",Vector2(345,40),11,CYAN)
	enemy_form = _label(battle,"BASE",Vector2(1120,40),11,GOLD)
	player_hp = _make_bar(battle,Rect2(43,68,419,22),CYAN)
	enemy_hp = _make_bar(battle,Rect2(819,68,419,22),Color("da9cff"))
	enemy_hp.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	player_energy = _make_bar(battle,Rect2(43,100,346,7),GOLD)
	enemy_energy = _make_bar(battle,Rect2(892,100,346,7),GOLD)
	enemy_energy.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	health_text = _label(battle,"1000 / 1000",Vector2(42,112),10,MUTED)
	enemy_health_text = _label(battle,"1000 / 1000",Vector2(1138,112),10,MUTED)
	time_label = _label(battle,"00:00",Vector2(588,28),31,WHITE,104)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_mode = _label(battle,"VERSUS AI",Vector2(548,71),10,GOLD,184)
	battle_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pause_button := _button(battle,"Ⅱ",Rect2(617,100,46,31),MUTED)
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(func(): pause_requested.emit())
	combo_label = _label(battle,"",Vector2(45,159),29,CYAN)
	status_label = _label(battle,"",Vector2(360,169),16,WHITE,560)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_outline_color",Color("06111d"))
	status_label.add_theme_constant_override("outline_size",5)
	countdown_label = _label(battle,"",Vector2(240,245),76,WHITE,800)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_color_override("font_outline_color",Color("06111d"))
	countdown_label.add_theme_constant_override("outline_size",9)
	battle.visible = false

func show_menu() -> void:
	_close_tutorial()
	mode = "menu"
	_clear_overlay()
	if settings_overlay != null:
		settings_overlay.queue_free()
		settings_overlay = null
	menu.show()
	battle.hide()
	touch.visible = false
	touch.enabled = false
	touch.reset()
	_update_preview_visibility()

func show_battle(config: Dictionary) -> void:
	_close_tutorial()
	get_viewport().gui_release_focus()
	mode = "battle"
	menu.hide()
	_clear_overlay()
	battle.show()
	touch.visible = bool(settings.show_touch)
	touch.enabled = bool(settings.show_touch)
	touch.reset()
	var label_mode := str(config.get("mode","versus")).to_upper()
	battle_mode.text = ("VERSUS AI" if label_mode == "VERSUS" else label_mode)+"  /  "+["EASY","NORMAL","HARD"][clampi(int(config.get("difficulty",1)),0,2)]
	_last_combo = 0
	combo_label.text = ""
	status_label.text = "TRAINING: unlimited practice · charge C · transform T · beam E" if label_mode == "TRAINING" else "FIGHT!"
	_notice_timer = 6.0
	set_countdown("")
	_update_preview_visibility()

func update_hud(player: Node, enemy: Node, combo: int, elapsed: float, status: String="") -> void:
	if player == null or enemy == null:
		return
	player_hp.max_value = player.max_hp
	player_hp.value = player.hp
	enemy_hp.max_value = enemy.max_hp
	enemy_hp.value = enemy.hp
	player_energy.max_value = player.max_energy
	player_energy.value = player.energy
	enemy_energy.max_value = enemy.max_energy
	enemy_energy.value = enemy.energy
	player_name.text = str(player.data.get("name","PLAYER")).to_upper()
	enemy_name.text = str(enemy.data.get("name","RIVAL")).to_upper()
	var forms := ["BASE","AWAKENED","ULTIMATE"]
	player_form.text = forms[clampi(player.form,0,2)]
	enemy_form.text = forms[clampi(enemy.form,0,2)]
	health_text.text = "%d / %d    ·    ENERGY %d" % [maxi(0,int(player.hp)),int(player.max_hp),int(player.energy)]
	enemy_health_text.text = "%d / %d" % [maxi(0,int(enemy.hp)),int(enemy.max_hp)]
	time_label.text = "%02d:%02d" % [int(elapsed)/60,int(elapsed)%60]
	if combo > 1:
		combo_label.text = "%02d  HITS" % combo
		_combo_timer = 1.8
		if combo != _last_combo:
			combo_label.scale = Vector2(1.12,1.12)
			_last_combo = combo
	if status != "":
		status_label.text = status
		_notice_timer = 2.5

func _process(delta: float) -> void:
	if mode == "menu" and settings_overlay == null and tutorial_overlay == null and is_instance_valid(preview_model):
		_preview_clock += delta
		preview_model.rotation.y = 0.10 + sin(_preview_clock*0.4)*0.12
		preview_model.animate(delta,"idle",0.0,0.0,0,false)
	if mode == "battle":
		_combo_timer = maxf(0,_combo_timer-delta)
		if _combo_timer == 0:
			combo_label.text = ""
			_last_combo = 0
		combo_label.scale = combo_label.scale.lerp(Vector2.ONE,minf(1,delta*12))
		_notice_timer = maxf(0,_notice_timer-delta)
		if _notice_timer == 0:
			status_label.text = ""

func _clear_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null

func _new_overlay() -> Control:
	_clear_overlay()
	overlay = Control.new()
	overlay.size = Vector2(1280,720)
	design.add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.015,0.03,0.06,0.82)
	dim.size = Vector2(1280,720)
	overlay.add_child(dim)
	return overlay

func show_pause() -> void:
	mode = "pause"
	_update_preview_visibility()
	touch.visible = false
	touch.enabled = false
	touch.reset()
	var layer := _new_overlay()
	_panel(layer,Rect2(400,126,480,474),Color("091a2b"),Color("31536a"))
	_label(layer,"TAKE A BREATH.",Vector2(438,159),33,WHITE)
	_label(layer,"BATTLE PAUSED",Vector2(440,210),12,CYAN)
	_button(layer,"RESUME BATTLE",Rect2(439,256,402,55),CYAN,true).pressed.connect(func(): resume_requested.emit())
	_button(layer,"SETTINGS & CONTROLS",Rect2(439,328,402,49),MUTED).pressed.connect(_open_settings)
	_button(layer,"RESTART MATCH",Rect2(439,394,402,49),MUTED).pressed.connect(func(): rematch_requested.emit())
	_button(layer,"RETURN TO MENU",Rect2(439,460,402,49),MUTED).pressed.connect(func(): menu_requested.emit())
	_label(layer,"Esc / Start to resume",Vector2(440,550),12,MUTED)

func hide_pause() -> void:
	_close_tutorial()
	get_viewport().gui_release_focus()
	if settings_overlay != null:
		settings_overlay.queue_free()
		settings_overlay = null
	_clear_overlay()
	mode = "battle"
	_update_preview_visibility()
	touch.visible = bool(settings.show_touch)
	touch.enabled = bool(settings.show_touch)

func show_result(won: bool, subtitle: String, can_continue: bool=false) -> void:
	mode = "result"
	set_countdown("")
	_update_preview_visibility()
	touch.enabled = false
	touch.visible = false
	touch.reset()
	var layer := _new_overlay()
	var accent := CYAN if won else GOLD
	_label(layer,"THE ARENA REMEMBERS.",Vector2(440,135),13,accent)
	var title := _label(layer,"VICTORY" if won else "DEFEAT",Vector2(256,180),80,WHITE,768)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var desc := _label(layer,subtitle,Vector2(250,298),18,MUTED,780)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if can_continue:
		_button(layer,"NEXT CHALLENGER   →",Rect2(420,380,440,58),accent,true).pressed.connect(func(): continue_requested.emit())
	else:
		_button(layer,"FIGHT AGAIN",Rect2(420,380,440,58),accent,true).pressed.connect(func(): rematch_requested.emit())
	_button(layer,"RETURN TO MENU",Rect2(420,456,440,47),MUTED).pressed.connect(func(): menu_requested.emit())
	_label(layer,"EVERY LIMIT IS A NEW BEGINNING.",Vector2(440,564),11,MUTED)

func _load_settings() -> void:
	var file := ConfigFile.new()
	if file.load(settings_path) == OK:
		for key in settings:
			settings[key] = file.get_value("settings",key,settings[key])
	settings.quality = clampi(int(settings.quality),0,2)
	settings.fps = 30 if int(settings.fps) == 30 else 60
	settings.button_scale = clampf(float(settings.button_scale),0.75,1.3)
	settings.sensitivity = clampf(float(settings.sensitivity),0.6,1.6)
	settings.volume = clampf(float(settings.volume),0,1)
	settings.resolution = clampi(int(settings.resolution),0,2)
	settings.touch_layout = clampi(int(settings.touch_layout),0,2)

func _save_settings() -> void:
	var file := ConfigFile.new()
	for key in settings:
		file.set_value("settings",key,settings[key])
	file.save(settings_path)
	if touch != null:
		touch.apply_settings(settings)
	if mode == "battle":
		touch.visible = bool(settings.show_touch)
		touch.enabled = bool(settings.show_touch)
		if not touch.enabled:
			touch.reset()
	settings_changed.emit(settings.duplicate())

func _open_settings() -> void:
	if settings_overlay != null:
		return
	settings_overlay = Control.new()
	settings_overlay.size = Vector2(1280,720)
	design.add_child(settings_overlay)
	_update_preview_visibility()
	var dim := ColorRect.new()
	dim.color = Color(0.01,0.025,0.05,0.98)
	dim.size = Vector2(1280,720)
	settings_overlay.add_child(dim)
	_label(settings_overlay,"TUNE YOUR BATTLE",Vector2(55,35),30,WHITE)
	_label(settings_overlay,"DISPLAY  /  COMBAT  /  TOUCH",Vector2(57,83),11,CYAN)
	_panel(settings_overlay,Rect2(55,118,1170,1),Color("2b4358"))
	_label(settings_overlay,"GRAPHICS & DISPLAY",Vector2(58,145),16,WHITE)
	_setting_choice("RENDER QUALITY",["LOW — MOBILE SAVER","MEDIUM — BALANCED","HIGH — FULL EFFECTS"],Vector2(58,185),"quality",int(settings.quality))
	var fps := _setting_choice("FRAME RATE",["30 FPS — BATTERY","60 FPS — RESPONSIVE"],Vector2(58,274),"fps",0 if settings.fps == 30 else 1,false)
	fps.item_selected.connect(func(index: int): settings.fps = 30 if index == 0 else 60; _save_settings())
	_setting_choice("WINDOW RESOLUTION",["1280 × 720","1600 × 900","1920 × 1080"],Vector2(58,363),"resolution",int(settings.resolution))
	_setting_toggle("FULLSCREEN",Vector2(54,451),"fullscreen")
	_setting_toggle("CAMERA SHAKE",Vector2(54,503),"shake")
	_slider("MASTER VOLUME",Vector2(58,571),0,1,settings.volume,func(value: float): settings.volume = value; _save_settings(),340)
	_panel(settings_overlay,Rect2(427,145,1,511),Color("2b4358"))
	_label(settings_overlay,"CONTROLS & PRACTICE",Vector2(462,145),16,WHITE)
	_setting_toggle("SHOW TOUCH CONTROLS",Vector2(458,184),"show_touch")
	_setting_choice("TOUCH LAYOUT",["COMPACT","STANDARD","WIDE"],Vector2(462,250),"touch_layout",int(settings.touch_layout))
	_slider("TOUCH BUTTON SIZE",Vector2(462,351),0.75,1.3,settings.button_scale,func(value: float): settings.button_scale = value; _save_settings(),340)
	_slider("JOYSTICK SENSITIVITY",Vector2(462,452),0.6,1.6,settings.sensitivity,func(value: float): settings.sensitivity = value; _save_settings(),340)
	_setting_toggle("TRAINING DUMMY ATTACKS",Vector2(458,554),"training_attack")
	_label(settings_overlay,"Off by default. Only changes Training Mode.",Vector2(464,605),11,MUTED)
	_panel(settings_overlay,Rect2(831,145,1,511),Color("2b4358"))
	_label(settings_overlay,"QUICK COMMANDS",Vector2(865,145),16,WHITE)
	var lines := [["MOVE / CAMERA","WASD / right mouse drag"],["STRIKE / HEAVY","J / K    ·    pad X / Y"],["BLAST / BEAM","L / E    ·    pad B / LS click"],["GUARD / VANISH","Q / X    ·    pad LB / A"],["DASH / CHARGE","Shift / C    ·    RB / D-pad down"],["RISE / FALL","Space / Ctrl    ·    RT / LT"],["TRANSFORM / LOCK","T / Tab    ·    D-pad up / RS click"]]
	for i in lines.size():
		_label(settings_overlay,lines[i][0],Vector2(866,190+i*51),10,CYAN)
		_label(settings_overlay,lines[i][1],Vector2(866,208+i*51),12,MUTED)
	_button(settings_overlay,"HOW TO PLAY",Rect2(865,580,332,45),MUTED).pressed.connect(_open_tutorial)
	_button(settings_overlay,"DONE   ✓",Rect2(1028,40,184,49),CYAN,true).pressed.connect(_close_settings)

func _close_settings() -> void:
	if settings_overlay != null:
		settings_overlay.queue_free()
		settings_overlay = null
	_update_preview_visibility()

func _setting_choice(caption: String, items: Array, pos: Vector2, key: String, selected: int, automatic: bool=true) -> OptionButton:
	_label(settings_overlay,caption,pos,11,CYAN)
	var choice := _choice(settings_overlay,items,pos+Vector2(0,24),340)
	choice.name = "Setting_"+key
	choice.select(selected)
	if automatic:
		choice.item_selected.connect(func(index: int): settings[key] = index; _save_settings())
	return choice

func _setting_toggle(caption: String, pos: Vector2, key: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = "Setting_"+key
	toggle.text = caption
	toggle.position = pos
	toggle.size = Vector2(345,40)
	toggle.button_pressed = bool(settings[key])
	toggle.add_theme_font_size_override("font_size",12)
	toggle.add_theme_color_override("font_color",WHITE)
	settings_overlay.add_child(toggle)
	toggle.toggled.connect(func(value: bool): settings[key] = value; _save_settings())
	return toggle

func _open_tutorial() -> void:
	if tutorial_overlay != null:
		return
	tutorial_overlay = Control.new()
	tutorial_overlay.size = Vector2(1280,720)
	design.add_child(tutorial_overlay)
	_update_preview_visibility()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.01,0.025,0.05,0.98)
	backdrop.size = Vector2(1280,720)
	tutorial_overlay.add_child(backdrop)
	_label(tutorial_overlay,"OWN THE SKY.",Vector2(65,48),40,WHITE)
	_label(tutorial_overlay,"A SHORT FIELD GUIDE",Vector2(67,108),12,CYAN)
	var lessons := [["01  FIND YOUR RHYTHM","Move with WASD / left stick / the touch joystick.\nTap J / X / Strike to chain four attacks.\nUse K / Y / Heavy to launch a rival into the air."],["02  TAKE THE FIGHT HIGHER","Hold Space / RT / Rise to fly; Ctrl / LT / Fall descends.\nDash toward a launched rival to extend your pursuit.\nTab / right stick / Lock keeps your opponent in focus."],["03  DEFENSE OPENS THE DOOR","Hold Q / LB / Guard to reduce incoming damage.\nRaise guard just before impact for a parry and counter.\nTap X / pad A / Vanish to evade; timing earns a counter."],["04  BUILD YOUR POWER","Hold C / D-pad down / Charge to recover energy.\nT / D-pad up / Awaken unlocks two stronger forms.\nBeam becomes your ultimate in final form at 85 energy."]]
	for i in lessons.size():
		var pos := Vector2(67+(i%2)*590,175+(i/2)*190)
		_panel(tutorial_overlay,Rect2(pos.x,pos.y,555,164),Color("0d2033"),Color("294359"))
		_label(tutorial_overlay,lessons[i][0],pos+Vector2(20,18),16,CYAN)
		var text := _label(tutorial_overlay,lessons[i][1],pos+Vector2(20,52),14,MUTED)
		text.add_theme_constant_override("line_spacing",7)
	_label(tutorial_overlay,"TOUCH COMBINATIONS: Charge + Blast = sphere   /   Guard + Blast = homing   /   Charge + Heavy = nova",Vector2(68,582),12,GOLD)
	_button(tutorial_overlay,"READY   →",Rect2(1001,637,211,47),CYAN,true).pressed.connect(_close_tutorial)

func _close_tutorial() -> void:
	if tutorial_overlay != null:
		tutorial_overlay.queue_free()
		tutorial_overlay = null
	_update_preview_visibility()

func set_countdown(text_value: String) -> void:
	if countdown_label == null:
		return
	countdown_label.text = text_value
	countdown_label.visible = not text_value.is_empty()
	countdown_label.add_theme_color_override("font_color",GOLD if text_value == "FIGHT" else WHITE)

func _slider(caption: String, pos: Vector2, minimum: float, maximum: float, value: float, callback: Callable, width: float=450) -> void:
	_label(settings_overlay,caption,pos,12,CYAN)
	var value_label := _label(settings_overlay,"%d%%" % int(value*100),pos+Vector2(width-70,0),12,WHITE)
	var slider := HSlider.new()
	slider.position = pos+Vector2(0,31)
	slider.size = Vector2(width,20)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = value
	slider.add_theme_stylebox_override("slider",_style(Color("1d3346"),Color.TRANSPARENT,0,2))
	slider.add_theme_stylebox_override("grabber_area",_style(CYAN,Color.TRANSPARENT,0,2))
	slider.add_theme_stylebox_override("grabber_area_highlight",_style(CYAN.lightened(0.2),Color.TRANSPARENT,0,2))
	settings_overlay.add_child(slider)
	slider.value_changed.connect(func(v: float): value_label.text = "%d%%" % int(v*100); callback.call(v))

func set_records(wins: int, best: int) -> void:
	if records_label != null:
		records_label.text = "CAREER WINS  %02d    /    SURVIVAL BEST  %02d" % [maxi(0,wins),maxi(0,best)]
