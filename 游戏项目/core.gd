extends RefCounted

# Value, loaded return speed, collision radius and time to regrow.
const TYPES := {
	"small": [30, 220.0, 12.0, 4.0], "gold": [65, 145.0, 18.0, 7.0],
	"giant": [120, 82.0, 30.0, 12.0], "rock": [5, 90.0, 16.0, 5.0],
	"gem": [90, 135.0, 15.0, 9.0],
	"silverfish":[26,220.0,13.0,4.0], "carp":[50,170.0,17.0,6.0], "goldfin":[88,125.0,20.0,9.0],
	"graymouse":[28,225.0,13.0,4.0], "mole":[55,155.0,17.0,6.0], "goldback":[92,135.0,19.0,9.0]
}
const HOME := [Vector2(260, 145), Vector2(700, 145)]
const MAX_ANGLE := 1.22
const REST_LENGTH := 23.0
const DRILL_PERIOD := 5.0
const STATION_BONUS := 1.35
const STATION_TYPES := [
	{"name":"快卷机", "cargo":"碎金、金块", "kinds":["small","gold"]},
	{"name":"重载机", "cargo":"巨金、石块", "kinds":["giant","rock"]}
]
const CUT_COST := 8
const CUT_SECONDS := 3.0
const LAMP_UNLOCK := 3
const CONTRACT_NAMES := ["原石备料", "鉴定样本", "优质展品"]
const CONTRACT_BONUSES := [15,20,35]
const PROJECT_COSTS := [120, 240, 360]
const VALUE_RANGES := {"small":Vector2i(22,38), "gold":Vector2i(48,82), "giant":Vector2i(95,145), "rock":Vector2i(3,8), "gem":Vector2i(72,108), "silverfish":Vector2i(18,34), "carp":Vector2i(38,62), "goldfin":Vector2i(72,105), "graymouse":Vector2i(20,36), "mole":Vector2i(42,68), "goldback":Vector2i(75,110)}
const REGULAR_KINDS := ["small", "small", "small", "small", "gold", "gold", "gold", "giant", "rock", "rock"]
const CRATE_KINDS := ["oil", "blueprint", "polish"]
const CRATE_PRICES := [20, 35, 45]
const CRATE_CHARGES := [3, 1, 2]
const ASSIST_RADIUS := 20.0
const ASSIST_MIN_DISTANCE := 50.0
const ASSIST_SPEED := 1.6
const CRATE_RADIUS := 22.0
const STOCK_DELAY := 8.0
const REGULAR_SLOTS := 16
const GEM_SLOTS := 2
const FAUNA_ENABLED := false
const BIOMES := ["mine", "lake", "burrow"]
const FAUNA_SLOTS := 8
const FAUNA := {"lake":["silverfish", "carp", "goldfin"], "burrow":["graymouse", "mole", "goldback"]}
const MOTION_RATE := {"silverfish":0.85, "carp":0.62, "goldfin":1.14, "graymouse":0.94, "mole":0.65, "goldback":1.2}
var rng := RandomNumberGenerator.new()
var frame: Dictionary = {}

static func price(kind: String, current_level: int) -> int:
	var base := 60 if kind == "drill" else 40
	var value := base * pow(1.65, current_level)
	if value >= float(0x7fffffffffffffff):
		return 0x7fffffffffffffff
	return ceili(value)

static func threshold(level: int) -> int:
	return 150 * level * (level + 1)

static func delivery_value(base: int, mine_level: int) -> int:
	return mini(base * mini(mine_level, 500), 500)

static func origins(count: int) -> Array:
	match count:
		3: return [Vector2(220,145), Vector2(480,145), Vector2(740,145)]
		4: return [Vector2(145,145), Vector2(368,145), Vector2(592,145), Vector2(815,145)]
		_: return HOME

static func new_crates() -> Array:
	var crates := []
	for i in CRATE_KINDS.size():
		crates.append({"kind":CRATE_KINDS[i], "pos":Vector2(315 + i*165,375), "owner":-1, "regen":0.0})
	return crates

func start(count: int = 2) -> void:
	count = clampi(count, 2, 4)
	var stations := origins(count)
	rng.randomize()
	frame = {"phase":"play", "player_count":count, "map_id":"mine", "rules":"party", "last_contest":{}, "map_cache":{}, "last_assist":{}, "last_gift":{}, "ground_x":[], "move_dir":[], "cargo":[], "appraisal_xp":[], "cutters":[], "contract_count":0, "last_sale":{}, "sales":[], "wildlife":[], "wallet":[], "earned":[], "winch":[], "drill":[],
		"oil":[], "blueprint":[], "polish":[], "tailings":[], "crates":new_crates(), "drill_time":[], "level":1, "priority":0, "hooks":[], "ores":[], "rng_state":rng.state, "project_stage":0, "project_paid":0, "project_gems":0, "project_launched":false, "opening_samples":{}, "opening_record":{}}
	for p in count:
		for key in ["wallet", "earned", "winch", "drill", "oil", "blueprint", "polish", "tailings", "wildlife"]:
			frame[key].append(0)
		frame.drill_time.append(0.0)
		frame.ground_x.append(stations[p].x + (-68.0 if stations[p].x <= 480 else 68.0))
		frame.move_dir.append(0)
		frame.cargo.append({})
		frame.appraisal_xp.append(0)
		frame.cutters.append(false)
		frame.sales.append({})
		frame.hooks.append({"station":p, "origin":stations[p], "tip":stations[p]+Vector2.DOWN*REST_LENGTH, "angle":0.0, "swing_time":0.0, "mode":"aim", "load":-1, "market":false, "crate":-1, "oiled":false, "market_notice":"", "helper":-1, "leader":-1})
	for i in REGULAR_SLOTS:
		add_slot()

