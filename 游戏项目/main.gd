extends Node2D

const Core := preload("res://core.gd")
const Room := preload("res://room.gd")
const Art := preload("res://mine_art.gd")
const GemView := preload("res://gem_view.gd")
var product_frames: Array[Control] = []
var sample_panel: Panel
const INK := Color("182c2c")
const PAPER := Color("f1e9d3")
const GOLD := Color("ffce73")
const COLORS := [Color("ff9965"), Color("68dbcf"),Color("c7b0ff"),Color("f4d973")]
const WALK_KEYS := [[KEY_A,KEY_D],[KEY_LEFT,KEY_RIGHT],[KEY_G,KEY_H],[KEY_K,KEY_L]]
const WALK_HINTS := ["A/D","←/→","G/H","K/L"]
var walk_held: Array = [[],[],[],[]]
const CONTRACT_TERMS := ["未开原石", "任意已开原石", "已开且中品或上品"]
const GRADE_NAMES := ["低品","中品","上品"]
var trade_views: Array[Control] = []
var trade_switch: Array[Button] = []
var trade_contract: Array[Label] = []
var trade_quote: Array[Label] = []
var cutter_buttons: Array[Button] = []
var trade_receipts: Array[Label] = []
var trade_alerts: Array[Label] = []
var trade_last: Array = []
var appraisal_seen: Array = []
var sale_until: Array = []
var auto_trading: Array = []
var ground_labels: Array[Label] = []
var inspection: Array[Button] = []
var lamp_status: Array[Label] = []
var appraisal: Array[Button] = []
var sale: Array[Button] = []
const ACTIONS := ["winch", "drill"]
const SAVE_EVERY := 3.0
const DEFAULT_KEYS := [KEY_SPACE, KEY_ENTER, KEY_F, KEY_J]
const PREFS := "user://mine_controls.cfg"
var selected_count := 2
var active_count := 2
var fire_keys: Array = DEFAULT_KEYS.duplicate()
var capture_seat := -1
var feedback: Label
var address_draft := ""
var lobby_count: Label
var state := Core.new()
var preview := Core.new()
var room := Room.new()
var art := Art.new()
var ui := Control.new()
var session := "menu"
var shown := ""
var notice := ""
var broadcast_time := 0.0
var save_elapsed := 0.0
var save_generation := 0
var save_failed := false
var address_box: LineEdit
var personal_panels: Array[Control] = []
var personal_tabs: Array[Button] = []
var open_seat := -1
var wallets: Array[Label] = []
var rate_labels: Array[Label] = []
var gear: Array[Button] = []
const MAP_IDS := ["mine","lake","burrow"]
const MAP_NAMES := ["矿井","湖泊","鼠穴"]
var map_buttons: Array[Button] = []
var map_notice: Label
var rules_button: Button
var last_contest_id := -1
var contest_expiry := 0
var gift_popup: Panel = null
var gift_amount: LineEdit
var gift_target: OptionButton
var gift_title: Label
var gift_hint: Label
var gift_send: Button
var gift_sender := -1
var gift_pending := false
var last_gift_id := -1
var gift_expiry := 0
const GIFT_ERRORS := {"amount":"请输入有效的正整数。", "funds":"钱包余额不足。", "self":"请选择另一名矿工。", "recipient":"收款人无效。", "overflow":"收款钱包已满。", "sender":"当前席位无法赠金。"}
var last_assist_id := -1
var assist_expiry := 0
var last_wildlife: Array = []
var market_buttons: Array[Button] = []
var inventory_labels: Array[Label] = []
const RECEIPT := {"funds":"余额不足", "reserved":"已付款 · 回收中", "miss":"未钩中补给", "oil":"油已到货", "blueprint":"图纸已到货", "polish":"抛光布已到货"}
var project_actions: Array[Button] = []
var opening_button: Button
var opening_panel: Panel
var opening_seen := false
var opening_view_key := ""
var project_label: Label
var last_earned: Array = []
var depth_label: Label
var depth_bar: ColorRect
var production_label: Label


func _ready() -> void:
	load_controls()
	preview.start(selected_count)
	art.name = "Mine"
	room.name = "Room"
	add_child(art)
	add_child(room)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(ui)
	ui.size = Vector2(960,600)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Noto Sans CJK SC", "PingFang SC", "Microsoft YaHei", "Arial"])
	theme.default_font = font
	ui.theme = theme
	art.label_font = font
	room.paired.connect(on_paired)
	room.lobby_changed.connect(update_lobby)
	room.connection_lost.connect(to_menu)
	room.action_received.connect(on_remote_action)
	room.frame_received.connect(on_frame)
	room.gift_requested.connect(on_gift_request)
	room.gift_result.connect(on_gift_result)
	get_tree().auto_accept_quit = false
	refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready(): release_walk()
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_mine()
		get_tree().quit()

func save_file(slot: int) -> String:
	var group := session if active_count == 2 else "%s_%dp" % [session,active_count]
	return "user://mine_%s_v1_%d.dat" % [group, slot]

func read_slot(slot: int) -> Dictionary:
	var path := save_file(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 12 or file.get_length() > 262144:
		return {}
	var envelope: Variant = file.get_var(false)
	if not (envelope is Dictionary) or envelope.get("schema") != 1 or typeof(envelope.get("generation")) != TYPE_INT or typeof(envelope.get("mine")) != TYPE_DICTIONARY:
		return {}
	return envelope

func begin_mine() -> void:
	save_generation = 0
	save_elapsed = 0
	save_failed = false
	var candidates := [read_slot(0), read_slot(1)]
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return a.get("generation", -1) > b.get("generation", -1))
	for record: Dictionary in candidates:
		if not record.is_empty() and record.mine.get("player_count",2) == active_count and state.restore(record.mine):
			save_generation = record.generation
			return
	state.start(active_count)

func save_mine() -> void:
	if session not in ["local","host"] or state.frame.is_empty():
		return
	# Alternating complete snapshots preserves the previous slot if a write is interrupted.
	var next := save_generation + 1
	var file := FileAccess.open(save_file(next % 2), FileAccess.WRITE)
	if file == null:
		save_failed = true
		return
	file.store_var({"schema":1,"generation":next,"mine":state.frame}, false)
	file.flush()
	save_failed = file.get_error() != OK
	file.close()
	if not save_failed:
		save_generation = next
		save_elapsed = 0.0

