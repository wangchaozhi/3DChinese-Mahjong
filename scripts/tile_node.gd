class_name TileNode
extends StaticBody3D
## 一张 3D 麻将牌:白色牌身 + 绿色牌背 + Label3D 牌面。
## 局部坐标:x=宽,y=牌面文字朝上方向,z=牌面法线。

var id := 0
var visual: Node3D
var base_transform := Transform3D()
var move_tween: Tween
var lift_tween: Tween


func setup(tile_id: int, body_mesh: Mesh, back_mesh: Mesh, font: Font, tile_size: Vector3) -> void:
	id = tile_id
	var k := id >> 2
	visual = Node3D.new()
	add_child(visual)

	var body := MeshInstance3D.new()
	body.mesh = body_mesh
	visual.add_child(body)

	var back := MeshInstance3D.new()
	back.mesh = back_mesh
	var bt := tile_size.z * 0.36
	back.position = Vector3(0, 0, -tile_size.z * 0.5 + bt * 0.5 - 0.01)
	visual.add_child(back)

	var label := Label3D.new()
	label.text = Rules.kind_text(k)
	label.font = font
	label.font_size = 90 if k >= 27 else 60
	label.pixel_size = 0.006
	label.modulate = Rules.kind_color(k)
	label.outline_size = 0
	label.line_spacing = -14.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector3(0, 0, tile_size.z * 0.5 + 0.005)
	visual.add_child(label)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = tile_size
	col.shape = shape
	add_child(col)
	collision_layer = 2


func set_lift(on: bool) -> void:
	if lift_tween and lift_tween.is_valid():
		lift_tween.kill()
	lift_tween = create_tween()
	lift_tween.tween_property(visual, "position",
			Vector3(0, 0.22, 0) if on else Vector3.ZERO, 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
