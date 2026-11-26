extends Control

const Core := preload("res://core.gd")
const Art := preload("res://mine_art.gd")
const ATLAS := preload("res://cut_gems.png")
const LOOP := [0,1,2,3,2,1]
var cargo: Dictionary = {}
var sample := false
var sample_elapsed := Core.CUT_SECONDS

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	set_process(is_visible_in_tree())

func _process(delta: float) -> void:
	if sample:
		sample_elapsed = minf(Core.CUT_SECONDS,sample_elapsed + delta)
	queue_redraw()

func reveal_fraction() -> float:
	if sample: return sample_elapsed / Core.CUT_SECONDS
	if cargo.get("cut",false): return 1.0
	var left: float = cargo.get("cut_left",0.0)
	return clampf(1.0-left/Core.CUT_SECONDS,0,1) if left>0.0 else 0.0

func _draw() -> void:
	if cargo.is_empty(): return
	var center := (size*0.5).round()
	var extent := floorf(minf(size.x,size.y)/64.0)*64.0
	if extent < 64: extent = minf(size.x,size.y)
	var offset := (center-Vector2.ONE*extent*0.5).round()
	var reveal := reveal_fraction()
	var rows := clampi(floori(64*reveal),0,64)
	if rows < 64:
		var shell := PackedVector2Array()
		for point: Vector2 in Art.ORE_SHAPE:
			shell.append(center+point*extent*0.38)
		var floor_y := offset.y+extent*(1.0-rows/64.0)
		var mask := PackedVector2Array([offset,offset+Vector2(extent,0),Vector2(offset.x+extent,floor_y),Vector2(offset.x,floor_y)])
		for contour in Geometry2D.intersect_polygons(shell,mask):
			draw_colored_polygon(contour,Color("8c9892"))
		var facet := PackedVector2Array([shell[0],shell[1],shell[2],center])
		for contour in Geometry2D.intersect_polygons(facet,mask):
			draw_colored_polygon(contour,Color("bdc3b6"))
	if rows > 0:
		var index := floori(Time.get_ticks_msec()/170.0) % LOOP.size()
		var x: int = LOOP[index]*64
		var y := (0 if Core.product_color(cargo) == "green" else 1)*64
		var draw_height := extent*rows/64.0
		var to := Rect2(offset+Vector2(0,extent-draw_height),Vector2(extent,draw_height))
		draw_texture_rect_region(ATLAS,to,Rect2(x,y+64-rows,64,rows))