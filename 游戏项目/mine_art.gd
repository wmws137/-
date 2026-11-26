extends Node2D

# World coordinates and tool positions come from the authoritative game state.
var frame: Dictionary = {}
var mine_state: Core
var label_font: Font
var contest_begin := -1
const PRODUCT_COLORS := [Color("e8b877"),Color("8fcbd2"),Color("cba2dc")]
const PRODUCT_NAMES := ["润滑油", "碎石图纸", "抛光布"]
const PRODUCT_USES := ["3 次重物速拉 ×2", "1 石块造尾矿机", "2 次宝石金值 ×1.5"]
const Core := preload("res://core.gd")
const PLAYER_COLORS = [Color("ff9965"), Color("68dbcf"), Color("c7b0ff"), Color("f4d973")]
const INK = Color("102628")
const ORE_SHAPE = [Vector2(-0.95, -0.16), Vector2(-0.57, -0.80), Vector2(0.14, -0.92), Vector2(0.81, -0.53), Vector2(0.96, 0.14), Vector2(0.39, 0.86), Vector2(-0.46, 0.88), Vector2(-0.91, 0.46)]
var seams: Array[PackedVector2Array] = []

func _ready() -> void:
	for layer in range(7):
		var line := PackedVector2Array()
		for index in range(31):
			var x := float(index * 32)
			var y := 166.0 + layer * 65.0 + sin(x * 0.008 + layer) * 11.0 + cos(x * 0.021 - layer * 0.6) * 5.0
			line.append(Vector2(x, y))
		seams.append(line)

func _draw() -> void:
	_draw_mine()
	_draw_lift()
	_draw_shop(45)
	_draw_shop(915)
	for ore in frame.get("ores", []):
		if not ore.get("gone", false):
			_draw_ore(ore)
	var hooks: Array = frame.get("hooks", [])
	_draw_supply_track(hooks)
	for index in hooks.size():
		var h: Dictionary = hooks[index]
		if h.mode=="aim":
			if mine_state == null or not mine_state.at_winch(index) or not frame.cargo[index].is_empty(): continue
			var nearest := mine_state.nearby_station(index)
			if nearest < 0: continue
			var aim := h.duplicate()
			aim.origin = Core.origins(hooks.size())[nearest]
			aim.tip = aim.origin + Vector2(sin(h.angle),cos(h.angle))*Core.REST_LENGTH
			_draw_hook(aim,PLAYER_COLORS[index])
		else:
			_draw_hook(h,PLAYER_COLORS[index])
	for p in hooks.size():
		var held: Dictionary = hooks[p]
		if held.mode == "back" and held.load >= 0:
			_draw_coupling(held,p)
	_draw_contest()
	var stations := Core.origins(hooks.size()) if not hooks.is_empty() else []
	for machine in stations.size():
		var origin: Vector2 = stations[machine]
		var operator := mine_state.station_user(machine) if mine_state!=null else -1
		var accent: Color = PLAYER_COLORS[operator] if operator>=0 else Color("a6b8ad")
		var facing := 1.0 if origin.x < 480.0 else -1.0
		_draw_station(origin,facing,accent)
		_draw_machine_label(machine,origin,operator,accent)
		if int(frame.drill[machine]) > 0:
			_draw_auto_drill(origin + Vector2(-77 * facing,-15),PLAYER_COLORS[machine],float(frame.drill_time[machine]))
	for p in hooks.size():
		_draw_miner(p)

func _draw_machine_label(machine: int, pos: Vector2, operator: int, accent: Color) -> void:
	var corner := pos + Vector2(-81,13)
	draw_rect(Rect2(corner, Vector2(162,19)),Color("162b2bea"))
	var font := label_font if label_font!=null else ThemeDB.fallback_font
	var who := "空闲" if operator<0 else "P%d 使用" % (operator+1)
	draw_string(font,corner+Vector2(0,15),"%d号 %s · %s" % [machine+1,Core.station_type(machine).name,who],HORIZONTAL_ALIGNMENT_CENTER,162,14,accent)

