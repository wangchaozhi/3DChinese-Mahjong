class_name Rules
## 麻将规则:和牌判定、听牌计算、番数计算。
## 牌种编码 kind 0..33:0-8 万,9-17 筒,18-26 条,27-30 东南西北,31-33 中发白。
## 牌实例 id 0..135,kind = id >> 2。

const NUMS := ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
const HONORS := ["东", "南", "西", "北", "中", "发", "白"]
const WINDS := ["东", "南", "西", "北"]


static func kind_name(k: int) -> String:
	if k < 9:
		return NUMS[k] + "万"
	if k < 18:
		return NUMS[k - 9] + "筒"
	if k < 27:
		return NUMS[k - 18] + "条"
	return HONORS[k - 27]


static func kind_text(k: int) -> String:
	if k < 9:
		return NUMS[k] + "\n万"
	if k < 18:
		return NUMS[k - 9] + "\n筒"
	if k < 27:
		return NUMS[k - 18] + "\n条"
	return HONORS[k - 27]


static func kind_color(k: int) -> Color:
	if k < 9:
		return Color(0.72, 0.13, 0.11)
	if k < 18:
		return Color(0.12, 0.28, 0.62)
	if k < 27:
		return Color(0.07, 0.42, 0.18)
	if k < 31:
		return Color(0.13, 0.13, 0.16)
	if k == 31:
		return Color(0.75, 0.10, 0.10)
	if k == 32:
		return Color(0.06, 0.50, 0.20)
	return Color(0.42, 0.50, 0.62)


## counts:长度 34 的手牌张数数组(不含副露)。总数 %3 须为 2。
static func can_win_counts(counts: Array) -> bool:
	var total := 0
	for v in counts:
		total += v
	if total % 3 != 2:
		return false
	if total == 14 and is_seven_pairs(counts):
		return true
	var c: Array = counts.duplicate()
	for i in 34:
		if c[i] >= 2:
			c[i] -= 2
			if _melds_ok(c, 0):
				c[i] += 2
				return true
			c[i] += 2
	return false


static func is_seven_pairs(counts: Array) -> bool:
	var pairs := 0
	for v in counts:
		if v % 2 != 0:
			return false
		pairs += v >> 1
	return pairs == 7


static func _melds_ok(c: Array, idx: int) -> bool:
	while idx < 34 and c[idx] == 0:
		idx += 1
	if idx == 34:
		return true
	if c[idx] >= 3:
		c[idx] -= 3
		var ok := _melds_ok(c, idx)
		c[idx] += 3
		if ok:
			return true
	if idx < 27 and idx % 9 <= 6 and c[idx + 1] > 0 and c[idx + 2] > 0:
		c[idx] -= 1
		c[idx + 1] -= 1
		c[idx + 2] -= 1
		var ok2 := _melds_ok(c, idx)
		c[idx] += 1
		c[idx + 1] += 1
		c[idx + 2] += 1
		return ok2
	return false


## 13 张(3n+1)手牌的听牌列表。
static func waits(counts: Array) -> Array:
	var res := []
	for k in 34:
		if counts[k] >= 4:
			continue
		counts[k] += 1
		if can_win_counts(counts):
			res.append(k)
		counts[k] -= 1
	return res


## 算番。counts 为含和牌张的手牌,mds 为副露列表,ctx 含 zimo/menqing/gang_flower/qiang_gang/haidi。
static func calc_fan(counts: Array, mds: Array, ctx: Dictionary) -> Dictionary:
	var list := []
	var total_tiles := 0
	for v in counts:
		total_tiles += v
	var qidui: bool = mds.is_empty() and total_tiles == 14 and is_seven_pairs(counts)
	list.append(["底番", 1])
	if qidui:
		list.append(["七对", 2])
	elif _all_triplets(counts, mds):
		list.append(["碰碰胡", 2])
	var suits := {}
	var has_honor := false
	for k in 34:
		if counts[k] > 0:
			if k >= 27:
				has_honor = true
			else:
				suits[int(k / 9.0)] = true
	for m in mds:
		for id in m["tiles"]:
			var k2: int = id >> 2
			if k2 >= 27:
				has_honor = true
			else:
				suits[int(k2 / 9.0)] = true
	if suits.size() == 1 and not has_honor:
		list.append(["清一色", 4])
	elif suits.size() == 0 and has_honor:
		list.append(["字一色", 4])
	elif suits.size() == 1 and has_honor:
		list.append(["混一色", 2])
	if _no_terminals(counts, mds):
		list.append(["断幺九", 1])
	if ctx.get("menqing", false):
		list.append(["门前清", 1])
	if ctx.get("zimo", false):
		list.append(["自摸", 1])
	if ctx.get("gang_flower", false):
		list.append(["杠上开花", 1])
	if ctx.get("qiang_gang", false):
		list.append(["抢杠", 1])
	if ctx.get("haidi", false):
		list.append(["海底捞月" if ctx.get("zimo", false) else "河底捞鱼", 1])
	var total := 0
	for f in list:
		total += f[1]
	return {"list": list, "total": total}


static func _all_triplets(counts: Array, mds: Array) -> bool:
	for m in mds:
		if m["type"] == "chi":
			return false
	for p in 34:
		if counts[p] >= 2:
			var ok := true
			for k in 34:
				var v: int = counts[k]
				if k == p:
					v -= 2
				if v % 3 != 0:
					ok = false
					break
			if ok:
				return true
	return false


static func _no_terminals(counts: Array, mds: Array) -> bool:
	for k in 34:
		if counts[k] > 0:
			if k >= 27 or k % 9 == 0 or k % 9 == 8:
				return false
	for m in mds:
		for id in m["tiles"]:
			var k2: int = id >> 2
			if k2 >= 27 or k2 % 9 == 0 or k2 % 9 == 8:
				return false
	return true
