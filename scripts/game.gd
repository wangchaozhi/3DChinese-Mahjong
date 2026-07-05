class_name MahjongGame
extends Node
## 游戏状态机:座位 0 为人类玩家,1-3 为 AI(1=下家,2=对家,3=上家)。
## 逆时针行牌;吃只能吃上家。

signal changed
signal announce(seat: int, text: String)
signal ask_actions(data: Dictionary)
signal round_over(result: Dictionary)
signal round_started
signal tile_drawn(seat: int)
signal tile_discarded(seat: int, id: int)

signal _human_choice(choice: Dictionary)

const HUMAN := 0

var wall: Array = []
var wall_slot := {}              # id -> 牌墙固定槽位(用于 3D 摆放)
var hands := [[], [], [], []]    # 各家手牌 id 列表
var melds := [[], [], [], []]    # 副露 {type, tiles, kind, from}
var rivers := [[], [], [], []]   # 牌河
var scores := [0, 0, 0, 0]
var dealer := 0
var hand_no := 1
var cur := 0
var phase := "idle"              # idle / playing / over
var last_discard_id := -1
var last_discarder := -1
var drawn_id := -1
var revealed := false
var result := {}

var _skip_draw := false          # 碰/吃后直接进入出牌
var _next_draw_from_end := false # 明杠后从墙尾补牌


static func kind_of(id: int) -> int:
	return id >> 2


func counts_of(seat: int) -> Array:
	var c := []
	c.resize(34)
	c.fill(0)
	for id in hands[seat]:
		c[kind_of(id)] += 1
	return c


func seat_wind(seat: int) -> int:
	return (seat - dealer + 4) % 4


## 所有玩家可见的牌(牌河 + 副露)按种类计数,供 AI 判断死牌。
func visible_counts() -> Array:
	var c := []
	c.resize(34)
	c.fill(0)
	for s in 4:
		for id in rivers[s]:
			c[kind_of(id)] += 1
		for m in melds[s]:
			for id2 in m["tiles"]:
				c[kind_of(id2)] += 1
	return c


func first_id_of_kind(seat: int, k: int) -> int:
	for id in hands[seat]:
		if kind_of(id) == k:
			return id
	return -1


func submit(choice: Dictionary) -> void:
	_human_choice.emit(choice)


func start_round() -> void:
	if phase == "playing":
		return
	wall.clear()
	for i in 136:
		wall.append(i)
	wall.shuffle()
	hands = [[], [], [], []]
	melds = [[], [], [], []]
	rivers = [[], [], [], []]
	last_discard_id = -1
	last_discarder = -1
	drawn_id = -1
	revealed = false
	result = {}
	_skip_draw = false
	_next_draw_from_end = false
	for _r in 13:
		for s in 4:
			hands[(dealer + s) % 4].append(wall.pop_back())
	wall_slot.clear()
	for i in wall.size():
		wall_slot[wall[i]] = i
	for s in 4:
		hands[s].sort()
	cur = dealer
	phase = "playing"
	round_started.emit()
	changed.emit()
	_game_loop()


func next_round() -> void:
	if phase != "over":
		return
	var w: int = result.get("winner", -1)
	if w != -1 and w != dealer:
		dealer = (dealer + 1) % 4
	hand_no += 1
	phase = "idle"
	start_round()


func _game_loop() -> void:
	await _delay(1.15)
	while phase == "playing":
		await _do_turn(cur)


