extends Node3D
## 主场景:搭建 3D 牌桌、136 张牌、摄像机与灯光,处理鼠标交互和全部 UI。
## 设置环境变量 MJ_AUTOPLAY=1 可让人类座位由 AI 代打(用于自动化测试)。

const TILE_SIZE := Vector3(0.64, 0.86, 0.44)
const HAND_R := 6.45
const RIVER_R := 1.8
const WALL_R := 5.15
const SEAT_NAMES := ["你", "下家", "对家", "上家"]

var game: MahjongGame
var tiles := {}
var cn_font: Font
var camera: Camera3D
var marker: MeshInstance3D

var ui_root: Control
var round_label: Label
var seat_rows := []
var action_bar: HBoxContainer
var hint_label: Label
var announce_label: Label
var announce_tween: Tween
var result_panel: PanelContainer
var result_title: Label
var result_body: Label

var can_discard := false
var hovered: TileNode = null
var click_pending := false
var autoplay := false

var snd := {}
var clack_pool: Array = []
var clack_idx := 0
var deal_stagger := false
var win_fx: CPUParticles3D


func _ready() -> void:
	autoplay = OS.get_environment("MJ_AUTOPLAY") == "1"
	if autoplay:
		Engine.time_scale = 20.0
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_load_font()
	_build_world()
	_build_tiles()
	_build_ui()
	_build_audio()
	game = MahjongGame.new()
	add_child(game)
	game.changed.connect(_on_changed)
	game.announce.connect(_on_announce)
	game.ask_actions.connect(_on_ask_actions)
	game.round_over.connect(_on_round_over)
	game.round_started.connect(_on_round_started)
	game.tile_drawn.connect(_on_tile_drawn)
	game.tile_discarded.connect(_on_tile_discarded)
	_start_marker_pulse()
	_intro_camera()
	game.start_round()


func _load_font() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(
		["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	cn_font = sf


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.10, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-40, 205, 0)
	fill.light_energy = 0.35
	add_child(fill)

	var felt := MeshInstance3D.new()
	var felt_mesh := BoxMesh.new()
	felt_mesh.size = Vector3(18.6, 0.5, 18.6)
	var felt_mat := StandardMaterial3D.new()
	felt_mat.albedo_color = Color(0.10, 0.34, 0.22)
	felt_mat.roughness = 1.0
	felt_mesh.material = felt_mat
	felt.mesh = felt_mesh
	felt.position = Vector3(0, -0.25, 0)
	add_child(felt)

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.33, 0.21, 0.12)
	wood_mat.roughness = 0.7
	var border_mesh := BoxMesh.new()
	border_mesh.size = Vector3(20.4, 0.9, 0.9)
	border_mesh.material = wood_mat
	for s in 4:
		var b := MeshInstance3D.new()
		b.mesh = border_mesh
		b.basis = _basis_from(_seat_out(s), Vector3.UP)
		b.position = _seat_out(s) * 9.75 + Vector3(0, -0.1, 0)
		add_child(b)

	camera = Camera3D.new()
	camera.fov = 44
	add_child(camera)
	camera.position = Vector3(0, 12.2, 11.8)
	camera.look_at(Vector3(0, 0, 1.0))

	marker = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0.85, 0.2)
	mm.emission_enabled = true
	mm.emission = Color(1, 0.8, 0.15)
	mm.emission_energy_multiplier = 1.4
	sm.material = mm
	marker.mesh = sm
	marker.visible = false
	add_child(marker)

	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(1.0, 0.85, 0.25)
	pm.emission_enabled = true
	pm.emission = Color(1.0, 0.75, 0.2)
	pm.emission_energy_multiplier = 2.0
	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(0.09, 0.09, 0.09)
	pmesh.material = pm
	win_fx = CPUParticles3D.new()
	win_fx.mesh = pmesh
	win_fx.one_shot = true
	win_fx.emitting = false
	win_fx.amount = 90
	win_fx.lifetime = 1.4
	win_fx.explosiveness = 1.0
	win_fx.direction = Vector3.UP
	win_fx.spread = 65.0
	win_fx.initial_velocity_min = 3.5
	win_fx.initial_velocity_max = 7.0
	win_fx.angular_velocity_min = -360.0
	win_fx.angular_velocity_max = 360.0
	win_fx.gravity = Vector3(0, -8, 0)
	win_fx.scale_amount_min = 0.5
	win_fx.scale_amount_max = 1.2
	add_child(win_fx)