func _draw_shop(x: float) -> void:
	var font := label_font if label_font != null else ThemeDB.fallback_font
	draw_rect(Rect2(x-25,95,50,30),Color("364e43"))
	draw_colored_polygon(PackedVector2Array([Vector2(x-30,96),Vector2(x-24,84),Vector2(x+24,84),Vector2(x+30,96)]),Color("b29965"))
	draw_rect(Rect2(x-26,109,52,15),Color("183631"))
	draw_string(font,Vector2(x-24,121),"收购站",HORIZONTAL_ALIGNMENT_CENTER,48,13,Color("ffe1a3"))
	draw_line(Vector2(x-43,126),Vector2(x+43,126),Color("dcc185"),2,true)

func _draw_contest() -> void:
	var event: Dictionary = frame.get("last_contest",{})
	if contest_begin < 0 or event.is_empty() or frame.get("rules") != "party": return
	var progress := (Time.get_ticks_msec()-contest_begin)/520.0
	if progress >= 1.0: return
	var center: Vector2 = event.point
	var color := Color("ffd27b") if event.kind=="clash" else Color("ff9579")
	color.a = 1-progress
	for i in 8:
		var axis := Vector2.from_angle(i*TAU/8+0.18)
		var length := 19.0 if i%2==0 else 11.0
		draw_line(center+axis*(3+progress*17),center+axis*(length+progress*22),color,2.1,true)

func _draw_supply_track(hooks: Array) -> void:
	var crates: Array = frame.get("crates",[])
	if crates.is_empty(): return
	var ordering := hooks.any(func(h): return h.market)
	var rail_color := Color("c0b88a") if ordering else Color("7b8673")
	var font := label_font if label_font != null else ThemeDB.fallback_font
	var left: Vector2 = crates.front().pos
	var right: Vector2 = crates.back().pos
	draw_dashed_line(left-Vector2(39,-22),right+Vector2(39,22),rail_color,1.5,7.0,true,true)
	for i in crates.size():
		var crate: Dictionary = crates[i]
		var pos: Vector2 = crate.pos
		var held: int = crate.owner
		var available: bool = held < 0 and crate.regen <= 0
		var accent: Color = PRODUCT_COLORS[i]
		var point: Vector2 = hooks[held].tip if held >= 0 else pos
		if ordering:
			draw_arc(pos,Core.CRATE_RADIUS,0,TAU,32,accent if available else rail_color.darkened(0.3),1.7,true)
		if available or held >= 0:
			draw_rect(Rect2(point-Vector2(12,10), Vector2(24,20)),INK)
			draw_rect(Rect2(point-Vector2(11,9), Vector2(22,18)),accent,false,2.0,true)
			match i:
				0:
					draw_rect(Rect2(point-Vector2(4,4),Vector2(8,9)),accent)
					draw_line(point-Vector2(1,4),point-Vector2(-4,7),accent,2)
				1:
					draw_line(point-Vector2(6,4),point+Vector2(5,4),accent,2)
					draw_line(point+Vector2(-5,4),point+Vector2(5,4),accent,2)
				2:
					draw_colored_polygon(PackedVector2Array([point+Vector2(-6,0),point+Vector2(0,-5),point+Vector2(6,0),point+Vector2(0,5)]),accent)
		var heading := "%s %d金" % [PRODUCT_NAMES[i],Core.CRATE_PRICES[i]]
		if held >= 0: heading = "P%d 已订" % (held+1)
		elif not available: heading = "补货 %d秒" % ceili(crate.regen)
		if ordering or not available:
			var caption_width := 137 if ordering else 88
			var corner := pos + Vector2(-caption_width*0.5,22)
			draw_rect(Rect2(corner,Vector2(caption_width,39 if ordering else 20)),Color("142e2ff1"))
			draw_string(font,corner+Vector2(0,15),heading,HORIZONTAL_ALIGNMENT_CENTER,caption_width,14,accent)
			if ordering: draw_string(font,corner+Vector2(0,32),PRODUCT_USES[i],HORIZONTAL_ALIGNMENT_CENTER,caption_width,13,Color("d7e1d3"))