func switch_map(destination: String) -> void:
	if (not FAUNA_ENABLED and destination != "mine") or destination not in BIOMES or destination == frame.map_id:
		return
	for hook in frame.hooks:
		if hook.mode != "aim":
			return
	frame.map_cache[frame.map_id] = frame.ores
	frame.map_id = destination
	frame.ores = frame.map_cache.get(destination, [])
	frame.map_cache.erase(destination)
	if destination == "mine":
		var required := REGULAR_SLOTS + (GEM_SLOTS if frame.level >= 2 else 0)
		while frame.ores.size() < required:
			add_slot()
	elif frame.ores.is_empty():
		for i in FAUNA_SLOTS:
			frame.ores.append({"owner":-1, "gone":true, "regen":0.0, "offset":Vector2.ZERO})
			spawn_wildlife(i)

func spawn_wildlife(index: int) -> void:
	var animals: Array = FAUNA[frame.map_id]
	var kind: String = animals[index % animals.size()]
	var target: Dictionary = frame.ores[index]
	# Two staggered rows, each with four separate horizontal travel corridors.
	var center := Vector2(145 + (index % 4) * 218, 295 if index < 4 else 455)
	var shift := Vector2(rng.randi_range(-15,15), rng.randi_range(-24,24))
	target.home = center + shift
	target.pos = target.home
	target.kind = kind
	target.radius = TYPES[kind][2]
	target.value = rng.randi_range(VALUE_RANGES[kind].x, VALUE_RANGES[kind].y)
	target.motion = rng.randf_range(0,TAU)
	target.facing = 1
	target.gone = false
	target.stolen = false
	target.regen = 0.0
	move_wildlife(target, 0.0)
	frame.rng_state = rng.state

func move_wildlife(target: Dictionary, step: float) -> void:
	target.motion = fmod(target.motion + step * MOTION_RATE[target.kind], TAU)
	var phase: float = target.motion
	var x: float
	var y := 0.0
	if frame.map_id == "lake":
		x = 65.0 * sin(phase)
		y = 9.0 * sin(2.0*phase)
		target.facing = 1 if cos(phase) >= 0.0 else -1
	else:
		# Each half-cycle consists of a sprint followed by a pause at the burrow.
		var run := clampf(fmod(phase,PI) / (PI*0.55),0.0,1.0)
		var distance_run := smoothstep(0.0,1.0,run) * 116.0
		if phase < PI:
			x = -58.0 + distance_run
			target.facing = 1
		else:
			x = 58.0 - distance_run
			target.facing = -1
	target.pos = target.home + Vector2(x,y)

func add_slot() -> void:
	var index: int = frame.ores.size()
	if index >= REGULAR_SLOTS + GEM_SLOTS:
		return
	var kind := "gem" if index >= REGULAR_SLOTS else "small"
	frame.ores.append({"pos":Vector2.ZERO, "home":Vector2.ZERO, "kind":kind, "radius":TYPES[kind][2],
		"value":TYPES[kind][0], "owner":-1, "gone":true, "regen":0.0, "offset":Vector2.ZERO})
	refresh_slot(index)

func refresh_slot(index: int) -> void:
	var ore: Dictionary = frame.ores[index]
	if not ore.gone or ore.owner >= 0:
		return
	var kind := "gem"
	if index < REGULAR_SLOTS:
		kind = REGULAR_KINDS[rng.randi_range(0, REGULAR_KINDS.size()-1)]
	var radius: float = TYPES[kind][2]
	for attempt in 72:
		var point := Vector2(rng.randi_range(45,915), rng.randi_range(223,552))
		if not clear_site(point, radius, kind == "gem"):
			continue
		ore.kind = kind
		ore.radius = radius
		ore.value = rng.randi_range(VALUE_RANGES[kind].x, VALUE_RANGES[kind].y)
		ore.grade = rng.randi_range(0,2)
		ore.pos = point
		ore.home = point
		ore.gone = false
		ore.stolen = false
		ore.regen = 0.0
		break
	# A crowded site retries later instead of stacking ores or growing the slot list.
	if ore.gone:
		ore.regen = 0.25
	frame.rng_state = rng.state

func clear_site(point: Vector2, radius: float, is_gem: bool) -> bool:
	for other in frame.ores:
		if not other.gone and point.distance_to(other.pos) < radius + other.radius + 9.0:
			return false
	# Materializing ahead of an already flying hook would change the target after release.
	for hook in frame.hooks:
		if hook.mode == "aim":
			continue
		var line_end: Vector2 = hook.origin
		var clearance := radius + 6.0
		if hook.mode == "out":
			line_end = hook.tip + Vector2(sin(hook.angle), cos(hook.angle)) * 1200.0
		elif hook.load >= 0:
			clearance += frame.ores[hook.load].radius
		if hook.tip.distance_squared_to(line_end) > 0.01:
			var nearest := Geometry2D.get_closest_point_to_segment(point, hook.tip, line_end)
			if point.distance_to(nearest) < clearance:
				return false
	if is_gem:
		for origin: Vector2 in origins(frame.player_count):
			if absf((point-origin).angle_to(Vector2.DOWN)) > MAX_ANGLE:
				return false
	for origin: Vector2 in origins(frame.player_count):
		if absf((point-origin).angle_to(Vector2.DOWN)) > MAX_ANGLE:
			continue
		if is_gem:
			var blocked := false
			for other in frame.ores:
				if other.gone or other.owner >= 0:
					continue
				var closest := Geometry2D.get_closest_point_to_segment(other.pos, origin, point)
				if closest.distance_to(other.pos) < other.radius + 2.0:
					blocked = true
					break
			if blocked:
				continue
		return true
	return false