func to_menu(message: String = "") -> void:
	close_opening()
	release_walk()
	close_gift()
	save_mine()
	room.leave_room()
	capture_seat = -1
	notice = message
	if save_failed:
		notice += " 矿场存档写入失败。"
	session = "menu"
	state.frame = {}
	shown = ""
	refresh()

func local_game() -> void:
	room.leave_room()
	session = "local"
	active_count = selected_count
	capture_seat = -1
	begin_mine()
	refresh()

func host_game() -> void:
	capture_seat = -1
	active_count = selected_count
	var err := room.host_room(active_count)
	if err != OK:
		to_menu("建房失败，请检查端口是否被占用。")
		return
	session = "host"
	state.frame = {}
	refresh()

func join_game(address: String) -> void:
	capture_seat = -1
	var err := room.join_room(address)
	if err != OK:
		to_menu("请输入有效的房主 IP 地址。")
		return
	session = "client"
	state.frame = {}
	refresh()

func on_paired() -> void:
	if session == "host":
		begin_mine()
		room.publish(state.frame)
	refresh()

func on_remote_action(seat: int, action: String, _generation: int) -> void:
	if session == "host" and not state.frame.is_empty():
		state.act(seat, action)
		room.publish(state.frame)
		refresh()

func on_frame(incoming: Dictionary) -> void:
	if session == "client":
		active_count = incoming.player_count
		state.frame = incoming
		refresh()

func controls(player: int) -> bool:
	return session == "local" or player == room.local_seat

func act(player: int, action: String) -> void:
	if state.frame.is_empty() or not controls(player):
		return
	if session == "client":
		room.send_action(action, 1)
	else:
		state.act(player, action)
		if session == "host":
			room.publish(state.frame)
	refresh()

func close_gift() -> void:
	if is_instance_valid(gift_popup):
		gift_popup.hide()
		gift_popup.queue_free()
	gift_popup = null
	gift_sender = -1
	gift_pending = false

func open_gift(p: int) -> void:
	if state.frame.is_empty() or not controls(p) or is_instance_valid(gift_popup): return
	release_walk()
	gift_sender = p
	gift_popup = Panel.new()
	gift_popup.z_index = 5
	gift_popup.position = Vector2.ZERO
	gift_popup.size = Vector2(960,600)
	gift_popup.add_theme_stylebox_override("panel", box_style(Color("0c1616bd"),Color.TRANSPARENT))
	ui.add_child(gift_popup)
	var screen := Panel.new()
	screen.position = Vector2(285,175)
	screen.size = Vector2(390,252)
	screen.add_theme_stylebox_override("panel",box_style(INK,COLORS[p]))
	gift_popup.add_child(screen)
	var layout := VBoxContainer.new()
	layout.position = Vector2(18,12)
	layout.size = Vector2(354,228)
	layout.add_theme_constant_override("separation",5)
	screen.add_child(layout)
	gift_title = Label.new()
	gift_title.text = "P%d 赠金　钱包 %d 金" % [p+1,state.frame.wallet[p]]
	gift_title.add_theme_color_override("font_color",COLORS[p])
	layout.add_child(gift_title)
	gift_target = OptionButton.new()
	for other in active_count:
		if other!=p: gift_target.add_item("收款矿工　P%d" % (other+1),other)
	layout.add_child(gift_target)
	gift_amount = LineEdit.new()
	gift_amount.placeholder_text = "输入赠送金额（正整数）"
	gift_amount.max_length = 19
	layout.add_child(gift_amount)
	gift_hint = Label.new()
	gift_hint.text = "选择矿友、填写金额，然后点击确认赠送。"
	layout.add_child(gift_hint)
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	gift_send = Button.new()
	gift_send.text = "确认赠送"
	gift_send.pressed.connect(submit_gift)
	actions.add_child(gift_send)
	var cancel := Button.new()
	cancel.text = "关闭"
	cancel.pressed.connect(func():
		if not gift_pending: close_gift())
	actions.add_child(cancel)
	gift_amount.grab_focus()

func submit_gift() -> void:
	if gift_pending or not is_instance_valid(gift_popup): return
	var raw := gift_amount.text.strip_edges()
	var amount := raw.to_int()
	if amount <= 0 or str(amount)!=raw.lstrip("0"):
		gift_hint.text = GIFT_ERRORS.amount
		return
	var recipient := gift_target.get_selected_id()
	if session == "client":
		gift_pending = room.send_gift(recipient,amount)
		gift_send.disabled = gift_pending
		gift_amount.editable = not gift_pending
		gift_target.disabled = gift_pending
		gift_hint.text = "等待房主结算…" if gift_pending else "发送失败，请检查连接。"
	else:
		on_gift_result(state.gift(gift_sender,recipient,amount))
		if session == "host": room.publish(state.frame)
		refresh()

func on_gift_request(seat: int, recipient: int, amount: int) -> void:
	if session == "host":
		var status := state.gift(seat,recipient,amount)
		room.reply_gift(seat,status)
		room.publish(state.frame)
		refresh()

func on_gift_result(status: String) -> void:
	gift_pending = false
	if not is_instance_valid(gift_popup): return
	if status == "ok":
		gift_hint.text = "已向 P%d 赠送 %s 金。" % [gift_target.get_selected_id()+1,gift_amount.text.strip_edges()]
		gift_send.disabled = true
		gift_target.disabled = true
		gift_amount.editable = false
	else:
		gift_send.disabled = false
		gift_target.disabled = false
		gift_amount.editable = true
		gift_hint.text = GIFT_ERRORS.get(status,"赠送失败，请重试。")

func project_act(p: int) -> void:
	if not state.frame.is_empty() and not state.frame.project_launched:
		act(p, "launch" if state.frame.project_stage == 3 else "invest")

func _physics_process(delta: float) -> void:
	if session in ["local", "host"] and not state.frame.is_empty():
		state.tick(delta)
		save_elapsed += delta
		if save_elapsed >= SAVE_EVERY:
			save_elapsed = 0.0
			save_mine()
		if session == "host":
			broadcast_time += delta
			if broadcast_time >= 0.04:
				broadcast_time = fmod(broadcast_time, 0.04)
				room.publish(state.frame)
		refresh()