func _draw_auto_drill(pos: Vector2, accent: Color, cycle: float) -> void:
	draw_set_transform(pos,0,Vector2.ONE)
	var offset := 20.0 + sin(cycle * TAU * 1.7) * 3.0
	draw_line(Vector2(0, 0), Vector2(0, offset + 7), INK, 5, true)
	draw_line(Vector2(0, 5), Vector2(0, offset + 6), Color("c9bfa4"), 2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-4,offset),Vector2(4,offset),Vector2(0,offset+11)]),accent)
	draw_rect(Rect2(-9,-10,18,12),INK)
	draw_rect(Rect2(-7,-8,14,8),accent.darkened(0.38))
	draw_rect(Rect2(-6,-6,12.0 * clampf(cycle/5.0,0.0,1.0),3),accent)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

func _draw_lift() -> void:
	var stage: int = frame.get("project_stage",0)
	var running: bool = frame.get("project_launched",false)
	var x := 367.0 if frame.get("player_count",2)==3 else 480.0
	var floor_y := 126.0
	var steel := Color("c0b497")
	draw_rect(Rect2(x-29,floor_y-4,58,5),INK)
	if stage == 0:
		draw_line(Vector2(x-21,floor_y-6),Vector2(x+19,floor_y-13),steel,3,true)
		draw_line(Vector2(x-15,floor_y-9),Vector2(x+15,floor_y-7),Color("987d56"),3,true)
		return
	for side in [-1,1]:
		draw_line(Vector2(x+side*24,floor_y),Vector2(x+side*14,81),steel,4,true)
		draw_line(Vector2(x+side*19,104),Vector2(x-side*15,86),Color("849789"),2,true)
	draw_line(Vector2(x-19,81),Vector2(x+19,81),steel,5,true)
	if stage >= 2:
		draw_circle(Vector2(x,85),5,INK)
		draw_arc(Vector2(x,85),4,0,TAU,20,steel,2,true)
		var lift_y := 120.0 if not running else 109.0 + sin(Time.get_ticks_msec()*0.0015)*12.0
		draw_line(Vector2(x,87),Vector2(x,lift_y-8),Color("b8ab7e"),1.5,true)
		draw_rect(Rect2(x-9,lift_y-8,18,10),INK)
		draw_rect(Rect2(x-9,lift_y-8,18,10),Color("f2c474"),false,1.5,true)
		draw_line(Vector2(x,lift_y-8),Vector2(x,lift_y+2),steel,1,true)
	if stage >= 3:
		draw_circle(Vector2(x-15,79),3.4,Color("86ffe0") if running else Color("ffc668"),true,-1,true)