func act(player: int, action: String) -> void:
	if frame.is_empty() or player < 0 or player >= frame.player_count:
		return
	if action in ["move_left", "move_right", "move_stop"]:
		if frame.hooks[player].mode == "aim" and not cutting(player):
			frame.move_dir[player] = {"move_left":-1,"move_right":1,"move_stop":0}[action]
	elif action in ["inspect", "open", "sell", "build_cutter", "cut"]:
		if at_buyer(player) and frame.hooks[player].mode == "aim":
			trade_cargo(player, action)
	elif player == 0 and action in ["rules_party", "rules_coop"]:
		if frame.hooks.all(func(h): return h.mode == "aim"):
			frame.rules = action.trim_prefix("rules_")
	elif player == 0 and action.begins_with("map_"):
		switch_map(action.trim_prefix("map_"))
	elif action in ["market", "fire"]:
		var hook: Dictionary = frame.hooks[player]
		var station := nearby_station(player)
		if hook.mode == "aim" and station >= 0 and station_user(station) == -1 and frame.cargo[player].is_empty():
			locate_hook(hook,station)
			frame.move_dir[player] = 0
			hook.market_notice = ""
			if action == "market":
				hook.market = not hook.market
			else:
				hook.mode = "out"
	elif action == "invest" and frame.project_stage < PROJECT_COSTS.size():
		var rest: int = PROJECT_COSTS[frame.project_stage] - frame.project_paid
		var payment := mini(frame.wallet[player], rest)
		frame.wallet[player] -= payment
		frame.project_paid += payment
		advance_project()
	elif action == "launch" and frame.project_stage == PROJECT_COSTS.size():
		frame.project_launched = true
		check_opening(player)
	elif action in ["winch", "drill"]:
		var cost := price(action, frame[action][player])
		if frame.wallet[player] >= cost:
			frame.wallet[player] -= cost
			frame[action][player] += 1

func advance_project() -> void:
	var stage: int = frame.project_stage
	if stage >= PROJECT_COSTS.size() or frame.project_paid < PROJECT_COSTS[stage]:
		return
	if stage == 2 and frame.project_gems < GEM_SLOTS:
		return
	frame.project_stage += 1
	frame.project_paid = 0

func tick(step: float) -> void:
	if frame.is_empty() or step <= 0.0:
		return
	var hits: Array = []
	var return_paths := []
	var starting_modes := []
	var outgoing := []
	for seat in frame.player_count:
		var returning: Dictionary = frame.hooks[seat]
		starting_modes.append(returning.mode)
		if frame.rules == "party" and returning.mode == "out" and not returning.market:
			outgoing.append({"seat":seat, "start":returning.tip, "velocity":Vector2(sin(returning.angle), cos(returning.angle)) * 520.0})
		if returning.mode == "back" and returning.load >= 0 and returning.helper < 0 and not returning.market:
			var dock := rest_tip(returning)
			var velocity: Vector2 = returning.tip.direction_to(dock) * return_speed(returning, seat)
			return_paths.append({"seat":seat, "start":returning.tip, "velocity":velocity})
	for crate in frame.crates:
		crate.regen = maxf(0.0, crate.regen - step)
		if crate.regen < 0.000001:
			crate.regen = 0.0
	# Income within one physics tick uses the same mine level for all miners.
	for i in frame.ores.size():
		var ore: Dictionary = frame.ores[i]
		if ore.gone:
			ore.regen = maxf(0.0, ore.regen - step)
			if ore.regen <= 0.000001:
				if frame.map_id == "mine":
					refresh_slot(i)
				else:
					spawn_wildlife(i)
		elif frame.map_id != "mine" and ore.owner < 0:
			move_wildlife(ore, step)
	for p in frame.player_count:
		if cutting(p):
			var cargo: Dictionary = frame.cargo[p]
			cargo.cut_left = maxf(0.0, cargo.cut_left - step)
			if cargo.cut_left < 0.000001:
				cargo.cut_left = 0.0
				cargo.cut = true
				cargo.quote = cut_price(cargo.quote)
		if starting_modes[p] == "aim" and frame.move_dir[p] != 0:
			var speed := 200.0 if frame.cargo[p].is_empty() else 130.0
			frame.ground_x[p] = clampf(frame.ground_x[p] + frame.move_dir[p]*speed*step, 20.0, 940.0)
			var station := nearby_station(p)
			if station < 0 or station_user(station) >= 0:
				frame.hooks[p].market = false
			else:
				locate_hook(frame.hooks[p],station)
		var wildlife_income := floori(frame.wildlife[p] / 5.0) if FAUNA_ENABLED else 0
		if frame.drill[p] > 0 or frame.tailings[p] > 0 or wildlife_income > 0:
			frame.drill_time[p] += step
			var payouts := floori((frame.drill_time[p] + 0.000001) / DRILL_PERIOD)
			if payouts > 0:
				frame.drill_time[p] = maxf(0.0, frame.drill_time[p] - payouts * DRILL_PERIOD)
				credit(p, payouts * (5 * frame.drill[p] * frame.level + 2 * frame.tailings[p] + wildlife_income))
		var hook: Dictionary = frame.hooks[p]
		match starting_modes[p]:
			"aim":
				hook.swing_time += step
				hook.angle = sin(hook.swing_time * 1.85) * MAX_ANGLE * (1 if p % 2 == 0 else -1)
				hook.tip = rest_tip(hook)
			"out":
				extend_hook(hook, p, step, hits, return_paths)
	append_clashes(outgoing, hits)
	hits.sort_custom(func(a, b):
		if is_equal_approx(a.t, b.t):
			return posmod(a.player - frame.priority, frame.player_count) < posmod(b.player - frame.priority, frame.player_count)
		return a.t < b.t)
	var resolved := {}
	for hit in hits:
		if resolved.has(hit.player):
			continue
		var hook: Dictionary = frame.hooks[hit.player]
		if hook.load >= 0 or hook.leader >= 0:
			continue
		if hit.has("peer"):
			if resolved.has(hit.peer):
				continue
			var other: Dictionary = frame.hooks[hit.peer]
			hook.mode = "back"
			other.mode = "back"
			hook.tip = hit.point
			other.tip = hit.other_point
			resolved[hit.player] = true
			resolved[hit.peer] = true
			contest("clash", hit.player, hit.peer, (hook.tip + other.tip) * 0.5)
			continue
		if hit.has("lead"):
			var lead: Dictionary = frame.hooks[hit.lead]
			if lead.mode == "back" and lead.load >= 0 and lead.helper < 0:
				if frame.rules == "party":
					var cargo: Dictionary = frame.ores[lead.load]
					if cargo.get("stolen",false):
						continue
					lead.tip = hit.cargo_tip
					cargo.pos = lead.tip + cargo.offset
					hook.tip = hit.point
					hook.mode = "back"
					hook.load = lead.load
					cargo.owner = hit.player
					cargo.offset = cargo.pos - hook.tip
					cargo.stolen = true
					lead.load = -1
					lead.oiled = false
					consume_oil(hook, hit.player, cargo.kind)
					contest("steal", hit.player, hit.lead, hook.tip)
				else:
					hook.mode = "assist"
					hook.leader = hit.lead
					hook.tip = lead.tip
					lead.helper = hit.player
				resolved[hit.player] = true
			continue
		if hit.has("crate"):
			reserve_crate(hook, hit)
			continue
		var ore: Dictionary = frame.ores[hit.ore]
		if hook.load < 0 and ore.owner == -1:
			hook.load = hit.ore
			hook.mode = "back"
			hook.tip = hit.point
			ore.offset = ore.pos - hit.point
			ore.owner = hit.player
			consume_oil(hook, hit.player, ore.kind)
			resolved[hit.player] = true
	for p in frame.player_count:
		if starting_modes[p] == "back":
			retract(frame.hooks[p], p, step)
	for hook in frame.hooks:
		if hook.leader >= 0:
			hook.tip = frame.hooks[hook.leader].tip
	frame.priority = (frame.priority + 1) % frame.player_count
	var total := 0
	for income: int in frame.earned:
		total += income
	while total >= threshold(frame.level):
		frame.level += 1
		if frame.level == 2 and frame.map_id == "mine":
			for i in GEM_SLOTS:
				add_slot()