func _intro_camera() -> void:
	if autoplay:
		return
	var start := Vector3(0, 16.5, 15.6)
	var end := Vector3(0, 12.2, 11.8)
	camera.position = start
	camera.look_at(Vector3(0, 0, 1.0))
	var tw := create_tween()
	tw.tween_method(_camera_step.bind(start, end), 0.0, 1.0, 1.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _camera_step(t: float, start: Vector3, end: Vector3) -> void:
	camera.position = start.lerp(end, t)
	camera.look_at(Vector3(0, 0, 1.0))


func _start_marker_pulse() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(marker, "scale", Vector3.ONE * 1.4, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(marker, "scale", Vector3.ONE, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------- 音效

func _build_audio() -> void:
	snd["tick"] = _make_player(Sfx.tick(), -12.0)
	snd["thud"] = _make_player(Sfx.thud(), -6.0)
	snd["fanfare"] = _make_player(Sfx.fanfare(), -6.0)
	snd["sad"] = _make_player(Sfx.sad(), -7.0)
	snd["shuffle"] = _make_player(Sfx.shuffle(), -9.0)
	var clack_stream := Sfx.clack()
	for _i in 5:
		var p := AudioStreamPlayer3D.new()
		p.stream = clack_stream
		p.volume_db = -6.0
		p.unit_size = 14.0
		add_child(p)
		clack_pool.append(p)


func _make_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.max_polyphony = 3
	add_child(p)
	return p


func _play(name: String) -> void:
	if not snd.has(name):
		return
	var p: AudioStreamPlayer = snd[name]
	p.pitch_scale = randf_range(0.96, 1.04)
	p.play()


func _clack_at(pos: Vector3) -> void:
	if clack_pool.is_empty():
		return
	var p: AudioStreamPlayer3D = clack_pool[clack_idx]
	clack_idx = (clack_idx + 1) % clack_pool.size()
	p.position = pos
	p.pitch_scale = randf_range(0.90, 1.10)
	p.play()


func _build_tiles() -> void:
	var body_mesh := BoxMesh.new()
	body_mesh.size = TILE_SIZE
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.97, 0.96, 0.90)
	body_mat.roughness = 0.35
	body_mesh.material = body_mat
	var bt := TILE_SIZE.z * 0.36
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(TILE_SIZE.x + 0.022, TILE_SIZE.y + 0.022, bt + 0.02)
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.13, 0.45, 0.34)
	back_mat.roughness = 0.5
	back_mesh.material = back_mat
	for id in 136:
		var t := TileNode.new()
		add_child(t)
		t.setup(id, body_mesh, back_mesh, cn_font, TILE_SIZE)
		t.position = Vector3(0, -2.0, 0)
		tiles[id] = t


# ---------------------------------------------------------------- 布局

func _seat_out(s: int) -> Vector3:
	return Vector3(sin(s * PI / 2.0), 0, cos(s * PI / 2.0))


func _seat_right(s: int) -> Vector3:
	return Vector3(sin(s * PI / 2.0 + PI / 2.0), 0, cos(s * PI / 2.0 + PI / 2.0))


## 由牌面法线与文字朝上方向构造正交基(列 = 局部 x/y/z 的世界方向)。
func _basis_from(face: Vector3, glyph_up: Vector3) -> Basis:
	return Basis(glyph_up.cross(face), glyph_up, face)


func _relayout() -> void:
	var sp := TILE_SIZE.x + 0.055
	for s in 4:
		var out := _seat_out(s)
		var right := _seat_right(s)
		var hand: Array = game.hands[s]
		var n := hand.size()
		var has_drawn: bool = game.drawn_id != -1 and n > 0 \
				and hand[n - 1] == game.drawn_id and game.cur == s
		var gap := 0.30 if has_drawn else 0.0
		var meld_w := 0.0
		for m in game.melds[s]:
			meld_w += m["tiles"].size() * sp + 0.32
		if game.melds[s].size() > 0:
			meld_w += 0.25
		var total_w := n * sp + gap + meld_w
		var sx := -total_w * 0.5
		var pickable: bool = game.phase == "playing" and not game.revealed and s == 0
		for i in n:
			var node: TileNode = tiles[hand[i]]
			var x := sx + i * sp + sp * 0.5
			if has_drawn and i == n - 1:
				x += gap
			var basis: Basis
			var y: float
			if game.revealed:
				basis = _basis_from(Vector3.UP, -out)
				y = TILE_SIZE.z * 0.5
			elif s == 0:
				var lean := 0.62
				var face := (out * cos(lean) + Vector3.UP * sin(lean)).normalized()
				var gup := (Vector3.UP * cos(lean) - out * sin(lean)).normalized()
				basis = _basis_from(face, gup)
				y = TILE_SIZE.y * 0.5 * cos(lean) + TILE_SIZE.z * 0.5 * sin(lean)
			else:
				basis = _basis_from(out, Vector3.UP)
				y = TILE_SIZE.y * 0.5
			node.collision_layer = 1 if pickable else 2
			var d := (i * 0.035 + s * 0.012) if deal_stagger else 0.0
			_move_tile(node, basis, out * HAND_R + right * x + Vector3(0, y, 0), d)
		var mx := sx + n * sp + gap + (0.25 if game.melds[s].size() > 0 else 0.0)
		for m in game.melds[s]:
			var face_down: bool = m["type"] == "angang" and not game.revealed and s != 0
			var mtiles: Array = m["tiles"]
			for j in mtiles.size():
				var node2: TileNode = tiles[mtiles[j]]
				node2.collision_layer = 2
				var b2 := _basis_from(Vector3.DOWN if face_down else Vector3.UP, -out)
				_move_tile(node2, b2,
						out * HAND_R + right * (mx + j * sp + sp * 0.5)
						+ Vector3(0, TILE_SIZE.z * 0.5, 0))
			mx += mtiles.size() * sp + 0.32
		var river: Array = game.rivers[s]
		for i2 in river.size():
			var node3: TileNode = tiles[river[i2]]
			node3.collision_layer = 2
			var row := int(i2 / 6.0)
			var col := i2 % 6
			var pos := out * (RIVER_R + row * 0.95) \
					+ right * ((col - 2.5) * (TILE_SIZE.x + 0.04)) \
					+ Vector3(0, TILE_SIZE.z * 0.5, 0)
			_move_tile(node3, _basis_from(Vector3.UP, -out), pos)
			if river[i2] == game.last_discard_id:
				marker.position = pos + Vector3(0, 0.55, 0)
	for id4 in game.wall:
		var node4: TileNode = tiles[id4]
		node4.collision_layer = 2
		var slot: int = game.wall_slot[id4]
		var side := int(slot / 21.0)
		var within := slot % 21
		var col2 := int(within / 2.0)
		var layer := within % 2
		var wout := _seat_out(side)
		var wright := _seat_right(side)
		var wpos := wout * WALL_R + wright * ((col2 - 5) * (TILE_SIZE.x + 0.04)) \
				+ Vector3(0, TILE_SIZE.z * (0.5 + layer), 0)
		var dw := (slot * 0.004) if deal_stagger else 0.0
		_move_tile(node4, _basis_from(Vector3.DOWN, -wout), wpos, dw)
	marker.visible = game.last_discard_id >= 0
	deal_stagger = false


func _move_tile(node: TileNode, basis: Basis, pos: Vector3, delay := 0.0) -> void:
	var target := Transform3D(basis, pos)
	if target.is_equal_approx(node.base_transform):
		return
	var from := node.transform
	var dist := from.origin.distance_to(target.origin)
	node.base_transform = target
	if node.move_tween and node.move_tween.is_valid():
		node.move_tween.kill()
	node.move_tween = node.create_tween()
	if delay > 0.0:
		node.move_tween.tween_interval(delay)
	if dist > 1.4:
		# 长距离移动(出牌/摸牌/鸣牌)走抛物线。
		var height := clampf(dist * 0.12, 0.25, 0.8)
		node.move_tween.tween_method(_arc_step.bind(node, from, target, height),
				0.0, 1.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		node.move_tween.tween_property(node, "transform", target, 0.22) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _arc_step(t: float, node: TileNode, from: Transform3D, target: Transform3D, height: float) -> void:
	var xf := from.interpolate_with(target, t)
	xf.origin.y += height * 4.0 * t * (1.0 - t)
	node.transform = xf


# ---------------------------------------------------------------- 交互

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		click_pending = true


func _physics_process(_dt: float) -> void:
	var want := click_pending
	click_pending = false
	if not can_discard or game == null or game.phase != "playing":
		_set_hovered(null)
		return
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var node: TileNode = null
	if not hit.is_empty() and hit["collider"] is TileNode:
		node = hit["collider"]
	_set_hovered(node)
	if want and node != null:
		var picked := node
		_set_hovered(null)
		_submit({"action": "discard", "id": picked.id})


func _set_hovered(n: TileNode) -> void:
	if hovered == n:
		return
	if hovered != null and is_instance_valid(hovered):
		hovered.set_lift(false)
	hovered = n
	if hovered != null:
		hovered.set_lift(true)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		_show_discard_hint(hovered.id)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if game != null:
			_update_ui()


## 悬停时预览:打出这张牌后听什么。
func _show_discard_hint(id: int) -> void:
	if not can_discard:
		return
	var k := id >> 2
	var counts: Array = game.counts_of(0)
	if counts[k] <= 0:
		return
	counts[k] -= 1
	var ws: Array = Rules.waits(counts)
	if ws.is_empty():
		hint_label.text = "打出 %s" % Rules.kind_name(k)
	else:
		var names := []
		for w in ws:
			names.append(Rules.kind_name(w))
		hint_label.text = "打 %s 后听:%s" % [Rules.kind_name(k), " ".join(names)]


func _submit(choice: Dictionary) -> void:
	can_discard = false
	_clear_action_buttons()
	game.submit(choice)


# ---------------------------------------------------------------- 游戏信号

func _on_changed() -> void:
	_relayout()
	_update_ui()


func _on_announce(seat: int, text: String) -> void:
	if text == "胡" or text == "自摸" or text == "抢杠胡":
		_play("fanfare")
	elif text == "流局":
		_play("sad")
	else:
		_play("thud")
	var msg := text if seat < 0 else "%s:%s!" % [SEAT_NAMES[seat], text]
	announce_label.text = msg
	announce_label.reset_size()
	announce_label.pivot_offset = announce_label.size * 0.5
	announce_label.modulate.a = 0.0
	announce_label.scale = Vector2(1.7, 1.7)
	if announce_tween and announce_tween.is_valid():
		announce_tween.kill()
	announce_tween = create_tween()
	announce_tween.set_parallel(true)
	announce_tween.tween_property(announce_label, "modulate:a", 1.0, 0.1)
	announce_tween.tween_property(announce_label, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	announce_tween.chain().tween_interval(0.85)
	announce_tween.chain().tween_property(announce_label, "modulate:a", 0.0, 0.5)


func _on_round_started() -> void:
	deal_stagger = true
	_play("shuffle")


func _on_tile_drawn(_seat: int) -> void:
	_play("tick")


func _on_tile_discarded(_seat: int, id: int) -> void:
	if tiles.has(id):
		_clack_at(tiles[id].base_transform.origin)


func _on_ask_actions(data: Dictionary) -> void:
	_clear_action_buttons()
	if autoplay:
		_autoplay_choice.call_deferred(data)
		return
	var mode: String = data.get("mode", "")
	if mode == "turn":
		can_discard = true
		var acts: Array = data.get("actions", [])
		for act in acts:
			var a: Dictionary = act
			match a["action"]:
				"hu":
					_add_action_button("胡!", func() -> void: _submit({"action": "hu"}))
				"angang":
					_add_action_button("暗杠 " + Rules.kind_name(a["kind"]),
							func() -> void: _submit({"action": "angang", "kind": a["kind"]}))
				"bugang":
					_add_action_button("补杠 " + Rules.kind_name(a["kind"]),
							func() -> void: _submit({"action": "bugang", "kind": a["kind"]}))
		if acts.size() > 0:
			_add_action_button("过", func() -> void: _clear_action_buttons())
	elif mode == "claim":
		can_discard = false
		if data.get("can_hu", false):
			_add_action_button("胡!", func() -> void: _submit({"action": "hu"}))
		if data.get("can_gang", false):
			_add_action_button("杠", func() -> void: _submit({"action": "gang"}))
		if data.get("can_peng", false):
			_add_action_button("碰", func() -> void: _submit({"action": "peng"}))
		for opt in data.get("chis", []):
			var kinds: Array = opt
			var names := "吃 "
			for kk in kinds:
				names += Rules.kind_name(kk)
			_add_action_button(names,
					func() -> void: _submit({"action": "chi", "kinds": kinds}))
		_add_action_button("过", func() -> void: _submit({"action": "pass"}))
	elif mode == "qianggang":
		_add_action_button("抢杠胡 " + Rules.kind_name(data.get("kind", 0)) + "!",
				func() -> void: _submit({"action": "hu"}))
		_add_action_button("过", func() -> void: _submit({"action": "pass"}))
	_update_ui()


func _autoplay_choice(data: Dictionary) -> void:
	var mode: String = data.get("mode", "")
	var counts: Array = game.counts_of(0)
	if mode == "turn":
		var can_hu := false
		var angangs := []
		var bugangs := []
		for act in data.get("actions", []):
			match act["action"]:
				"hu":
					can_hu = true
				"angang":
					angangs.append(act["kind"])
				"bugang":
					bugangs.append(act["kind"])
		var ch := AI.turn_choice(counts, game.melds[0].size(), can_hu, angangs, bugangs,
				game.visible_counts())
		if ch.get("action", "") == "discard":
			ch = {"action": "discard", "id": game.first_id_of_kind(0, ch["kind"])}
		game.submit(ch)
	elif mode == "claim":
		var ch2 := AI.claim_choice(counts, game.melds[0].size(), data["kind"],
				data.get("can_hu", false), data.get("can_peng", false),
				data.get("can_gang", false), data.get("chis", []))
		if ch2.is_empty():
			ch2 = {"action": "pass"}
		game.submit(ch2)
	else:
		game.submit({"action": "hu"})


func _on_round_over(res: Dictionary) -> void:
	_clear_action_buttons()
	can_discard = false
	var w: int = res.get("winner", -1)
	var totals := "总分:你 %d · 下家 %d · 对家 %d · 上家 %d" \
			% [game.scores[0], game.scores[1], game.scores[2], game.scores[3]]
	if w < 0:
		result_title.text = "流局"
		result_body.text = "无人胡牌,庄家连庄\n" + totals
	else:
		win_fx.position = _seat_out(w) * 4.5 + Vector3(0, 0.6, 0)
		win_fx.restart()
		var t := "%s 胡牌!" % SEAT_NAMES[w]
		if res.get("zimo", false):
			t += "(自摸)"
		result_title.text = t
		var lines := []
		if not res.get("zimo", false) and res.get("loser", -1) >= 0:
			lines.append("点炮:%s" % SEAT_NAMES[res["loser"]])
		for f in res.get("fans", []):
			lines.append("%s  %d番" % [f[0], f[1]])
		lines.append("共 %d 番 · %d 分" % [res.get("fan_total", 0), res.get("points", 0)])
		lines.append(totals)
		result_body.text = "\n".join(lines)
	result_panel.visible = true
	if autoplay:
		print("[第%d局] %s" % [game.hand_no, str(res)])
		print("  分数: %s" % str(game.scores))
		_auto_next()


func _auto_next() -> void:
	await get_tree().create_timer(0.5).timeout
	if game.hand_no >= 6:
		print("自动测试完成,共 %d 局" % game.hand_no)
		get_tree().quit()
		return
	result_panel.visible = false
	game.next_round()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = cn_font
	theme.default_font_size = 20
	ui_root.theme = theme
	layer.add_child(ui_root)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(14, 14)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.08, 0.11, 0.8)))
	ui_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	round_label = Label.new()
	round_label.add_theme_font_size_override("font_size", 22)
	round_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	vb.add_child(round_label)
	for s in 4:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 20)
		vb.add_child(l)
		seat_rows.append(l)
	var mute_btn := CheckButton.new()
	mute_btn.text = "音效"
	mute_btn.button_pressed = true
	mute_btn.add_theme_font_size_override("font_size", 16)
	mute_btn.toggled.connect(func(on: bool) -> void:
		AudioServer.set_bus_mute(0, not on)
	)
	vb.add_child(mute_btn)

	var bar_margin := MarginContainer.new()
	bar_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bar_margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar_margin.add_theme_constant_override("margin_right", 24)
	bar_margin.add_theme_constant_override("margin_bottom", 24)
	ui_root.add_child(bar_margin)
	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 10)
	bar_margin.add_child(action_bar)

	var hint_margin := MarginContainer.new()
	hint_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint_margin.grow_horizontal = Control.GROW_DIRECTION_END
	hint_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_margin.add_theme_constant_override("margin_left", 18)
	hint_margin.add_theme_constant_override("margin_bottom", 18)
	ui_root.add_child(hint_margin)
	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 20)
	hint_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	hint_margin.add_child(hint_label)

	announce_label = Label.new()
	announce_label.set_anchors_preset(Control.PRESET_CENTER)
	announce_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	announce_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	var ls := LabelSettings.new()
	ls.font = cn_font
	ls.font_size = 64
	ls.font_color = Color(1, 0.85, 0.3)
	ls.outline_size = 14
	ls.outline_color = Color(0, 0, 0, 0.85)
	announce_label.label_settings = ls
	announce_label.modulate.a = 0.0
	ui_root.add_child(announce_label)

	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_panel.custom_minimum_size = Vector2(380, 0)
	result_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.09, 0.13, 0.95)))
	result_panel.visible = false
	ui_root.add_child(result_panel)
	var rvb := VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 12)
	result_panel.add_child(rvb)
	result_title = Label.new()
	result_title.add_theme_font_size_override("font_size", 32)
	result_title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rvb.add_child(result_title)
	result_body = Label.new()
	result_body.add_theme_font_size_override("font_size", 21)
	result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rvb.add_child(result_body)
	var next_btn := Button.new()
	next_btn.text = "下一局"
	next_btn.custom_minimum_size = Vector2(160, 52)
	next_btn.add_theme_font_size_override("font_size", 24)
	next_btn.pressed.connect(func() -> void:
		_play("tick")
		result_panel.visible = false
		game.next_round()
	)
	rvb.add_child(next_btn)


func _panel_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


func _add_action_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(func() -> void:
		_play("tick")
		cb.call()
	)
	action_bar.add_child(b)


func _clear_action_buttons() -> void:
	for child in action_bar.get_children():
		child.queue_free()


func _update_ui() -> void:
	round_label.text = "第 %d 局 · 庄家:%s · 余牌 %d" \
			% [game.hand_no, SEAT_NAMES[game.dealer], game.wall.size()]
	for s in 4:
		var mark := "▶ " if (game.phase == "playing" and game.cur == s) else "    "
		seat_rows[s].text = "%s%s(%s)  %d" \
				% [mark, SEAT_NAMES[s], Rules.WINDS[game.seat_wind(s)], game.scores[s]]
	var hand: Array = game.hands[0]
	if game.phase == "playing" and hand.size() % 3 == 1:
		var ws: Array = Rules.waits(game.counts_of(0))
		if ws.size() > 0:
			var names := []
			for k in ws:
				names.append(Rules.kind_name(k))
			hint_label.text = "听牌:" + " ".join(names)
		else:
			hint_label.text = ""
	elif game.phase == "playing" and hand.size() % 3 == 2 and can_discard:
		hint_label.text = "点击一张牌打出"
	else:
		hint_label.text = ""