func load_controls() -> void:
	var config := ConfigFile.new()
	if config.load(PREFS) != OK:
		return
	var values: Variant = config.get_value("local", "fire", [])
	if values is Array and values.size() == 4:
		var seen := {}
		for key in values:
			if typeof(key) != TYPE_INT or key <= 0 or key == KEY_ESCAPE or seen.has(key):
				return
			seen[key] = true
		fire_keys = values.duplicate()
	selected_count = clampi(int(config.get_value("local","count",2)),2,4)

func persist_controls() -> void:
	var config := ConfigFile.new()
	config.set_value("local", "fire", fire_keys)
	config.set_value("local", "count",selected_count)
	if config.save(PREFS) != OK:
		notice = "按键设置未能保存，本次仍可使用。"

func fire_name(value: int) -> String:
	match value:
		KEY_SPACE: return "空格"
		KEY_ENTER: return "回车"
		_: return OS.get_keycode_string(value)

func choose_count(value: int) -> void:
	address_draft = address_box.text
	selected_count = value
	capture_seat = -1
	notice = ""
	persist_controls()
	preview.start(value)
	shown = ""
	refresh()

func start_capture(p: int) -> void:
	if address_box.has_focus(): address_box.release_focus()
	capture_seat = p
	feedback.text = "请按 P%d 的新出钩键，Esc 取消。" % (p+1)

func accept_binding(key: int) -> void:
	if key == KEY_ESCAPE:
		capture_seat = -1
		feedback.text = "已取消改键。"
		return
	if key <= 0 or key in [KEY_SHIFT, KEY_CTRL, KEY_META, KEY_ALT]:
		feedback.text = "请选择一个可单独按下的出钩键。"
		return
	var previous := fire_keys.find(key)
	if previous != -1 and previous != capture_seat:
		feedback.text = "%s 是 P%d 的出钩键，请换一个。" % [fire_name(key),previous+1]
		return
	fire_keys[capture_seat] = key
	notice = "P%d 现在用 %s 出钩。" % [capture_seat+1,fire_name(key)]
	capture_seat = -1
	persist_controls()
	address_draft = address_box.text
	shown = ""
	refresh()

func ground_input(p: int, direction: int, down: bool) -> void:
	if not controls(p) or state.frame.is_empty(): return
	var keys: Array = walk_held[p]
	keys.erase(direction)
	if down: keys.append(direction)
	var last: int = 0 if keys.is_empty() else keys.back()
	act(p,"move_stop" if last == 0 else ("move_left" if last < 0 else "move_right"))

func release_walk() -> void:
	for p in active_count:
		if not walk_held[p].is_empty():
			walk_held[p].clear()
			if not state.frame.is_empty() and controls(p): act(p,"move_stop")

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	if is_instance_valid(opening_panel):
		if event.pressed and event.keycode == KEY_ESCAPE:
			close_opening()
		return
	if is_instance_valid(sample_panel):
		if event.pressed and event.keycode == KEY_ESCAPE:
			close_samples()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(gift_popup):
		if event.pressed and event.keycode == KEY_ESCAPE and not gift_pending:
			close_gift()
			get_viewport().set_input_as_handled()
		return
	var key: int = event.keycode
	if key == KEY_KP_ENTER: key = KEY_ENTER
	if event.pressed and session == "menu" and capture_seat >= 0:
		accept_binding(key)
		get_viewport().set_input_as_handled()
		return
	if state.frame.is_empty(): return
	var p := maxi(0,room.local_seat)
	var fire_seat := fire_keys.find(key) if session == "local" else (p if key in [KEY_SPACE, KEY_ENTER] else -1)
	if fire_seat < 0 or fire_seat >= active_count:
		for seat in active_count:
			if not controls(seat): continue
			var binding: Array = WALK_KEYS[seat] if session == "local" else WALK_KEYS[0]
			var bind_index := binding.find(key)
			if session != "local" and bind_index < 0: bind_index = WALK_KEYS[1].find(key)
			if bind_index >= 0:
				ground_input(seat, -1 if bind_index == 0 else 1, event.pressed)
				get_viewport().set_input_as_handled()
				return
	if not event.pressed: return
	if fire_seat >= 0 and fire_seat < active_count:
		act(fire_seat,"fire")
	else:
		match key:
			KEY_1: act(p,"winch")
			KEY_2: act(p,"drill")
			KEY_3: project_act(p)
			KEY_0 when session == "local": project_act(1)
			KEY_8 when session == "local": act(1,"winch")
			KEY_9 when session == "local": act(1,"drill")
			_: return
	get_viewport().set_input_as_handled()

func box_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style

func panel(rect: Rect2, bg := INK) -> void:
	var box := Panel.new()
	box.position = rect.position
	box.size = rect.size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", box_style(bg, Color("49615a")))
	ui.add_child(box)