func _draw_mine() -> void:
	draw_rect(Rect2(0, 0, 960, 600), Color("283e3b"))
	var palette := [Color("354a42"), Color("30463f"), Color("2e423e"), Color("2b3c39"), Color("273836"), Color("233432"), Color("202f2e")]
	var biome: String = frame.get("map_id","mine")
	if biome == "lake":
		palette = [Color("347479"),Color("2d696f"),Color("285e66"),Color("24555e"),Color("214d56"),Color("1c444e"),Color("1a3d46")]
	elif biome == "burrow":
		palette = [Color("795c43"),Color("70553f"),Color("684f3c"),Color("604937"),Color("584334"),Color("523f31"),Color("49382c")]
	for i in range(seams.size()):
		var border := seams[i].duplicate()
		border.append(Vector2(960, 640))
		border.append(Vector2(0, 640))
		draw_colored_polygon(border, palette[i])
		draw_polyline(seams[i], Color("68807165"), 1.5, true)
	if biome == "lake":
		for i in 16:
			var seed_pos := Vector2(26+(i*197)%904,237+(i*83)%302)
			draw_arc(seed_pos,2+i%4,0,TAU,12,Color("98d6d777"),1.3,true)
			draw_circle(seed_pos+Vector2(3,-9),1.4,Color("bddfdc77"))
		for i in 13:
			var x := 19.0+i*77
			draw_polyline(PackedVector2Array([Vector2(x,600),Vector2(x-6,581),Vector2(x+3,566),Vector2(x,550+i%4*5)]),Color("568d77"),4,true)
	elif biome == "burrow":
		for i in 5:
			var x := 47+i*208
			var y := 230+(i*71)%243
			draw_arc(Vector2(x,y),24,PI,TAU,16,Color("9e7958"),4,true)
			draw_circle(Vector2(x,y),20,Color("453628"))
			draw_rect(Rect2(x-22,y+8,44,12),Color("755940"))
	# Fissures follow the strata. Keep the central playfield quiet beneath the gold.
	for i in range(24):
		var x := float((i * 173 + 27) % 933)
		var y := float(181 + (i * 59) % 389)
		var p := Vector2(x, y)
		draw_polyline(PackedVector2Array([p, p + Vector2(11, -3), p + Vector2(19, 0), p + Vector2(33, -5)]), Color("82918442"), 1.2, true)
	for x in [18, 941]:
		draw_line(Vector2(x, 165), Vector2(x, 585), Color("81958566"), 1)
		for tick in range(17):
			var width := 8 if tick % 4 == 0 else 4
			var side := 1 if x == 18 else -1
			draw_line(Vector2(x, 169 + tick * 25), Vector2(x + side * width, 169 + tick * 25), Color("81958577"), 1)
	# Riveted bridge with a continuous rail across both players' stations.
	draw_rect(Rect2(0, 127, 960, 17), Color("172d2d"))
	for x in range(0, 960, 43):
		draw_line(Vector2(x, 142), Vector2(x + 16, 130), Color("51635b"), 3, true)
		draw_circle(Vector2(x + 8, 132), 1.7, Color("c0a775"), true, -1, true)
	draw_rect(Rect2(0, 126, 960, 3), Color("99a58e"))
	draw_rect(Rect2(0, 144, 960, 2), Color("101f22"))