func append_clashes(outgoing: Array, hits: Array) -> void:
	for i in outgoing.size():
		var first: Dictionary = outgoing[i]
		for j in range(i+1, outgoing.size()):
			var other: Dictionary = outgoing[j]
			var seconds := swept_contact_time(first.start - other.start, first.velocity - other.velocity, ASSIST_RADIUS)
			if seconds < 0.0:
				continue
			var distance := seconds * 520.0
			if distance > first.start.distance_to(frame.hooks[first.seat].tip) + 0.0001 or distance > other.start.distance_to(frame.hooks[other.seat].tip) + 0.0001:
				continue
			hits.append({"t":distance, "player":first.seat, "peer":other.seat,
				"point":first.start+first.velocity*seconds, "other_point":other.start+other.velocity*seconds})

func consume_oil(hook: Dictionary, p: int, kind: String) -> void:
	if kind in ["giant", "rock"] and frame.oil[p] > 0:
		frame.oil[p] -= 1
		hook.oiled = true

func contest(kind: String, a: int, b: int, point: Vector2) -> void:
	frame.last_contest = {"id":frame.last_contest.get("id",0)+1,"kind":kind,"a":a,"b":b,"point":point}

func reserve_crate(hook: Dictionary, hit: Dictionary) -> void:
	var index: int = hit.crate
	var crate: Dictionary = frame.crates[index]
	if crate.owner >= 0 or crate.regen > 0.0 or hook.crate >= 0 or hook.market_notice == "funds":
		return
	hook.mode = "back"
	hook.tip = hit.point
	if frame.wallet[hit.player] < CRATE_PRICES[index]:
		hook.market_notice = "funds"
		return
	frame.wallet[hit.player] -= CRATE_PRICES[index]
	crate.owner = hit.player
	hook.crate = index
	hook.market_notice = "reserved"

func gift(sender: int, recipient: int, amount: Variant) -> String:
	if frame.is_empty() or sender < 0 or sender >= frame.player_count:
		return "sender"
	if recipient < 0 or recipient >= frame.player_count:
		return "recipient"
	if sender == recipient:
		return "self"
	if not amount is int or amount <= 0:
		return "amount"
	if amount > frame.wallet[sender]:
		return "funds"
	if frame.wallet[recipient] > 0x7fffffffffffffff - amount:
		return "overflow"
	frame.wallet[sender] -= amount
	frame.wallet[recipient] += amount
	var previous: int = frame.last_gift.get("id", 0)
	var next_id := 1 if previous == 0x7fffffffffffffff else previous + 1
	frame.last_gift = {"id":next_id, "sender":sender, "recipient":recipient, "amount":amount}
	return "ok"

func credit(player: int, amount: int) -> void:
	frame.wallet[player] += amount
	frame.earned[player] += amount

func extend_hook(hook: Dictionary, p: int, dt: float, hits: Array, return_paths: Array) -> void:
	var from: Vector2 = hook.tip
	var direction := Vector2(sin(hook.angle), cos(hook.angle))
	var side_distance := INF
	if direction.x != 0.0:
		var edge := 948.0 if direction.x > 0 else 12.0
		side_distance = (edge - from.x) / direction.x
	var wall_distance := minf(side_distance, (583.0 - from.y) / direction.y)
	var length := minf(520.0 * dt, maxf(0.0, wall_distance))
	var to := from + direction * length
	var targets: Array = frame.crates if hook.market else frame.ores
	for i in targets.size():
		var target: Dictionary = targets[i]
		if target.owner >= 0 or target.get("gone",false) or target.regen > 0.0:
			continue
		var gap: Vector2 = target.pos - from
		var along := gap.dot(direction)
		var perp_sq := gap.length_squared() - along * along
		var radius: float = target.get("radius",CRATE_RADIUS)
		var radius_sq := radius * radius
		if perp_sq > radius_sq:
			continue
		var half_chord := sqrt(maxf(0.0, radius_sq - perp_sq))
		var entry := maxf(0.0, along - half_chord)
		if along + half_chord >= 0 and entry <= length:
			var hit := {"player":p, "t":entry, "point":from + direction * entry}
			hit["crate" if hook.market else "ore"] = i
			hits.append(hit)
	if not hook.market:
		for path in return_paths:
			var lead: Dictionary = frame.hooks[path.seat]
			var relative: Vector2 = from - path.start
			var velocity: Vector2 = direction * 520.0 - path.velocity
			var second := swept_contact_time(relative, velocity, ASSIST_RADIUS)
			if second < 0.0 or second * 520.0 > length:
				continue
			var contact: Vector2 = path.start + path.velocity * second
			# Ignore anything already inside the docking area, including a path extrapolated past the dock.
			var remaining: float = path.start.distance_to(rest_tip(lead)) - path.velocity.length() * second
			if remaining > 0.0 and contact.distance_to(lead.origin) > ASSIST_MIN_DISTANCE:
				hits.append({"player":p, "lead":path.seat, "t":second * 520.0, "point":from + direction * second * 520.0, "cargo_tip":contact})
	hook.tip = to
	if length >= wall_distance:
		hook.mode = "back"