func text_at(value: String, rect: Rect2, font_size: int, color := PAPER, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	ui.add_child(label)
	return label

func button(caption: String, rect: Rect2, pressed: Callable, accent := PAPER) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.text = caption
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_disabled_color", Color("b9c2b2"))
	b.add_theme_stylebox_override("normal", box_style(Color("2a4440"), Color("61796d")))
	b.add_theme_stylebox_override("hover", box_style(Color("405b51"), GOLD))
	b.add_theme_stylebox_override("disabled",box_style(Color("253a36"),Color("354e49")))
	b.add_theme_stylebox_override("pressed", box_style(Color("36584d"), GOLD))
	b.pressed.connect(pressed)
	ui.add_child(b)
	return b

func refresh() -> void:
	var active := not state.frame.is_empty()
	art.frame = state.frame if active else preview.frame
	art.mine_state = state if active else preview
	art.scale = Vector2(1,0.94) if active else Vector2.ONE
	art.position = Vector2(0,-14) if active else Vector2.ZERO
	art.queue_redraw()
	var key := session + ("/mine" if active else "/entry")
	if key != shown:
		shown = key
		opening_seen = active and not state.frame.opening_record.is_empty()
		for child in ui.get_children():
			ui.remove_child(child)
			child.queue_free()
		wallets.clear()
		personal_panels.clear()
		personal_tabs.clear()
		open_seat = -1
		rate_labels.clear()
		gear.clear()
		market_buttons.clear()
		ground_labels.clear()
		trade_views.clear()
		product_frames.clear()
		trade_switch.clear()
		trade_contract.clear()
		trade_quote.clear()
		cutter_buttons.clear()
		trade_receipts.clear()
		trade_alerts.clear()
		trade_last.clear()
		appraisal_seen.clear()
		sale_until.clear()
		auto_trading.clear()
		appraisal.clear()
		inspection.clear()
		lamp_status.clear()
		sale.clear()
		map_buttons.clear()
		last_wildlife.clear()
		inventory_labels.clear()
		project_actions.clear()
		last_earned.clear()
		if session == "menu": menu_ui()
		elif not active: lobby_ui()
		else:
			last_contest_id = state.frame.get("last_contest",{}).get("id",-1)
			contest_expiry = 0
			art.contest_begin = -1
			last_assist_id = state.frame.get("last_assist",{}).get("id",-1)
			assist_expiry = 0
			last_gift_id = state.frame.get("last_gift",{}).get("id",-1)
			gift_expiry = 0
			last_earned = state.frame.earned.duplicate()
			last_wildlife = state.frame.wildlife.duplicate()
			hud()
	if active:
		update_hud()

func close_opening() -> void:
	if is_instance_valid(opening_panel):
		opening_panel.hide()
		opening_panel.queue_free()
	opening_panel = null

func opening_key(f: Dictionary) -> String:
	return "%s/%s/%s/%s/%s/%s" % [f.project_launched,f.opening_samples.size(),f.opening_samples.has("red"),f.last_sale.is_empty(),f.cutters.has(true),f.opening_record.is_empty()]

func show_opening() -> void:
	if state.frame.is_empty(): return
	close_opening()
	release_walk()
	var f := state.frame
	opening_view_key = opening_key(f)
	var record: Dictionary = f.opening_record
	opening_panel = Panel.new()
	opening_panel.size = Vector2(960,600)
	opening_panel.z_index = 7
	opening_panel.add_theme_stylebox_override("panel",box_style(Color("132627f8"),GOLD))
	ui.add_child(opening_panel)
	var first := ui.get_child_count()
	text_at("矿铺正式开业" if not record.is_empty() else "矿铺开业验收",Rect2(170,80,620,64),38,GOLD,HORIZONTAL_ALIGNMENT_CENTER)
	text_at("升降机　" + ("已通车" if f.project_launched else "集资修复三段工程、售出两枚宝石后启动"),Rect2(214,166,570,38),19)
	var index := 0
	for color in ["red","green"]:
		var stamp: Dictionary = f.opening_samples.get(color,{})
		var name_text := "红色成品" if color == "red" else "绿色成品"
		var line := "等待第一件切割成品在柜台成交" if stamp.is_empty() else "已登记　P%d · 第%d笔成交 · 石价%d金" % [stamp.seller+1,stamp.sale,stamp.price]
		text_at(name_text + "　" + line,Rect2(214,221+index*48,590,40),18)
		index += 1
	var guide: String
	if not record.is_empty():
		guide = "P%d 完成最后一项验收。开业时共成交 %d 笔，完成 %d 份委托。" % [record.miner+1,record.sales,record.contracts]
	elif f.last_sale.is_empty():
		guide = "走到空闲矿机出钩，扛第一块原石到两端柜台出售。"
	elif not f.cutters.has(true):
		guide = "在柜台开石，留一块独采晶心建切割台。"
	elif f.opening_samples.size() < 2:
		guide = "把已开石料在柜台切割、出售，优先交付缺少的颜色。"
	else:
		guide = "两件货样已齐。完成升降机筹资并启动，即可开业。"
	text_at(guide,Rect2(126,346,708,55),17,PAPER,HORIZONTAL_ALIGNMENT_CENTER)
	button("继续经营" if not record.is_empty() else "返回矿场",Rect2(374,432,212,44),close_opening,GOLD)
	while ui.get_child_count() > first:
		ui.get_child(first).reparent(opening_panel,false)

func close_samples() -> void:
	if is_instance_valid(sample_panel):
		sample_panel.hide()
		sample_panel.queue_free()
	sample_panel = null

func show_samples() -> void:
	if is_instance_valid(sample_panel): return
	capture_seat = -1
	sample_panel = Panel.new()
	sample_panel.size = Vector2(960,600)
	sample_panel.add_theme_stylebox_override("panel",box_style(Color("0d1b1cf7"),INK))
	sample_panel.z_index = 6
	ui.add_child(sample_panel)
	var first := ui.get_child_count()
	text_at("切割台样品",Rect2(215,65,500,52),36,GOLD,HORIZONTAL_ALIGNMENT_CENTER)
	var caption := text_at("两种成品的转面与光泽",Rect2(215,119,500,32),16,PAPER,HORIZONTAL_ALIGNMENT_CENTER)
	var samples: Array[Control] = []
	for row in 2:
		var x := 250+240*row
		panel(Rect2(x,170,220,223),Color("213938"))
		var sprite := GemView.new()
		sprite.position = Vector2(x+14,175)
		sprite.size = Vector2(192,192)
		sprite.sample = true
		sprite.cargo = {"base":row}
		ui.add_child(sprite)
		samples.append(sprite)
		text_at("绿宝石" if row==0 else "红宝石",Rect2(x,355,220,34),18,PAPER,HORIZONTAL_ALIGNMENT_CENTER)
	button("播放 3 秒切割",Rect2(307,429,171,41),func():
		for sprite in samples: sprite.sample_elapsed = 0.0
		caption.text = "从粗糙岩壳到抛光切面",GOLD)
	button("返回大厅",Rect2(489,429,145,41),close_samples)
	while ui.get_child_count()>first:
		ui.get_child(first).reparent(sample_panel,false)

func menu_ui() -> void:
	panel(Rect2(49,145,634,420))
	button("看宝石样品",Rect2(498,170,136,36),show_samples,GOLD)
	text_at("矿工联营",Rect2(75,155,430,59),43,GOLD)
	text_at("走到任意空闲矿机出钩，扛货到两端收购站开石、出售。",Rect2(76,216,565,26),17)
	text_at("矿工人数",Rect2(76,257,96,34),16)
	for n in range(2,5):
		var choice := button("%d 人" % n,Rect2(171+(n-2)*95,255,82,37),choose_count.bind(n),GOLD if selected_count==n else PAPER)
		choice.disabled = n == selected_count
	text_at("同机出钩键",Rect2(76,306,105,31),15)
	for p in selected_count:
		button("P%d · %s" % [p+1,fire_name(fire_keys[p])],Rect2(181+p*117,303,112,37),start_capture.bind(p),COLORS[p])
	feedback = text_at(notice if notice != "" else "点击玩家按键可重新绑定。",Rect2(76,345,582,27),14,GOLD)
	button("进入同机矿场",Rect2(76,385,266,45),local_game,GOLD)
	button("创建局域网房间",Rect2(354,385,280,45),host_game)
	address_box = LineEdit.new()
	address_box.placeholder_text = "房主的局域网 IP"
	address_box.position = Vector2(76,445)
	address_box.size = Vector2(294,40)
	address_box.text = address_draft
	address_box.text_submitted.connect(join_game)
	ui.add_child(address_box)
	button("加入房间",Rect2(382,445,252,40),func(): join_game(address_box.text))
	text_at("新矿场默认派对争夺。旧矿场首次升级沿用协作合拉。",Rect2(76,505,580,33),14)

func lobby_ui() -> void:
	panel(Rect2(155,222,650,224))
	lobby_count = text_at("",Rect2(180,239,600,53),30,GOLD)
	update_lobby()
	if session == "host":
		var addresses := PackedStringArray()
		for address in IP.get_local_addresses():
			if address.contains(".") and not address.contains(":") and not address.begins_with("127.") and not address.begins_with("169.254."):
				addresses.append(address)
		text_at("房主地址   " + "  /  ".join(addresses),Rect2(180,306,605,32),16)
	button("返回大厅",Rect2(180,374,145,43),to_menu)

func update_lobby() -> void:
	if not is_instance_valid(lobby_count): return
	if session == "client" and room.local_seat < 0:
		lobby_count.text = "正在连接房主…"
	else:
		lobby_count.text = "等待矿友　%d / %d 人" % [room.connected_count,room.target_count]

func toggle_personal(p: int) -> void:
	if open_seat >= 0:
		personal_panels[open_seat].hide()
		personal_tabs[open_seat].button_pressed = false
	open_seat = -1 if open_seat == p else p
	if open_seat >= 0:
		personal_panels[open_seat].show()
		personal_tabs[open_seat].button_pressed = true

func switch_market_from_panel(p: int) -> void:
	act(p,"market")
	if open_seat == p:
		toggle_personal(p)

func toggle_rules() -> void:
	if not state.frame.is_empty() and session != "client":
		act(0,"rules_coop" if state.frame.rules == "party" else "rules_party")

func hud() -> void:
	panel(Rect2(0,0,960,58))
	project_label = text_at("",Rect2(16,2,533,29),19,GOLD)
	depth_label = text_at("",Rect2(17,30,111,24),14,PAPER)
	production_label = text_at("",Rect2(127,30,244,24),14,PAPER)
	var track := ColorRect.new()
	track.position = Vector2(358,42)
	track.size = Vector2(84,4)
	track.color = Color("4a6057")
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(track)
	depth_bar = ColorRect.new()
	depth_bar.color = GOLD
	track.add_child(depth_bar)
	for i in (MAP_IDS.size() if Core.FAUNA_ENABLED else 0):
		var selector := button(MAP_NAMES[i],Rect2(573+i*65,4,60,29),act.bind(0,"map_"+MAP_IDS[i]))
		selector.add_theme_font_size_override("font_size",14)
		map_buttons.append(selector)
	rules_button = button("",Rect2(457,20,108,30),toggle_rules,GOLD)
	rules_button.add_theme_font_size_override("font_size",14)
	map_notice = text_at("",Rect2(555,32,282,24),13,PAPER,HORIZONTAL_ALIGNMENT_CENTER)
	opening_button = button("开业验收",Rect2(570,2,254,28),show_opening,GOLD)
	opening_button.add_theme_font_size_override("font_size",14)
	button("返回大厅",Rect2(842,9,106,37),to_menu)
	panel(Rect2(0,546,960,54))
	var width := 960.0 / active_count
	for p in active_count:
		var x := width*p
		var hint := fire_name(fire_keys[p])+"出钩" if session == "local" else ("你 · 空格出钩" if controls(p) else "矿友")
		var tab := button("P%d · 矿工面板" % (p+1),Rect2(x+5,551,width-10,44),toggle_personal.bind(p),COLORS[p])
		tab.toggle_mode = true
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.add_theme_font_size_override("font_size",14)
		personal_tabs.append(tab)
		var rate := text_at(hint,Rect2(x+98,552,width-111,42),13,PAPER,HORIZONTAL_ALIGNMENT_RIGHT)
		rate.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		rate.set_meta("hint",hint)
		rate_labels.append(rate)
		build_personal(p,clampf(x + width*0.5-159,9,633))

func build_personal(p: int, x: float) -> void:
	var drawer := Panel.new()
	drawer.position = Vector2(x,166)
	drawer.size = Vector2(318,375)
	drawer.z_index = 2
	drawer.add_theme_stylebox_override("panel",box_style(Color("172e2e"),COLORS[p]))
	ui.add_child(drawer)
	personal_panels.append(drawer)
	var first := ui.get_child_count()
	wallets.append(text_at("",Rect2(14,8,161,33),21,COLORS[p]))
	trade_switch.append(button("收购店",Rect2(176,10,72,28),toggle_trade.bind(p),GOLD))
	button("收起",Rect2(253,10,52,28),toggle_personal.bind(p))
	var inventory := text_at("",Rect2(14,47,293,26),14,PAPER)
	inventory_labels.append(inventory)
	var market_button := button("切到订货",Rect2(14,83,140,34),switch_market_from_panel.bind(p),COLORS[p])
	market_button.tooltip_text = "瞄准时切换轨道，再按自己的出钩键抓取补给。货箱锁定时扣款。"
	market_buttons.append(market_button)
	var give := button("赠金给矿友",Rect2(162,83,142,34),open_gift.bind(p),COLORS[p])
	give.disabled = not controls(p)
	for i in 2:
		var b := button("",Rect2(14+148*i,128,141,41),act.bind(p,ACTIONS[i]),COLORS[p])
		b.add_theme_font_size_override("font_size",14)
		gear.append(b)
	project_actions.append(button("",Rect2(14,181,290,38),project_act.bind(p),GOLD))
	var ground := text_at("",Rect2(14,258,292,26),14,PAPER)
	ground_labels.append(ground)
	for i in 2:
		var direction := -1 if i==0 else 1
		var move := button("◀ 左移" if i==0 else "右移 ▶",Rect2(14+i*74,289,70,32),func():pass,COLORS[p])
		move.disabled = not controls(p)
		move.button_down.connect(ground_input.bind(p,direction,true))
		move.button_up.connect(ground_input.bind(p,direction,false))
	appraisal.append(button("开石",Rect2(163,289,63,32),act.bind(p,"open"),COLORS[p]))
	sale.append(button("出售",Rect2(231,289,73,32),act.bind(p,"sell"),GOLD))
	var movement: String = WALK_HINTS[p] if session == "local" else "A/D 或 ←/→"
	var hint := "%s 或按住按钮移动 · 空闲机出钩，两端收购" % movement if controls(p) else "矿友的装备与库存"
	text_at(hint,Rect2(14,331,295,27),13,Color("c3d6cc"))
	# The normal widget factories return nodes in UI coordinates. Group this seat's
	# controls under one clipped panel using their panel-local positions.
	while ui.get_child_count() > first:
		ui.get_child(first).reparent(drawer,false)
	var receipt_view := Panel.new()
	receipt_view.position = Vector2(5,42)
	receipt_view.size = Vector2(308,214)
	receipt_view.add_theme_stylebox_override("panel",box_style(Color("243e37"),Color("8b8056")))
	drawer.add_child(receipt_view)
	trade_views.append(receipt_view)
	first = ui.get_child_count()
	var product := GemView.new()
	product.position = Vector2(227,3)
	product.size = Vector2(76,76)
	receipt_view.add_child(product)
	product_frames.append(product)
	trade_contract.append(text_at("",Rect2(9,5,217,39),15,GOLD))
	trade_quote.append(text_at("",Rect2(9,45,215,38),15,PAPER))
	trade_alerts.append(text_at("",Rect2(9,83,290,26),15,Color("a5e6bb")))
	trade_receipts.append(text_at("",Rect2(9,180,290,32),13,Color("c3d2c9")))
	cutter_buttons.append(button("",Rect2(9,149,290,28),run_cutter.bind(p),GOLD))
	cutter_buttons[p].add_theme_font_size_override("font_size",13)
	inspection.append(button("照石",Rect2(9,115,69,31),act.bind(p,"inspect"),GOLD))
	inspection[p].tooltip_text = "每块未开原石可照一次，照后仍可原封出售。"
	lamp_status.append(text_at("",Rect2(86,111,214,41),13,PAPER))
	while ui.get_child_count() > first:
		ui.get_child(first).reparent(receipt_view,false)
	receipt_view.hide()
	trade_last.append(state.frame.sales[p].get("id",-1))
	appraisal_seen.append(state.frame.cargo[p].get("opened",false))
	sale_until.append(0)
	auto_trading.append(false)
	drawer.hide()

func toggle_trade(p: int) -> void:
	trade_views[p].visible = not trade_views[p].visible
	trade_switch[p].text = "看装备" if trade_views[p].visible else "收购店"

func run_cutter(p: int) -> void:
	act(p, "cut" if state.frame.cutters[p] else "build_cutter")

func update_cutter(p: int, f: Dictionary, carried: Dictionary, at_shop: bool) -> void:
	var b := cutter_buttons[p]
	b.tooltip_text = ""
	b.disabled = true
	if not f.cutters[p]:
		if carried.get("opened",false) and carried.grade == 2 and carried.helper == -1:
			b.text = "用晶心建台 · 放弃 %d 金石价" % carried.quote
			b.disabled = not (controls(p) and at_shop)
		else:
			b.text = "用一块已开的独采晶心建切割台"
	elif carried.get("cut_left",0.0) > 0.0:
		b.text = "正在切割 · 剩余 %.1f 秒" % carried.cut_left
	elif carried.get("cut",false):
		b.text = "切割完成 · 成品 %d 金，可出售" % carried.quote
	elif not carried.get("opened",false):
		b.text = "切割台已建 · 带已开石料来加工"
	else:
		var price := Core.cut_price(carried.quote)
		var gain: int = price - carried.quote
		var terms := "%d → %d 金 · 费用 %d 金" % [carried.quote,price,Core.CUT_COST]
		if gain <= Core.CUT_COST and state.needs_exhibit(carried):
			b.text = "开业留样 · 净收益不足 · 8金/3秒" if f.wallet[p] >= Core.CUT_COST else "开业留样 · 净收益不足 · 需8金"
			b.tooltip_text = terms
			b.disabled = not (controls(p) and at_shop and f.wallet[p] >= Core.CUT_COST)
		elif gain <= Core.CUT_COST:
			b.text = terms + " · 利润不足"
		elif f.wallet[p] < Core.CUT_COST:
			b.text = terms + " · 余额不足"
		else:
			b.text = terms + " · 切割 3 秒"
			b.disabled = not (controls(p) and at_shop)

func update_trade(p: int, f: Dictionary, carried: Dictionary, at_shop: bool) -> void:
	update_cutter(p, f, carried, at_shop)
	product_frames[p].cargo = carried
	var arrival := at_shop and not carried.is_empty()
	if arrival and not auto_trading[p] and not trade_views[p].visible:
		toggle_trade(p)
	auto_trading[p] = arrival
	var which: int = f.contract_count % Core.CONTRACT_NAMES.size()
	var bonus: int = Core.CONTRACT_BONUSES[which]
	trade_contract[p].text = "委托 %d　%s  +%d 金\n交付%s" % [f.contract_count+1,Core.CONTRACT_NAMES[which],bonus,CONTRACT_TERMS[which]]
	var opened: bool = carried.get("opened",false)
	var experience: int = f.appraisal_xp[p]
	var unlocked := experience >= Core.LAMP_UNLOCK
	var clue := Core.inspection_hint(carried)
	inspection[p].disabled = not controls(p) or not unlocked or not at_shop or carried.is_empty() or opened or carried.get("inspected",false)
	if not unlocked:
		lamp_status[p].text = "开石 %d/%d 次解锁验石灯" % [experience,Core.LAMP_UNLOCK]
	elif clue != "":
		lamp_status[p].text = "灯下%s · 品质仍待开石" % clue
	else:
		lamp_status[p].text = "验石灯已解锁 · 每石可照一次"
	if carried.is_empty():
		trade_quote[p].text = "还没有待售原石"
		trade_alerts[p].text = "已完成 %d 份委托" % f.contract_count
	else:
		var base_offer := Core.cargo_quote(carried.base,carried.grade,false)
		if carried.get("cut",false):
			var color := Core.product_color(carried)
			var color_name := "绿" if color == "green" else "红"
			trade_quote[p].text = "%s色成品 · %d金\n%s" % [color_name,carried.quote,"此色已登记" if f.opening_samples.has(color) else "售出即可登记开业货样"]
		elif carried.get("cut_left",0.0)>0:
			trade_quote[p].text = "切割中　%d → %d 金" % [carried.quote,Core.cut_price(carried.quote)]
		elif opened:
			trade_quote[p].text = "%s　开石前 %d → %d 金（%+d）" % [GRADE_NAMES[carried.grade],base_offer,carried.quote,carried.quote-base_offer]
		else:
			trade_quote[p].text = "保底收购 %d 金\n开石后报价可能涨跌。" % base_offer
		trade_alerts[p].text = "本件符合委托，出售加 %d 金" % bonus if Core.contract_matches(f.contract_count,carried) else "本件按普通报价收购"
		if opened and not appraisal_seen[p]:
			trade_quote[p].modulate = GOLD
			trade_quote[p].create_tween().tween_property(trade_quote[p],"modulate",Color.WHITE,1.1)
	appraisal_seen[p] = opened
	var receipt: Dictionary = f.sales[p]
	if receipt.is_empty():
		trade_receipts[p].text = "暂无成交记录"
	else:
		var split := "给 P%d  %d 金" % [receipt.helper+1,receipt.share] if receipt.helper>=0 else "独立交货"
		trade_receipts[p].text = "最近成交　货价 %d 金 · %s\n委托 +%d 金　　实收 %d 金" % [receipt.price,split,receipt.bonus,receipt.net]
		if trade_last[p] != receipt.id:
			trade_last[p] = receipt.id
			sale_until[p] = Time.get_ticks_msec()+3800
			trade_receipts[p].modulate = GOLD
			trade_receipts[p].create_tween().tween_property(trade_receipts[p],"modulate",Color.WHITE,1.1)

func update_hud() -> void:
	var f := state.frame
	if is_instance_valid(gift_popup) and gift_sender >= 0:
		gift_title.text = "P%d 赠金　钱包 %d 金" % [gift_sender+1,f.wallet[gift_sender]]
	var busy: bool = f.hooks.any(func(h): return h.mode != "aim")
	for i in (MAP_IDS.size() if Core.FAUNA_ENABLED else 0):
		var selected: bool = f.map_id == MAP_IDS[i]
		map_buttons[i].disabled = selected or busy or session == "client"
		map_buttons[i].text = ("● " if selected else "") + MAP_NAMES[i]
	var party: bool = f.rules == "party"
	rules_button.text = "派对争夺" if party else "协作合拉"
	rules_button.disabled = busy or session == "client"
	rules_button.tooltip_text = "全员收钩后，由房主或同机 P1 点击切换共同规则。"
	if busy:
		map_notice.text = "收回全部抓钩后可切换"
	elif session == "client":
		map_notice.text = "规则由房主切换"
	else:
		map_notice.text = "橙圈截货 · 双钩相碰弹回" if party else "瞄准队友钩圈 · 协作分成"
	var contest: Dictionary = f.get("last_contest",{})
	if not contest.is_empty() and int(contest.id) != last_contest_id:
		last_contest_id = contest.id
		contest_expiry = Time.get_ticks_msec()+2300
		art.contest_begin = Time.get_ticks_msec()
	var transfer: Dictionary = f.get("last_gift",{})
	if not transfer.is_empty() and int(transfer.id)!=last_gift_id:
		last_gift_id = transfer.id
		gift_expiry = Time.get_ticks_msec()+3500
	var settlement: Dictionary = f.get("last_assist",{})
	if not settlement.is_empty() and int(settlement.id) != last_assist_id:
		last_assist_id = settlement.id
		assist_expiry = Time.get_ticks_msec() + 3200
	var stamps: Dictionary = f.opening_samples
	opening_button.text = "查看开业记录" if not f.opening_record.is_empty() else "开业验收　通车%s　红%s　绿%s" % ["✓" if f.project_launched else "○","✓" if stamps.has("red") else "○","✓" if stamps.has("green") else "○"]
	if not f.opening_record.is_empty() and not opening_seen:
		opening_seen = true
		show_opening()
	elif is_instance_valid(opening_panel) and opening_key(f) != opening_view_key:
		show_opening()
	var stage: int = f.project_stage
	var due := 0
	if stage < 3:
		due = Core.PROJECT_COSTS[stage] - int(f.project_paid)
		var names := ["修井架", "装绞车", "接通动力"]
		project_label.text = "升降机 %d/3 · %s　%d/%d 金" % [stage+1,names[stage],f.project_paid,Core.PROJECT_COSTS[stage]]
		if stage == 2:
			project_label.text += "　出售宝石 %d/2" % f.project_gems
	else:
		project_label.text = "升降机已通车 · 可继续采矿与升级" if f.project_launched else "三段工程完成 · 任一矿工可启动升降机"
	for p in active_count:
		var offer: int = mini(f.wallet[p],due)
		var b := project_actions[p]
		var key := "工程　"
		b.text = key + ("已通车" if f.project_launched else ("启动" if stage == 3 else ("出资 %d 金" % offer)))
		b.disabled = not controls(p) or f.project_launched or (stage < 3 and offer <= 0)
	var total := 0
	for earned: int in f.earned:
		total += earned
	var target: int = Core.threshold(f.level)
	depth_label.text = "矿脉 %d 级" % f.level
	depth_bar.size = Vector2(84.0 * clampf(float(total)/maxi(1,target),0,1),4)
	production_label.text = "累计产值  %d / %d" % [total,target]
	for p in active_count:
		wallets[p].text = "P%d 钱包　%d 金" % [p+1,f.wallet[p]]
		var hook: Dictionary = f.hooks[p]
		var receipt: String = RECEIPT.get(hook.market_notice,"")
		var hint: String = rate_labels[p].get_meta("hint")
		rate_labels[p].text = receipt if receipt!="" else ("订货 · " + hint if hook.market else hint)
		market_buttons[p].text = "切回作业" if hook.market else "切到订货"
		var carried: Dictionary = f.cargo[p]
		var at_machine := state.at_winch(p)
		var machine := state.nearby_station(p)
		var operator := state.station_user(machine) if machine >= 0 else -1
		var at_shop := state.at_buyer(p)
		update_trade(p,f,carried,at_shop)
		market_buttons[p].disabled = not controls(p) or hook.mode != "aim" or not at_machine or not carried.is_empty()
		appraisal[p].disabled = not controls(p) or not at_shop or carried.is_empty() or carried.get("opened",false)
		sale[p].disabled = not controls(p) or not at_shop or carried.is_empty() or state.cutting(p)
		var ground_state := "收购站" if at_shop else "地表 · 可使用任意空闲机"
		if machine >= 0:
			var specialty := Core.station_type(machine)
			ground_state = "%s · %s回收 ×%.2f" % [specialty.name, specialty.cargo, Core.STATION_BONUS]
		if not carried.is_empty():
			ground_state = "扛货 · " + ("已验 %d 金" % carried.quote if carried.opened else "原石估价 %d 金" % carried.quote)
			if not at_shop: ground_state += " · 去两端收购站"
			else: ground_state += " · 可出售"
		ground_labels[p].text = ground_state
		if not carried.is_empty():
			rate_labels[p].text = "收购站 · 可出售" if at_shop else "扛货去收购站"
		elif hook.mode=="aim" and machine>=0:
			if operator>=0:
				rate_labels[p].text = "%d号机 · P%d占用" % [machine+1,operator+1]
			else:
				rate_labels[p].text = ("%d号机 · " % (machine+1)) + rate_labels[p].text
		elif not at_machine and hook.mode=="aim":
			rate_labels[p].text = (WALK_HINTS[p] if session=="local" else "A/D") + " 找空闲机"
		var captures: int = f.wildlife[p]
		var wildlife_income := floori(float(captures)/5.0) if Core.FAUNA_ENABLED else 0
		var income: int = 5 * f.drill[p] * f.level + 2 * f.tailings[p] + wildlife_income
		var milestone := wildlife_income > floori(float(last_wildlife[p])/5.0)
		if f.map_id != "mine" and receipt=="":
			rate_labels[p].text += " · 捕获 %d/5" % (captures % 5)
		if hook.get("helper",-1)>=0:
			rate_labels[p].text = "与 P%d 合拉中" % (int(hook.helper)+1)
		elif hook.get("leader",-1)>=0:
			rate_labels[p].text = "正在协助 P%d" % (int(hook.leader)+1)
		elif hook.mode=="back" and hook.load>=0 and not hook.market:
			var near_dock := Vector2(hook.tip).distance_to(hook.origin) <= 50
			if party and f.ores[hook.load].get("stolen",false):
				rate_labels[p].text = "已截获 · 货物已锁定"
			elif near_dock:
				rate_labels[p].text = "井口保护"
			else:
				rate_labels[p].text = "回程 · 可被截货" if party else "载货回程 · 队友可钩圆圈"
		if party and not contest.is_empty() and Time.get_ticks_msec() < contest_expiry and p in [contest.a,contest.b]:
			if contest.kind == "clash":
				rate_labels[p].text = "碰钩 · 空钩弹回"
			else:
				rate_labels[p].text = ("截获 P%d 的货" % (contest.b+1)) if p==contest.a else ("P%d 已截货" % (contest.a+1))
		if Time.get_ticks_msec() < assist_expiry and not settlement.is_empty():
			if p == settlement.lead:
				rate_labels[p].text = "合拉交付 · 主钩 +%d金" % (settlement.price-settlement.share)
			elif p == settlement.helper:
				rate_labels[p].text = "合拉交付 · 帮手 +%d金" % settlement.share
		if not transfer.is_empty() and Time.get_ticks_msec()<gift_expiry:
			if p == transfer.recipient:
				rate_labels[p].text = "收到 P%d 的 %d 金" % [transfer.sender+1,transfer.amount]
			elif p == transfer.sender:
				rate_labels[p].text = "已赠 P%d　%d 金" % [transfer.recipient+1,transfer.amount]
		if Time.get_ticks_msec() < sale_until[p]:
			rate_labels[p].text = "成交实收 %d 金" % f.sales[p].net
		last_wildlife[p] = captures
		inventory_labels[p].text = "油%d 图%d 布%d 尾矿机%d · %d金/5秒" % [f.oil[p],f.blueprint[p],f.polish[p],f.tailings[p],income]
		if save_failed:
			inventory_labels[p].text += " · 存档失败"
		inventory_labels[p].tooltip_text = "油用于重物；图纸配石块建尾矿机；布提高宝石价值。"
		var gain: int = f.earned[p] - last_earned[p]
		if gain > 0:
			var pos: Vector2 = art.position + Vector2(f.hooks[p].origin) * art.scale
			var tag := text_at("捕获满5 · 永久+1金/5秒" if milestone else ("+%d 金" % gain),Rect2(Vector2(clampf(pos.x-65,5,750),pos.y-32),Vector2(200,28)),16,COLORS[p])
			var motion := tag.create_tween().set_parallel(true)
			motion.tween_property(tag,"position:y",tag.position.y-18,0.65)
			motion.tween_property(tag,"modulate:a",0.0,0.35).set_delay(0.3)
			motion.chain().tween_callback(tag.queue_free)
		last_earned[p] = f.earned[p]
		for i in 2:
			var action: String = ACTIONS[i]
			var level: int = f[action][p]
			var cost: int = Core.price(action,level)
			var b := gear[p*2+i]
			
			b.tooltip_text = "每级提升 25% 基础回收速度" if i == 0 else ("每级每 5 秒产 %d 金" % (5*f.level))
			var name_text := "绞盘" if i == 0 else "钻机"
			b.text = "%s Lv.%d · %d金" % [name_text,level,cost]
			b.disabled = not controls(p) or f.wallet[p]<cost