func _delay(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _draw_tile(p: int, from_end := false) -> bool:
	if wall.is_empty():
		return false
	var id: int
	if from_end:
		id = wall.pop_front()
	else:
		id = wall.pop_back()
	hands[p].append(id)
	drawn_id = id
	changed.emit()
	tile_drawn.emit(p)
	return true


func _do_turn(p: int) -> void:
	var gang_flower := false
	var just_drew := false
	if _skip_draw:
		_skip_draw = false
	else:
		var from_end := _next_draw_from_end
		_next_draw_from_end = false
		gang_flower = from_end
		if not _draw_tile(p, from_end):
			_end_round_draw()
			return
		just_drew = true
		await _delay(0.2)
	while phase == "playing":
		var counts := counts_of(p)
		var can_zimo := just_drew and Rules.can_win_counts(counts)
		var angangs := _angang_options(p) if just_drew else []
		var bugangs := _bugang_options(p) if just_drew else []
		var choice: Dictionary
		if p == HUMAN:
			var acts := []
			if can_zimo:
				acts.append({"action": "hu"})
			for k in angangs:
				acts.append({"action": "angang", "kind": k})
			for k in bugangs:
				acts.append({"action": "bugang", "kind": k})
			ask_actions.emit({"mode": "turn", "actions": acts})
			choice = await _human_choice
		else:
			await _delay(0.6)
			choice = AI.turn_choice(counts, melds[p].size(), can_zimo, angangs, bugangs,
					visible_counts())
		match choice.get("action", ""):
			"hu":
				announce.emit(p, "自摸")
				_win(p, -1, {"zimo": true, "gang_flower": gang_flower, "haidi": wall.is_empty()})
				return
			"angang":
				_do_angang(p, choice["kind"])
				announce.emit(p, "暗杠")
				changed.emit()
				await _delay(0.8)
				if not _draw_tile(p, true):
					_end_round_draw()
					return
				just_drew = true
				gang_flower = true
			"bugang":
				var k: int = choice["kind"]
				var robber: int = await _check_qiang_gang(p, k)
				if robber >= 0:
					var tid := _hand_take_kind(p, k)
					hands[robber].append(tid)
					announce.emit(robber, "抢杠胡")
					_win(robber, p, {"zimo": false, "qiang_gang": true})
					return
				_do_bugang(p, k)
				announce.emit(p, "补杠")
				changed.emit()
				await _delay(0.8)
				if not _draw_tile(p, true):
					_end_round_draw()
					return
				just_drew = true
				gang_flower = true
			"discard":
				var id: int = choice.get("id", -1)
				if id < 0:
					id = first_id_of_kind(p, choice.get("kind", -1))
				if id < 0 or not hands[p].has(id):
					id = hands[p].back()
				await _do_discard(p, id)
				return
			_:
				await _do_discard(p, hands[p].back())
				return


func _do_discard(p: int, id: int) -> void:
	hands[p].erase(id)
	hands[p].sort()
	drawn_id = -1
	rivers[p].append(id)
	last_discard_id = id
	last_discarder = p
	changed.emit()
	tile_discarded.emit(p, id)
	var k := kind_of(id)
	var claim: Dictionary = await _gather_claims(p, k)
	if claim.is_empty():
		cur = (p + 1) % 4
		return
	await _delay(0.35)
	var q: int = claim["seat"]
	rivers[p].pop_back()
	last_discard_id = -1
	match claim["action"]:
		"hu":
			hands[q].append(id)
			announce.emit(q, "胡")
			_win(q, p, {"zimo": false, "haidi": wall.is_empty()})
		"gang":
			var tiles := [_hand_take_kind(q, k), _hand_take_kind(q, k), _hand_take_kind(q, k), id]
			melds[q].append({"type": "gang", "tiles": tiles, "kind": k, "from": p})
			announce.emit(q, "杠")
			cur = q
			_next_draw_from_end = true
			changed.emit()
			await _delay(0.6)
		"peng":
			var tiles2 := [_hand_take_kind(q, k), _hand_take_kind(q, k), id]
			melds[q].append({"type": "peng", "tiles": tiles2, "kind": k, "from": p})
			announce.emit(q, "碰")
			cur = q
			_skip_draw = true
			changed.emit()
			await _delay(0.6)
		"chi":
			var tiles3 := []
			for kk in claim["kinds"]:
				if kk == k:
					tiles3.append(id)
				else:
					tiles3.append(_hand_take_kind(q, kk))
			melds[q].append({"type": "chi", "tiles": tiles3, "kind": claim["kinds"][0], "from": p})
			announce.emit(q, "吃")
			cur = q
			_skip_draw = true
			changed.emit()
			await _delay(0.6)


func _gather_claims(p: int, k: int) -> Dictionary:
	var candidates := []
	var human_offer := {}
	for i in range(1, 4):
		var q := (p + i) % 4
		var c := counts_of(q)
		var can_hu := false
		if c[k] < 4:
			c[k] += 1
			can_hu = Rules.can_win_counts(c)
			c[k] -= 1
		var can_peng: bool = c[k] >= 2
		var can_gang: bool = c[k] >= 3 and not wall.is_empty()
		var chis := []
		if q == (p + 1) % 4 and k < 27:
			chis = _chi_options(c, k)
		if not (can_hu or can_peng or can_gang or chis.size() > 0):
			continue
		if q == HUMAN:
			human_offer = {
				"mode": "claim", "kind": k, "can_hu": can_hu,
				"can_peng": can_peng, "can_gang": can_gang, "chis": chis, "order": i,
			}
		else:
			var d := AI.claim_choice(c, melds[q].size(), k, can_hu, can_peng, can_gang, chis)
			if not d.is_empty():
				d["seat"] = q
				d["order"] = i
				candidates.append(d)
	if not human_offer.is_empty():
		ask_actions.emit(human_offer)
		var ch: Dictionary = await _human_choice
		var act: String = ch.get("action", "pass")
		if act != "pass":
			var d2 := {"action": act, "seat": HUMAN, "order": human_offer["order"]}
			if act == "chi":
				d2["kinds"] = ch.get("kinds", [])
			candidates.append(d2)
	var best := {}
	for cand in candidates:
		if best.is_empty():
			best = cand
		elif _claim_prio(cand) > _claim_prio(best) \
				or (_claim_prio(cand) == _claim_prio(best) and cand["order"] < best["order"]):
			best = cand
	return best


func _claim_prio(c: Dictionary) -> int:
	match c["action"]:
		"hu":
			return 3
		"gang":
			return 2
		"peng":
			return 2
		"chi":
			return 1
	return 0


func _check_qiang_gang(p: int, k: int) -> int:
	for i in range(1, 4):
		var q := (p + i) % 4
		var c := counts_of(q)
		if c[k] >= 4:
			continue
		c[k] += 1
		var can := Rules.can_win_counts(c)
		c[k] -= 1
		if not can:
			continue
		if q == HUMAN:
			ask_actions.emit({"mode": "qianggang", "kind": k})
			var ch: Dictionary = await _human_choice
			if ch.get("action", "") == "hu":
				return q
		else:
			return q
	return -1


func _chi_options(c: Array, k: int) -> Array:
	var res := []
	var n := k % 9
	var base := k - n
	for off in range(-2, 1):
		var a := n + off
		if a < 0 or a + 2 > 8:
			continue
		var ks := [base + a, base + a + 1, base + a + 2]
		var ok := true
		for kk in ks:
			if kk != k and c[kk] <= 0:
				ok = false
		if ok:
			res.append(ks)
	return res


func _angang_options(p: int) -> Array:
	if wall.is_empty():
		return []
	var res := []
	var c := counts_of(p)
	for k in 34:
		if c[k] == 4:
			res.append(k)
	return res


func _bugang_options(p: int) -> Array:
	if wall.is_empty():
		return []
	var res := []
	var c := counts_of(p)
	for m in melds[p]:
		if m["type"] == "peng" and c[m["kind"]] >= 1:
			res.append(m["kind"])
	return res


func _do_angang(p: int, k: int) -> void:
	var tiles := []
	for _i in 4:
		tiles.append(_hand_take_kind(p, k))
	melds[p].append({"type": "angang", "tiles": tiles, "kind": k, "from": p})
	drawn_id = -1


func _do_bugang(p: int, k: int) -> void:
	var id := _hand_take_kind(p, k)
	for m in melds[p]:
		if m["type"] == "peng" and m["kind"] == k:
			m["tiles"].append(id)
			m["type"] = "bugang"
			break
	drawn_id = -1


func _hand_take_kind(p: int, k: int) -> int:
	var id := first_id_of_kind(p, k)
	if id >= 0:
		hands[p].erase(id)
	return id


func _win(winner: int, loser: int, ctx: Dictionary) -> void:
	phase = "over"
	revealed = true
	drawn_id = -1
	last_discard_id = -1
	hands[winner].sort()
	var menqing := true
	for m in melds[winner]:
		if m["type"] != "angang":
			menqing = false
	ctx["menqing"] = menqing
	var fan := Rules.calc_fan(counts_of(winner), melds[winner], ctx)
	var pts := int(pow(2.0, float(min(int(fan["total"]), 8))))
	if ctx.get("zimo", false):
		for s in 4:
			if s != winner:
				scores[s] -= pts
		scores[winner] += pts * 3
	else:
		scores[loser] -= pts
		scores[winner] += pts
	result = {
		"winner": winner, "loser": loser, "zimo": ctx.get("zimo", false),
		"fans": fan["list"], "fan_total": fan["total"], "points": pts,
	}
	changed.emit()
	round_over.emit(result)


func _end_round_draw() -> void:
	phase = "over"
	revealed = true
	drawn_id = -1
	last_discard_id = -1
	result = {"winner": -1}
	announce.emit(-1, "流局")
	changed.emit()
	round_over.emit(result)
