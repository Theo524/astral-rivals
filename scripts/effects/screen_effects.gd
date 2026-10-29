extends CanvasLayer
## Lightweight anime impact accents; Canvas drawing, no screen-copy shaders.
## Camera and combat remain authoritative. This layer never captures input.
var quality: int = 1
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE
var _speed: float = 0.0
var _speed_target: float = 0.0
var _clock: float = 0.0
var _canvas: Control
var _was_active: bool = false

class Overlay extends Control:
	var effects: Node
	func _draw() -> void:
		if effects != null:
			effects.draw_overlay(self)

func _ready() -> void:
	layer = 3
	_canvas = Overlay.new()
	_canvas.effects = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)

func set_quality(level: int) -> void:
	quality = clampi(level,0,2)

func impact(strength: float, color: Color = Color.WHITE) -> void:
	_flash = maxf(_flash,clampf(strength,0.0,1.7))
	_flash_color = color

func pursuit(speed: float) -> void:
	_speed_target = clampf((speed-14.0)/26.0,0.0,1.0)

func _process(delta: float) -> void:
	_clock += delta
	_flash = maxf(0.0,_flash-delta*8.0)
	_speed = lerpf(_speed,_speed_target,1.0-exp(-delta*9.0))
	_speed_target = maxf(0.0,_speed_target-delta*2.0)
	if _flash > 0.0 or _speed > 0.01:
		_was_active = true
		_canvas.queue_redraw()
	elif _was_active:
		_was_active = false
		_canvas.queue_redraw()

func draw_overlay(canvas: Control) -> void:
	var size: Vector2 = canvas.get_viewport_rect().size
	var center := size*Vector2(0.5,0.47)
	if _flash > 0.0:
		var alpha := minf(_flash*0.055,0.085)
		canvas.draw_rect(Rect2(Vector2.ZERO,size),Color(_flash_color,alpha))
	var intensity := maxf(_speed,_flash*0.33)
	if intensity < 0.01:
		return
	var count: int = [8,16,28][quality]
	for i in count:
		var angle := float(i)*TAU/float(count)+sin(float(i)*8.13)*0.1
		var direction := Vector2(cos(angle),sin(angle))
		var phase := fmod(_clock*(2.0+float(i%3)*0.4)+float(i)*0.618,1.0)
		var edge := Vector2(direction.x*size.x*0.69,direction.y*size.y*0.74)
		var start := center+edge*(0.75+phase*0.08)
		var finish := center+edge*(0.99+phase*0.12)
		canvas.draw_line(start,finish,Color(0.82,0.94,1.0,intensity*(0.14+phase*0.1)),1.0+float(i%3)*0.5,true)
	# Short ink accents stay around the screen edge, preserving the fighters.
	if _flash > 0.45:
		var ink_alpha := minf((_flash-0.45)*0.08,0.09)
		canvas.draw_rect(Rect2(0,0,size.x,7),Color(0.015,0.025,0.05,ink_alpha))
		canvas.draw_rect(Rect2(0,size.y-7,size.x,7),Color(0.015,0.025,0.05,ink_alpha))