# Earliest contact between a moving tip and a moving circle in relative space.
func swept_contact_time(relative: Vector2, velocity: Vector2, radius: float) -> float:
	var c := relative.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var a := velocity.length_squared()
	var b := relative.dot(velocity)
	var discriminant := b * b - a * c
	if a < 0.000001 or b >= 0.0 or discriminant < 0.0:
		return -1.0
	return (-b - sqrt(discriminant)) / a

func rest_tip(hook: Dictionary) -> Vector2:
	return hook.origin + Vector2(sin(hook.angle), cos(hook.angle)) * REST_LENGTH

static func station_type(station: int) -> Dictionary:
	return STATION_TYPES[station % STATION_TYPES.size()]

func return_speed(hook: Dictionary, p: int) -> float:
	var speed := 350.0
	if hook.load >= 0:
		var kind: String = frame.ores[hook.load].kind
		speed = TYPES[kind][1]
		if kind in station_type(hook.station).kinds:
			speed *= STATION_BONUS
	if hook.oiled:
		speed *= 2.0
	if hook.helper >= 0:
		speed *= ASSIST_SPEED
	return speed * (1.0 + 0.25 * frame.winch[p])

func retract(hook: Dictionary, p: int, dt: float) -> void:
	var speed := return_speed(hook,p)
	var dock := rest_tip(hook)
	var tip: Vector2 = hook.tip
	hook.tip = tip.move_toward(dock, speed * dt)
	if hook.load >= 0:
		var ore: Dictionary = frame.ores[hook.load]
		ore.pos = hook.tip + ore.offset
	if hook.tip == dock:
		if hook.load >= 0:
			var ore: Dictionary = frame.ores[hook.load]
			var payment := delivery_value(ore.value, frame.level)
			if ore.kind == "gem" and frame.polish[p] > 0:
				payment = mini(floori(payment * 1.5), 500)
				frame.polish[p] -= 1
			var helper_seat: int = hook.helper
			if helper_seat >= 0:
				var helper: Dictionary = frame.hooks[helper_seat]
				helper.tip = hook.tip
				helper.mode = "back"
				helper.leader = -1
				hook.helper = -1
			if frame.map_id == "mine":
				# A generated rock keeps its grade through stealing, carrying and reloading.
				var grade: int = ore.get("grade", posmod(roundi(ore.home.x)+roundi(ore.home.y)+ore.value,3))
				frame.cargo[p] = {"kind":ore.kind, "base":payment, "gem_row":posmod(ore.value,2), "quote":cargo_quote(payment,grade,false),
					"grade":grade,"opened":false, "inspected":false, "cut":false, "cut_left":0.0, "helper":helper_seat}
			else:
				pay_delivery(p,helper_seat,payment)
				frame.wildlife[p] += 1
			ore.gone = true
			ore.regen = TYPES[ore.kind][3]
			ore.owner = -1
			ore.pos = ore.home
			ore.offset = Vector2.ZERO
		if hook.crate >= 0:
			var crate: Dictionary = frame.crates[hook.crate]
			frame[crate.kind][p] += CRATE_CHARGES[hook.crate]
			crate.owner = -1
			crate.regen = STOCK_DELAY
			hook.market_notice = crate.kind
		elif hook.market and hook.market_notice != "funds":
			hook.market_notice = "miss"
		hook.crate = -1
		hook.market = false
		hook.oiled = false
		hook.load = -1
		hook.mode = "aim"

func nearby_station(p: int) -> int:
	var stations := origins(frame.player_count)
	for i in stations.size():
		if absf(frame.ground_x[p] - stations[i].x) <= 32.0:
			return i
	return -1

func station_user(station: int) -> int:
	for p in frame.player_count:
		var hook: Dictionary = frame.hooks[p]
		if hook.mode != "aim" and hook.station == station:
			return p
	return -1

func locate_hook(hook: Dictionary, station: int) -> void:
	if hook.station != station:
		hook.station = station
		hook.origin = origins(frame.player_count)[station]
		hook.tip = rest_tip(hook)

func at_winch(p: int) -> bool:
	var station := nearby_station(p)
	return station >= 0 and station_user(station) in [-1,p]

func at_buyer(p: int) -> bool:
	return absf(frame.ground_x[p]-45.0) <= 45.0 or absf(frame.ground_x[p]-915.0) <= 45.0

static func cargo_quote(base: int, grade: int, opened: bool) -> int:
	var percent: int = [65,100,145][grade] if opened else 85
	return clampi(floori(base * percent / 100.0),1,500)

static func contract_matches(completed: int, cargo: Dictionary) -> bool:
	if cargo.is_empty():
		return false
	match completed % CONTRACT_NAMES.size():
		0: return not cargo.opened
		1: return cargo.opened
		_: return cargo.opened and cargo.grade >= 1

static func inspection_hint(cargo: Dictionary) -> String:
	if not cargo.get("inspected",false) or cargo.opened:
		return ""
	if cargo.grade == 2 or (cargo.grade == 1 and cargo.base % 2 == 0):
		return "通透"
	return "多裂"

static func cut_price(quote: int) -> int:
	return mini(500, floori(quote * 1.25))

func cutting(p: int) -> bool:
	return frame.cargo[p].get("cut_left",0.0) > 0.0

