class_name AI
## 电脑玩家决策:基于向听数(shanten)的出牌、吃碰杠选择。


## 自己回合(已摸牌,手牌 3n+2)的选择。dead 为场上可见牌计数(判断死牌)。
static func turn_choice(counts: Array, meld_count: int, can_zimo: bool, angangs: Array, bugangs: Array, dead: Array = []) -> Dictionary:
	if can_zimo:
		return {"action": "hu"}
	var discard_k := choose_discard(counts, meld_count, dead)
	var base := 99
	if discard_k >= 0:
		counts[discard_k] -= 1
		base = shanten(counts, meld_count)
		counts[discard_k] += 1
	for k in angangs:
		var c: Array = counts.duplicate()
		c[k] -= 4
		if shanten(c, meld_count + 1) <= base:
			return {"action": "angang", "kind": k}
	for k in bugangs:
		var c: Array = counts.duplicate()
		c[k] -= 1
		# 补杠不增加副露组数(碰已计入)
		if shanten(c, meld_count) <= base:
			return {"action": "bugang", "kind": k}
	return {"action": "discard", "kind": discard_k}


## 别人打出 k 时的鸣牌选择,counts 为 3n+1 手牌。返回空字典表示过。
static func claim_choice(counts: Array, meld_count: int, k: int, can_hu: bool, can_peng: bool, can_gang: bool, chis: Array) -> Dictionary:
	if can_hu:
		return {"action": "hu"}
	var base := shanten(counts, meld_count)
	if can_gang:
		var cg: Array = counts.duplicate()
		cg[k] -= 3
		if shanten(cg, meld_count + 1) <= base:
			return {"action": "gang"}
	if can_peng:
		var cp: Array = counts.duplicate()
		cp[k] -= 2
		if shanten(cp, meld_count + 1) < base:
			return {"action": "peng"}
	for opt in chis:
		var cc: Array = counts.duplicate()
		for kk in opt:
			if kk != k:
				cc[kk] -= 1
		if shanten(cc, meld_count + 1) < base:
			return {"action": "chi", "kinds": opt}
	return {}


## 从 3n+2 手牌中选一张打出,使打出后向听数最小。
static func choose_discard(counts: Array, meld_count: int, dead: Array = []) -> int:
	var best_k := -1
	var best_sh := 99
	var best_val := 99999.0
	for k in 34:
		if counts[k] <= 0:
			continue
		counts[k] -= 1
		var sh := shanten(counts, meld_count)
		counts[k] += 1
		var val := _tile_value(counts, k, dead)
		if sh < best_sh or (sh == best_sh and val < best_val):
			best_sh = sh
			best_val = val
			best_k = k
	return best_k


## 牌的"保留价值",用于向听数相同情况下的弃牌取舍。
## dead 中已见的副本越多,该牌越难成刻/成对,价值越低。
static func _tile_value(counts: Array, k: int, dead: Array = []) -> float:
	var v := float(counts[k]) * 2.0
	if k < 27:
		var n := k % 9
		if n >= 1:
			v += counts[k - 1] * 1.6
		if n >= 2:
			v += counts[k - 2] * 0.7
		if n <= 7:
			v += counts[k + 1] * 1.6
		if n <= 6:
			v += counts[k + 2] * 0.7
		v += 0.25 * min(n, 8 - n)
	else:
		if counts[k] == 1:
			v -= 1.0
	if dead.size() == 34:
		v -= float(dead[k]) * 0.35
	return v


## 标准型 + 七对的向听数,0 表示听牌,-1 表示已和。
static func shanten(counts: Array, meld_count: int) -> int:
	var best := [99]
	_search(counts.duplicate(), 0, meld_count, 0, 0, best)
	var s: int = best[0]
	if meld_count == 0:
		var pairs := 0
		var kinds := 0
		for v in counts:
			if v >= 2:
				pairs += 1
			if v >= 1:
				kinds += 1
		var s7: int = 6 - pairs + max(0, 7 - kinds)
		s = min(s, s7)
	return s


static func _search(c: Array, idx: int, sets: int, partials: int, pair: int, best: Array) -> void:
	while idx < 34 and c[idx] == 0:
		idx += 1
	if idx == 34:
		var p := partials
		if sets + p > 4:
			p = 4 - sets
		var st := 8 - 2 * sets - p - pair
		if st < best[0]:
			best[0] = st
		return
	# 刻子
	if c[idx] >= 3:
		c[idx] -= 3
		_search(c, idx, sets + 1, partials, pair, best)
		c[idx] += 3
	# 顺子
	if idx < 27 and idx % 9 <= 6 and c[idx + 1] > 0 and c[idx + 2] > 0:
		c[idx] -= 1
		c[idx + 1] -= 1
		c[idx + 2] -= 1
		_search(c, idx, sets + 1, partials, pair, best)
		c[idx] += 1
		c[idx + 1] += 1
		c[idx + 2] += 1
	if c[idx] >= 2:
		# 作将
		if pair == 0:
			c[idx] -= 2
			_search(c, idx, sets, partials, 1, best)
			c[idx] += 2
		# 对子作搭子
		if sets + partials < 4:
			c[idx] -= 2
			_search(c, idx, sets, partials + 1, pair, best)
			c[idx] += 2
	# 两面/嵌张搭子
	if sets + partials < 4 and idx < 27:
		if idx % 9 <= 7 and c[idx + 1] > 0:
			c[idx] -= 1
			c[idx + 1] -= 1
			_search(c, idx, sets, partials + 1, pair, best)
			c[idx] += 1
			c[idx + 1] += 1
		if idx % 9 <= 6 and c[idx + 2] > 0:
			c[idx] -= 1
			c[idx + 2] -= 1
			_search(c, idx, sets, partials + 1, pair, best)
			c[idx] += 1
			c[idx + 2] += 1
	# 该种全部作孤张
	var saved: int = c[idx]
	c[idx] = 0
	_search(c, idx + 1, sets, partials, pair, best)
	c[idx] = saved