func _draw_station(origin: Vector2, facing: float, accent: Color) -> void:
	# Mirroring the whole station puts both miners facing the central mine seam.
	draw_set_transform(origin, 0, Vector2(facing, 1))
	draw_rect(Rect2(-32,-21,64,3),Color(accent,0.65))
	draw_rect(Rect2(-60, -28, 64, 6), Color("9c8f6d"))
	# Steel derrick and pulley.
	draw_polyline(PackedVector2Array([Vector2(-23,-22), Vector2(-8,-48), Vector2(4,-8)]), INK, 6, true)
	draw_polyline(PackedVector2Array([Vector2(-23,-22), Vector2(-8,-48), Vector2(4,-8)]), Color("c4b893"), 2, true)
	draw_line(Vector2(-21,-25),Vector2(0,-17), Color("b3a887"), 2, true)
	draw_line(Vector2(-7,-46), Vector2(0,0), Color("ebc47d"), 1.5, true)
	draw_circle(Vector2.ZERO, 7, INK, true, -1, true)
	draw_arc(Vector2.ZERO, 5.2, 0, TAU, 20, accent, 2.2, true)
	draw_circle(Vector2.ZERO, 1.7, Color("f9dfac"))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_miner(p: int) -> void:
	var accent: Color = PLAYER_COLORS[p]
	var step: int = frame.move_dir[p]
	var world_x: float = frame.ground_x[p]
	var facing := float(step) if step!=0 else (1.0 if world_x < 480 else -1.0)
	var bob := sin(Time.get_ticks_msec()*0.021)*1.6 if step!=0 else 0.0
	var held: Dictionary = frame.cargo[p]
	draw_set_transform(Vector2(world_x+40*facing,151+bob),0,Vector2(facing,1))
	# Boots, work jacket, face, hardhat and helmet lamp.
	draw_line(Vector2(-44,-32), Vector2(-47,-25), INK, 6, true)
	draw_line(Vector2(-37,-33), Vector2(-34,-25), INK, 6, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-49,-32),Vector2(-47,-44),Vector2(-40,-48),Vector2(-33,-43),Vector2(-32,-32)]), accent.darkened(0.28))
	draw_line(Vector2(-46,-36),Vector2(-34,-36),accent.lightened(0.20),2,true)
	draw_circle(Vector2(-40,-48), 6.3, Color("d9af7c"), true, -1, true)
	draw_arc(Vector2(-41,-50), 6.3, PI, TAU, 12, accent, 4, true)
	draw_line(Vector2(-49,-50), Vector2(-31,-50), accent, 3, true)
	draw_circle(Vector2(-34,-51), 2.1, Color("fff3ba"), true, -1, true)
	draw_circle(Vector2(-36,-47), 1, INK)
	draw_line(Vector2(-35,-40), Vector2(-28,-36), accent, 3, true)
	draw_circle(Vector2(-26,-35), 2.2, Color("dfbd8d"))
	draw_line(Vector2(-27,-33), Vector2(-25,-27), Color("c8b28e"), 2, true)
	if not held.is_empty():
		var carrying := Color("82938a") if not held.opened else Color("efc774")
		draw_colored_polygon(PackedVector2Array([Vector2(-64,-41),Vector2(-58,-54),Vector2(-48,-53),Vector2(-43,-40),Vector2(-52,-32)]),carrying)
		draw_line(Vector2(-60,-45),Vector2(-50,-48),carrying.lightened(0.4),1.5,true)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	var font := label_font if label_font!=null else ThemeDB.fallback_font
	draw_string(font,Vector2(clampf(world_x-14,2,930),94),"P%d"%(p+1),HORIZONTAL_ALIGNMENT_CENTER,28,12,accent)