func trade_cargo(p: int, action: String) -> void:
	var cargo: Dictionary = frame.cargo[p]
	if cargo.is_empty() or cutting(p):
		return
	if action == "build_cutter":
		if not frame.cutters[p] and cargo.opened and cargo.grade == 2 and cargo.helper < 0:
			frame.cutters[p] = true
			frame.cargo[p] = {}
		return
	if action == "cut":
		if frame.cutters[p] and cargo.opened and not cargo.get("cut",false) and frame.wallet[p] >= CUT_COST and (cut_price(cargo.quote) - cargo.quote > CUT_COST or needs_exhibit(cargo)):
			frame.wallet[p] -= CUT_COST
			frame.move_dir[p] = 0
			cargo.cut_left = CUT_SECONDS
			cargo.exhibit = cut_price(cargo.quote) - cargo.quote <= CUT_COST
		return
	if action == "inspect":
		if frame.appraisal_xp[p] >= LAMP_UNLOCK and not cargo.opened:
			cargo.inspected = true
		return
	if action == "open":
		if not cargo.opened:
			frame.appraisal_xp[p] += 1
			cargo.opened = true
			cargo.quote = cargo_quote(cargo.base, cargo.grade, true)
		return
	frame.cargo[p] = {}
	var contract: int = frame.contract_count % CONTRACT_NAMES.size()
	var bonus := 0
	if contract_matches(frame.contract_count, cargo):
		bonus = CONTRACT_BONUSES[contract]
		frame.contract_count += 1
	var share := pay_delivery(p, cargo.helper, cargo.quote)
	if bonus > 0:
		credit(p, bonus)
	var receipt := {"id":frame.last_sale.get("id",0)+1, "seller":p, "price":cargo.quote, "helper":cargo.helper,
		"share":share, "bonus":bonus, "net":cargo.quote-share+bonus, "contract":contract}
	frame.sales[p] = receipt
	frame.last_sale = receipt
	if cargo.get("cut",false):
		var color := product_color(cargo)
		if not frame.opening_samples.has(color):
			frame.opening_samples[color] = {"sale":receipt.id, "seller":p, "price":cargo.quote}
		check_opening(p)
	if cargo.kind == "gem":
		frame.project_gems = mini(frame.project_gems+1,GEM_SLOTS)
		advance_project()
	if cargo.kind == "rock" and frame.blueprint[p] > 0:
		frame.blueprint[p] -= 1
		frame.tailings[p] += 1

static func product_color(cargo: Dictionary) -> String:
	return "green" if cargo.get("gem_row", posmod(int(cargo.get("base",0)),2)) == 0 else "red"

func needs_exhibit(cargo: Dictionary) -> bool:
	return frame.project_launched and not frame.opening_samples.has(product_color(cargo))

func check_opening(p: int) -> void:
	if not frame.opening_record.is_empty() or not frame.project_launched or frame.opening_samples.size() != 2:
		return
	frame.opening_record = {"miner":p, "sales":frame.last_sale.id, "contracts":frame.contract_count}

func restore_opening(data: Dictionary, count: int) -> bool:
	# Historical receipts do not record whether an item was cut or its color.
	data.merge({"opening_samples":{}, "opening_record":{}})
	if not data.opening_samples is Dictionary or not data.opening_record is Dictionary:
		return false
	for color in data.opening_samples:
		var stamp: Variant = data.opening_samples[color]
		if color not in ["red","green"] or not stamp is Dictionary:
			return false
		if not stamp.get("seller") is int or stamp.seller < 0 or stamp.seller >= count or not stamp.get("price") is int or stamp.price < 1 or stamp.price > 500:
			return false
		if not stamp.get("sale") is int or stamp.sale < 1 or stamp.sale > data.last_sale.get("id",0):
			return false
	var ready: bool = data.project_launched and data.opening_samples.size()==2
	var record: Dictionary = data.opening_record
	if record.is_empty():
		return not ready
	return ready and record.get("miner") is int and record.miner >= 0 and record.miner < count and record.get("sales") is int and record.sales >= 2 and record.sales <= data.last_sale.get("id",0) and record.get("contracts") is int and record.contracts >= 0 and record.contracts <= data.contract_count

func pay_delivery(p: int, helper: int, payment: int) -> int:
	var share := 0
	if helper >= 0:
		share = floori(payment * 0.2)
		frame.last_assist = {"id":frame.last_assist.get("id",0)+1, "lead":p, "helper":helper, "price":payment,"share":share}
		credit(helper,share)
		payment -= share
	credit(p,payment)
	return share

func restore_ground(data: Dictionary, count: int) -> bool:
	if not data.has("ground_x"):
		data.ground_x = []
		data.move_dir = []
		data.cargo = []
		for station: Vector2 in origins(count):
			data.ground_x.append(station.x)
			data.move_dir.append(0)
			data.cargo.append({})
	if not data.has("appraisal_xp"):
		data.appraisal_xp = []
		data.appraisal_xp.resize(count)
		data.appraisal_xp.fill(0)
	if not data.has("cutters"):
		data.cutters = []
		data.cutters.resize(count)
		data.cutters.fill(false)
	for key in ["ground_x", "move_dir", "cargo", "appraisal_xp", "cutters"]:
		if not data.get(key) is Array or data[key].size() != count:
			return false
	for p in count:
		if not data.cutters[p] is bool or not data.appraisal_xp[p] is int or data.appraisal_xp[p] < 0:
			return false
		var x: Variant = data.ground_x[p]
		if not x is float or not is_finite(x) or x < 20.0 or x > 940.0 or data.move_dir[p] not in [-1,0,1]:
			return false
		if not data.cargo[p] is Dictionary:
			return false
		var c: Dictionary = data.cargo[p]
		if c.is_empty():
			continue
		c.inspected = c.get("inspected",false)
		if not c.inspected is bool or (c.inspected and data.appraisal_xp[p] < LAMP_UNLOCK):
			return false
		if not TYPES.has(c.get("kind")) or MOTION_RATE.has(c.kind) or data.hooks[p].mode != "aim":
			return false
		if not c.get("base") is int or c.base < 1 or c.base > 500 or c.get("grade") not in [0,1,2] or not c.get("opened") is bool:
			return false
		c.merge({"cut":false, "cut_left":0.0, "gem_row":posmod(c.base,2), "exhibit":false})
		if not c.exhibit is bool or c.gem_row not in [0,1]:
			return false
		if not c.cut is bool or not c.cut_left is float or not is_finite(c.cut_left) or c.cut_left < 0.0 or c.cut_left > CUT_SECONDS:
			return false
		var price_before := cargo_quote(c.base,c.grade,c.opened)
		if c.cut or c.cut_left > 0.0:
			if not data.cutters[p] or not c.opened or (cut_price(price_before) - price_before <= CUT_COST and not (c.exhibit and data.get("project_launched",false))):
				return false
		if c.cut_left > 0.0 and (c.cut or data.move_dir[p] != 0 or minf(absf(x-45),absf(x-915)) > 45):
			return false
		var expected := cut_price(price_before) if c.cut else price_before
		if c.get("quote") != expected or not c.get("helper") is int or c.helper < -1 or c.helper >= count or c.helper == p:
			return false
	return true