func _draw_ore(ore: Dictionary) -> void:
	var pos: Vector2 = ore["pos"]
	var radius: float = ore["radius"]
	var kind: String = ore["kind"]
	var owner_index: int = ore["owner"]
	if frame.get("map_id","mine") == "mine":
		_draw_mineral(pos,radius,int(ore.value))
	else:
		_draw_animal(ore)
	if owner_index >= 0 and owner_index < PLAYER_COLORS.size():
		draw_arc(pos,radius+3,PI*1.10,PI*1.90,18,PLAYER_COLORS[owner_index],2.5,true)
	if frame.map_id == "mine": return
	var amount := str(Core.delivery_value(ore.value,frame.level))
	var font := ThemeDB.fallback_font
	var label_width := font.get_string_size(amount,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x + 6.0
	var label_x := clampf(pos.x + radius * 0.54,3.0,957.0 - label_width)
	var label_y := minf(pos.y+radius*0.54,573.0)
	draw_rect(Rect2(label_x,label_y,label_width,17),Color("192b29e1"))
	draw_string(font,Vector2(label_x+3,label_y+13.0),amount,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("e1ceaa"))
	if owner_index >= 0 and owner_index < PLAYER_COLORS.size():
		draw_arc(pos, radius + 3, PI * 1.10, PI * 1.90, 18, PLAYER_COLORS[owner_index], 2.5, true)

func _draw_mineral(pos: Vector2, radius: float, value: int) -> void:
	var body := Color("85918a")
	var top := Color("b1b6a8")
	var bottom := Color("556862")
	var points := PackedVector2Array()
	for vertex: Vector2 in ORE_SHAPE:
		points.append(pos + vertex.rotated(0.13*sin(pos.x)) * radius)
	draw_colored_polygon(points, body)
	var center := pos + Vector2(-0.16, -0.15) * radius
	draw_colored_polygon(PackedVector2Array([points[0],points[1],points[2],center]), top)
	draw_colored_polygon(PackedVector2Array([center, points[3], points[4],points[5]]), bottom.lightened(0.10))
	draw_colored_polygon(PackedVector2Array([center,points[5],points[6],points[7]]), bottom)
	points.append(points[0])
	draw_polyline(points, INK, 2, true)
	draw_line(points[1], points[2], top.lightened(0.15), 2, true)
	var glitter := 3 if value >= 85 else (2 if value >= 45 else (1 if value >= 12 else 0))
	for n in glitter:
		var mark := pos+Vector2(-0.36+n*0.32,-0.30 if n%2==0 else -0.52)*radius
		var shine := 2.0+absf(sin(Time.get_ticks_msec()*0.0025+float(pos.x)+n))*2.0
		draw_line(mark-Vector2(shine,0),mark+Vector2(shine,0),Color("ffe0a2"),1.4,true)
		draw_line(mark-Vector2(0,shine),mark+Vector2(0,shine),Color("fff4c7"),1.4,true)

func _draw_animal(target: Dictionary) -> void:
	var kind: String = target.kind
	var fish: bool = frame.map_id == "lake"
	var colors := {"silverfish":Color("bde1dc"),"carp":Color("e28f69"),"goldfin":Color("ffd475"),"graymouse":Color("b7afa6"),"mole":Color("94695e"),"goldback":Color("dfbb73")}
	var skin: Color = colors.get(kind,Color.WHITE)
	var r: float = target.radius
	var pulse := sin(Time.get_ticks_msec()*0.008+float(target.home.x))*0.14 if target.owner<0 else 0.0
	draw_set_transform(target.pos,0,Vector2(float(target.get("facing",1))*r,r))
	if fish:
		draw_colored_polygon(PackedVector2Array([Vector2(-0.48,0),Vector2(-1.24,-0.54+pulse),Vector2(-1.12,0.55+pulse)]), skin.darkened(0.18))
		draw_colored_polygon(PackedVector2Array([Vector2(-0.8,0),Vector2(-0.39,-0.43),Vector2(0.18,-0.53),Vector2(0.87,-0.16),Vector2(1.04,0.05),Vector2(0.61,0.34),Vector2(-0.15,0.43)]),skin)
		draw_line(Vector2(-0.38,0.22),Vector2(0.67,0.12),skin.lightened(0.35),0.1,true)
		if kind == "carp":
			draw_arc(Vector2(0.10,0.05),0.25,-1.55,1.45,10,skin.darkened(0.38),0.1,true)
			draw_line(Vector2(0.85,0.15),Vector2(1.13,0.36),skin,0.074,true)
		elif kind == "goldfin":
			draw_colored_polygon(PackedVector2Array([Vector2(-0.49,-0.25),Vector2(-0.20,-0.93),Vector2(0.20,-0.41)]),skin.lightened(0.25))
	else:
		draw_polyline(PackedVector2Array([Vector2(-0.55,0.15),Vector2(-1.18,0.25+pulse),Vector2(-1.59,-0.08+pulse)]),Color("cf9e90"),0.12,true)
		draw_colored_polygon(PackedVector2Array([Vector2(-0.86,0.11),Vector2(-0.72,-0.36),Vector2(-0.18,-0.65),Vector2(0.38,-0.55),Vector2(0.72,-0.29),Vector2(1.14,0.07),Vector2(0.62,0.37),Vector2(-0.44,0.41)]),skin)
		draw_circle(Vector2(0.28,-0.46),0.26 if kind!="mole" else 0.13,skin.lightened(0.25),true,-1,true)
		draw_circle(Vector2(1.04,0.04),0.105,Color("d9a39a"),true,-1,true)
		draw_line(Vector2(-0.36,0.35),Vector2(-0.55,0.52+pulse),INK,0.12,true)
		draw_line(Vector2(0.34,0.31),Vector2(0.56,0.50-pulse),INK,0.12,true)
		if kind == "mole": draw_line(Vector2(0.35,0.15),Vector2(0.75,0.28),Color("e3b6a3"),0.28,true)
		elif kind == "goldback": draw_line(Vector2(-0.56,-0.28),Vector2(0.12,-0.46),Color("ffe59f"),0.17,true)
	draw_circle(Vector2(0.57,-0.14),0.12,INK,true,-1,true)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

func _draw_coupling(hook: Dictionary, seat: int) -> void:
	var tip: Vector2 = hook.tip
	var helper: int = hook.get("helper",-1)
	var owner_color: Color = PLAYER_COLORS[seat]
	var font := label_font if label_font != null else ThemeDB.fallback_font
	if helper < 0:
		if hook.market: return
		var party: bool = frame.get("rules","coop") == "party"
		var near_dock := tip.distance_to(hook.origin) <= 50
		var locked: bool = party and frame.ores[hook.load].get("stolen",false)
		if near_dock or locked:
			if party:
				var mark := tip+Vector2(11,-12)
				draw_colored_polygon(PackedVector2Array([mark+Vector2(-5,-4),mark+Vector2(5,-4),mark+Vector2(4,2),mark+Vector2(0,6),mark+Vector2(-4,2)]),Color("c5e9cc"))
			return
		if party: owner_color = Color("ff985d")
		for quarter in 4:
			var start_angle := quarter * PI/2 + 0.13
			draw_arc(tip,20,start_angle,start_angle+1.29,14,INK,3.4,true)
			draw_arc(tip,20,start_angle,start_angle+1.29,14,owner_color.lightened(0.35),1.65,true)
		return
	var buddy_color: Color = PLAYER_COLORS[helper]
	draw_arc(tip,11,-PI,0,16,owner_color,3,true)
	draw_arc(tip,11,0,PI,16,buddy_color,3,true)
	var corner := Vector2(clampf(tip.x-42,3,871),clampf(tip.y-42,153,540))
	draw_rect(Rect2(corner,Vector2(86,19)),Color("132a2aed"))
	draw_string(font,corner+Vector2(0,15),"P%d + P%d 合拉" % [seat+1,helper+1],HORIZONTAL_ALIGNMENT_CENTER,86,13,Color("fff3bd"))

func _draw_hook(hook: Dictionary, accent: Color) -> void:
	var origin: Vector2 = hook["origin"]
	var angle: float = hook["angle"]
	var direction := Vector2(sin(angle), cos(angle))
	var tip: Vector2 = hook["tip"]
	if hook.mode == "assist" or (hook.mode == "back" and hook.load < 0):
		direction = (tip-origin).normalized()
	if hook["mode"] == "aim":
		for i in range(4):
			draw_circle(tip + direction * (14.0 + i * 9), 1.35, Color(accent, 0.55 - i * 0.08), true, -1, true)
	draw_line(origin, tip, INK, 4.5, true)
	draw_line(origin, tip, accent, 1.9, true)
	var side := direction.orthogonal()
	for sign_value in [-1.0, 1.0]:
		var jaw := PackedVector2Array([tip - direction * 5.0, tip + side * 5.6 * sign_value, tip + direction * 5.0 + side * 5.0 * sign_value, tip + direction * 7.2 + side * 2.0 * sign_value])
		draw_polyline(jaw, INK, 4.2, true)
		draw_polyline(jaw, accent.lightened(0.28), 2, true)
	draw_circle(tip - direction * 4.5, 2.7, accent, true, -1, true)