func restore(saved: Variant) -> bool:
	if not saved is Dictionary or saved.get("phase") != "play":
		return false
	var count: Variant = saved.get("player_count",2)
	if not count is int or count < 2 or count > 4:
		return false
	var stations := origins(count)
	for key in ["wallet", "earned", "drill", "winch", "drill_time", "hooks"]:
		if not saved.get(key) is Array or saved[key].size() != count:
			return false
	if not saved.get("level") is int or saved.level < 1 or not saved.get("priority") is int or saved.priority < 0 or saved.priority >= count:
		return false
	var biome: Variant = saved.get("map_id","mine")
	if biome not in BIOMES:
		return false
	var size := (16 if saved.level == 1 else 18) if biome == "mine" else FAUNA_SLOTS
	if not saved.get("ores") is Array or saved.ores.size() != size:
		return false
	for p in count:
		for key in ["wallet", "earned", "drill", "winch"]:
			if not saved[key][p] is int or saved[key][p] < 0:
				return false
		if not saved.drill_time[p] is float or not is_finite(saved.drill_time[p]) or saved.drill_time[p] < 0 or saved.drill_time[p] >= DRILL_PERIOD:
			return false
		var hook: Variant = saved.hooks[p]
		if not hook is Dictionary:
			return false
		var station: Variant = hook.get("station",p)
		if not station is int or station < 0 or station >= count:
			return false
		if hook.get("origin") != stations[station] or not hook.get("tip") is Vector2 or not hook.tip.is_finite():
			return false
		if not hook.get("angle") is float or not is_finite(hook.angle) or not hook.get("swing_time") is float or not is_finite(hook.swing_time):
			return false
		if hook.get("mode") not in ["aim", "out", "back", "assist"] or not hook.get("load") is int or hook.load < -1 or hook.load >= saved.ores.size():
			return false
	for i in saved.ores.size():
		var ore: Variant = saved.ores[i]
		if not valid_target(ore, biome, count):
			return false
		for p in count:
			if (saved.hooks[p].load == i) != (ore.owner == p):
				return false
		if ore.owner >= 0 and (ore.gone or saved.hooks[ore.owner].mode != "back"):
			return false
	var migrated: Dictionary = saved.duplicate(true)
	var occupied: Array = []
	for p in count:
		var hook: Dictionary = migrated.hooks[p]
		hook.station = hook.get("station",p)
		if hook.mode != "aim":
			if occupied.has(hook.station):
				return false
			occupied.append(hook.station)
	migrated.map_id = biome
	migrated.rules = migrated.get("rules", "coop")
	if migrated.rules not in ["party", "coop"]:
		return false
	migrated.last_contest = migrated.get("last_contest", {})
	if not migrated.last_contest is Dictionary:
		return false
	if not migrated.last_contest.is_empty():
		var event: Dictionary = migrated.last_contest
		if not event.get("id") is int or event.get("kind") not in ["clash", "steal"] or not event.get("point") is Vector2:
			return false
		for key in ["a", "b"]:
			if not event.get(key) is int or event[key] < 0 or event[key] >= count:
				return false
	migrated.player_count = count
	if not migrated.has("last_gift"):
		migrated.last_gift = {}
	if not migrated.last_gift is Dictionary:
		return false
	if not migrated.last_gift.is_empty():
		var receipt: Dictionary = migrated.last_gift
		for key in ["id", "sender", "recipient", "amount"]:
			if not receipt.get(key) is int:
				return false
		if receipt.id < 1 or receipt.amount < 1 or receipt.sender == receipt.recipient:
			return false
		if receipt.sender < 0 or receipt.sender >= count or receipt.recipient < 0 or receipt.recipient >= count:
			return false
	if not migrated.has("last_assist"):
		migrated.last_assist = {}
	if not migrated.last_assist is Dictionary:
		return false
	if not migrated.last_assist.is_empty():
		for key in ["id", "lead", "helper", "price", "share"]:
			if not migrated.last_assist.get(key) is int:
				return false
		for key in ["lead", "helper"]:
			if migrated.last_assist[key] < 0 or migrated.last_assist[key] >= count:
				return false
	if not migrated.has("map_cache"):
		migrated.map_cache = {}
	if not migrated.map_cache is Dictionary or migrated.map_cache.size() > 2:
		return false
	for key in migrated.map_cache:
		if key not in BIOMES or key == biome or not migrated.map_cache[key] is Array:
			return false
		var cached: Array = migrated.map_cache[key]
		if key == "mine" and cached.size() not in [16,18]:
			return false
		if key != "mine" and cached.size() != FAUNA_SLOTS:
			return false
		for ore in cached:
			if not valid_target(ore, key, count) or ore.owner != -1 or not ore.has("value"):
				return false
	if not restore_market(migrated, count) or not restore_ground(migrated,count) or not restore_sales(migrated,count):
		return false
	for ore in migrated.ores:
		ore.stolen = ore.get("stolen",false)
		var bounds: Vector2i = VALUE_RANGES[ore.kind]
		if not ore.has("value"):
			ore.value = TYPES[ore.kind][0]
		elif not ore.value is int or ore.value < bounds.x or ore.value > bounds.y:
			return false
	var stage: Variant = migrated.get("project_stage", 0)
	var paid: Variant = migrated.get("project_paid", 0)
	var gems: Variant = migrated.get("project_gems", 0)
	var launched: Variant = migrated.get("project_launched", false)
	if not stage is int or stage < 0 or stage > PROJECT_COSTS.size() or not paid is int or paid < 0:
		return false
	if paid > (0 if stage == PROJECT_COSTS.size() else PROJECT_COSTS[stage]):
		return false
	if not gems is int or gems < 0 or gems > GEM_SLOTS or not launched is bool or (launched and stage != PROJECT_COSTS.size()):
		return false
	migrated.merge({"project_stage":stage, "project_paid":paid, "project_gems":gems, "project_launched":launched})
	if not restore_opening(migrated,count):
		return false
	if migrated.has("rng_state"):
		if not migrated.rng_state is int:
			return false
		rng.state = migrated.rng_state
	else:
		rng.randomize()
		migrated.rng_state = rng.state
	frame = migrated
	if not FAUNA_ENABLED and biome != "mine":
		for target in frame.ores:
			if target.owner >= 0:
				target.owner = -1
				target.pos = target.home
				target.stolen = false
		# Recover the mine before the next tick, keeping paid supply deliveries intact.
		frame.map_cache[biome] = frame.ores
		frame.map_id = "mine"
		frame.ores = frame.map_cache.get("mine", [])
		frame.map_cache.erase("mine")
		while frame.ores.size() < REGULAR_SLOTS + (GEM_SLOTS if frame.level >= 2 else 0):
			add_slot()
		for hook in frame.hooks:
			if hook.crate < 0:
				hook.merge({"mode":"aim", "load":-1, "helper":-1, "leader":-1, "tip":rest_tip(hook), "market":false, "oiled":false}, true)
	return true

func restore_market(data: Dictionary, count: int) -> bool:
	for key in ["oil", "blueprint", "polish", "tailings", "wildlife"]:
		if not data.has(key):
			data[key] = []
			data[key].resize(count)
			data[key].fill(0)
		if not data[key] is Array or data[key].size() != count:
			return false
		for amount in data[key]:
			if not amount is int or amount < 0:
				return false
	var defaults := new_crates()
	if not data.has("crates"):
		data.crates = defaults
	if not data.crates is Array or data.crates.size() != defaults.size():
		return false
	for hook in data.hooks:
		hook.merge({"crate":-1, "market":false, "oiled":false, "market_notice":"", "helper":-1, "leader":-1})
		if not hook.crate is int or hook.crate < -1 or hook.crate >= defaults.size() or not hook.market is bool or not hook.oiled is bool or not hook.market_notice is String:
			return false
		if hook.crate >= 0 and (hook.load >= 0 or not hook.market or hook.mode != "back"):
			return false
		if hook.oiled and (hook.load < 0 or data.ores[hook.load].kind not in ["giant", "rock"]):
			return false
	for p in count:
		var hook: Dictionary = data.hooks[p]
		for field in ["helper", "leader"]:
			if not hook[field] is int or hook[field] < -1 or hook[field] >= count or hook[field] == p:
				return false
		if (hook.mode == "assist") != (hook.leader >= 0):
			return false
		if hook.leader >= 0:
			if hook.helper >= 0 or hook.load >= 0 or hook.market or data.hooks[hook.leader].helper != p:
				return false
		if hook.helper >= 0 and (hook.mode != "back" or hook.load < 0 or data.hooks[hook.helper].leader != p):
			return false
	for i in defaults.size():
		var crate: Variant = data.crates[i]
		if not crate is Dictionary or crate.get("pos") != defaults[i].pos or crate.get("kind") != defaults[i].kind:
			return false
		if not crate.get("owner") is int or crate.owner < -1 or crate.owner >= count or not crate.get("regen") is float or not is_finite(crate.regen) or crate.regen < 0.0 or crate.regen > STOCK_DELAY:
			return false
		if crate.owner >= 0 and crate.regen > 0.0:
			return false
		for p in count:
			if (data.hooks[p].crate == i) != (crate.owner == p):
				return false
	return true

func valid_target(ore: Variant, biome: String, count: int) -> bool:
	if not ore is Dictionary or not TYPES.has(ore.get("kind")) or ore.get("radius") != TYPES[ore.kind][2]:
		return false
	for key in ["pos", "home", "offset"]:
		if not ore.get(key) is Vector2 or not ore[key].is_finite():
			return false
	if not ore.get("owner") is int or ore.owner < -1 or ore.owner >= count or not ore.get("gone") is bool or not ore.get("regen") is float or not is_finite(ore.regen) or ore.regen < 0.0:
		return false
	if ore.get("grade",0) not in [0,1,2] or not ore.get("stolen",false) is bool:
		return false
	if ore.has("value") and (not ore.value is int or ore.value < VALUE_RANGES[ore.kind].x or ore.value > VALUE_RANGES[ore.kind].y):
		return false
	if biome == "mine":
		return not MOTION_RATE.has(ore.kind)
	return ore.kind in FAUNA[biome] and ore.get("motion") is float and is_finite(ore.motion) and ore.get("facing") in [-1,1]

func restore_sales(data: Dictionary, count: int) -> bool:
	if not data.has("contract_count"):
		data.contract_count = 0
	if not data.get("contract_count") is int or data.contract_count < 0:
		return false
	if not data.has("sales"):
		data.sales = []
		for p in count:
			data.sales.append({})
	if not data.sales is Array or data.sales.size() != count:
		return false
	var newest := {}
	for seller in count:
		var receipt: Variant = data.sales[seller]
		if not receipt is Dictionary:
			return false
		if receipt.is_empty():
			continue
		for key in ["id", "seller", "price", "helper", "share", "bonus", "net", "contract"]:
			if not receipt.get(key) is int:
				return false
		if receipt.id < 1 or receipt.seller != seller or receipt.price < 1 or receipt.price > 500 or receipt.contract < 0 or receipt.contract >= CONTRACT_NAMES.size():
			return false
		if receipt.helper < -1 or receipt.helper >= count or receipt.helper == seller:
			return false
		if receipt.bonus not in [0, CONTRACT_BONUSES[receipt.contract]] or receipt.net != receipt.price - receipt.share + receipt.bonus:
			return false
		var share := floori(receipt.price * 0.2) if receipt.helper >= 0 else 0
		if receipt.share != share:
			return false
		if receipt.id > newest.get("id",0):
			newest = receipt
	if data.get("last_sale",newest) != newest:
		return false
	data.last_sale = newest
	return true
