# 架构与领域参考

深入细节的参考文档,配合根目录 [AGENTS.md](../AGENTS.md) 使用。所有内容与代码逐一核对过;若发现文档与代码不符,以代码为准并顺手修文档。

## 1. 数据模型(game.gd)

```
wall: Array[int]            # 剩余牌墙(id),正常摸 pop_back,杠补 pop_front
wall_slot: {id: int}        # 发牌后固定的槽位映射,3D 摆放用(抽走留洞不重排)
hands: [[id], x4]           # 各家手牌;直接 sort() 即按种类有序(kind = id >> 2 单调)
melds: [[meld], x4]         # 副露,见下
rivers: [[id], x4]          # 牌河(被鸣走的牌会 pop_back 移除)
scores: [int, x4]           # 累计分,恒零和
dealer, hand_no, cur        # 庄家、局数、当前行动座位
phase: "idle"|"playing"|"over"
last_discard_id/-1          # 供 3D 高亮标记
drawn_id/-1                 # 刚摸的牌(布局时右侧留缝),打出/鸣牌后归 -1
revealed: bool              # 局末亮牌,relayout 据此把所有手牌摊开
result: {}                  # 见 §4
_skip_draw                  # 碰/吃后:轮到该家但不摸牌
_next_draw_from_end         # 明杠后:下次摸牌从墙尾(pop_front)
```

**meld 字典**:`{"type": "chi"|"peng"|"gang"|"angang"|"bugang", "tiles": [ids], "kind": int, "from": seat}`
- `chi` 的 `kind` 是顺子最小种类;`tiles` 顺序即顺子顺序,含被吃的那张 id。
- 补杠不新建 meld:在原 `peng` 上 `tiles.append(第4张)` 并把 type 改成 `bugang`。

## 2. 游戏流程(async 协程)

```
start_round()
  洗牌 → 发 13×4(pop_back)→ 记录 wall_slot → cur=dealer
  → emit round_started, changed → _game_loop()   (不 await,后台跑)

_game_loop():  await 1.15s;  while playing: await _do_turn(cur)

_do_turn(p):
  ① 摸牌(除非 _skip_draw);杠补从墙尾并标记 gang_flower;墙空 → 流局
  ② 内层循环:算 can_zimo(仅 just_drew)/ 暗杠 / 补杠选项
     p==0 → ask_actions{"mode":"turn"} + await _human_choice
     AI   → await 0.6s + AI.turn_choice(counts, melds数, ..., visible_counts())
  ③ match action:
     hu     → _win(p, -1, {zimo, gang_flower, haidi})
     angang → 成杠 → 补牌 → 回②(gang_flower=true)
     bugang → 先 _check_qiang_gang(逐家问,AI 必抢,人类弹按钮)
              被抢 → 抢牌进赢家手 → _win(robber, p, {qiang_gang})
              没抢 → 改 meld → 补牌 → 回②
     discard→ _do_discard(p, id) 后返回

_do_discard(p, id):
  牌入 river → emit changed, tile_discarded → _gather_claims(p, kind)
  无人鸣 → cur = (p+1)%4
  有人鸣 → 牌离开 river:
     hu   → 牌进赢家手 → _win(q, p, {haidi: wall空})
     gang → 拆 3 张成明杠,cur=q,_next_draw_from_end=true(之后照常摸补出牌)
     peng/chi → 成副露,cur=q,_skip_draw=true

_gather_claims(p, k):
  对 (p+1..p+3)%4 逐家算 can_hu / can_peng / can_gang(墙非空) / chis(仅下家)
  AI 立即出决策;人类有任何选项则 ask_actions{"mode":"claim"} + await
  全部候选按 胡3 > 杠2=碰2 > 吃1、同级取 order 小者,返回唯一赢家或空

_win(): 算番算分 → phase=over, revealed=true → emit changed, round_over
_end_round_draw(): 流局,不动分 → 同上
next_round(): 赢家非庄则庄移一位(庄胡/流局连庄);hand_no+1 → start_round()
```

**人机输入契约**:任何需要人类决策的点都是 `ask_actions.emit(payload)` + `await _human_choice`;外界用 `game.submit(choice)` 恢复。同一时刻最多一个 await 挂起。**处理器内严禁同步 submit**(死锁),必须 `call_deferred`。

### ask_actions payload

| mode | 字段 | 期望的 submit |
|---|---|---|
| `turn` | `actions: [{action:"hu"} \| {action:"angang",kind} \| {action:"bugang",kind}]`(可为空;出牌不在列表里,靠点牌) | `{action:"discard", id}` 或列表内动作 |
| `claim` | `kind, can_hu, can_peng, can_gang, chis:[[k,k,k]...], order` | `{action:"hu"/"peng"/"gang"/"pass"}` 或 `{action:"chi", kinds}` |
| `qianggang` | `kind` | `{action:"hu"}` 或 `{action:"pass"}` |

## 3. 信号一览

| 信号 | 载荷 | main.gd 消费者 |
|---|---|---|
| `changed` | — | `_relayout()` + `_update_ui()`(唯一视觉刷新入口) |
| `announce` | seat(-1=全局), text(有限集合,见 AGENTS.md) | 中央弹出字 + 音效映射 |
| `ask_actions` | 见上表 | 建按钮 / autoplay 代打(deferred) |
| `round_over` | result | 结算面板、胡牌粒子、autoplay 打印+续局 |
| `round_started` | — | `deal_stagger=true` + 洗牌音 |
| `tile_drawn` | seat | tick 音 |
| `tile_discarded` | seat, id | 牌落点 3D 定位 clack 音 |

## 4. result 字典

胡牌:`{winner, loser(-1=自摸), zimo, fans:[[名,番]...], fan_total, points}`;流局:`{winner:-1}`。

## 5. 算法

### 和牌判定 `Rules.can_win_counts(counts34)`
总数 %3==2 前提下:七对(全偶且对数=7,4 张算两对)或标准型(枚举将对 + `_melds_ok` 递归拆刻/顺,顺子仅数牌且 idx%9<=6)。

### 听牌 `Rules.waits`
对 34 种各 +1 试 can_win,O(34×拆解),够快,UI 悬停实时调用。

### 向听数 `AI.shanten(counts, meld_count)`
标准公式 `8 - 2*(副露+面子) - 搭子(封顶 4-面子) - 将(0/1)`,递归分支:刻子/顺子/将对/对子作搭/两面/嵌张/整种弃为孤张;无副露时另算七对 `6 - 对数 + max(0, 7-种类数)` 取小。0=听牌,-1=已和。

### AI 决策
- 出牌:枚举弃每种牌后的向听数取最小,平局按 `_tile_value` 弃价值最低者(同种张数×2 + 邻牌 1.6/隔牌 0.7 + 中张加成;孤字牌减 1;**每见一张死牌减 0.35**,死牌数来自 `game.visible_counts()` = 全部牌河+副露)。
- 鸣牌:胡必胡;明杠向听不变差就杠;碰/吃要求向听**严格下降**;暗杠/补杠与最优弃牌比较向听不变差才做(补杠比较时副露数不 +1)。

### 算番 `Rules.calc_fan` 与计分

| 番种 | 番 | 判定 |
|---|---|---|
| 底番 | 1 | 恒有 |
| 七对 | 2 | 无副露且 14 张全对 |
| 碰碰胡 | 2 | 无吃副露且手牌=将+纯刻子(与七对互斥) |
| 清一色 | 4 | 单花色无字(含副露) |
| 字一色 | 4 | 全字牌 |
| 混一色 | 2 | 单花色+字 |
| 断幺九 | 1 | 无 1/9/字 |
| 门前清 | 1 | 副露仅暗杠 |
| 自摸 / 杠上开花 / 抢杠 | 各 1 | ctx 标志 |
| 海底捞月 / 河底捞鱼 | 1 | 墙空时自摸/荣和 |

`points = 2^min(总番, 8)`。自摸:三家各付 points(赢家 +3×);点炮:仅放炮者付。

## 6. 3D 布局系统(main.gd)

- 常量:`TILE_SIZE=(0.64, 0.86, 0.44)`(宽/高/厚),`HAND_R=6.45`,`RIVER_R=1.8`,`WALL_R=5.15`;牌间距 手牌 0.695 / 河与墙 0.68。
- 座位方向:`_seat_out(s) = (sin(sπ/2), 0, cos(sπ/2))`(指向玩家),`_seat_right(s)` 为其 +90°。
- **牌的局部轴**:x=宽,y=牌面文字朝上方向,z=牌面法线(Label3D 在 +z 面,绿背盖住 -z 侧后 36% 厚度)。
- 朝向统一由 `_basis_from(face, glyph_up) = Basis(glyph_up.cross(face), glyph_up, face)` 构造(三列即局部 xyz 的世界方向,保持右手系,否则文字镜像):
  - 对手立牌:`(out, UP)`;人类手牌后仰 0.62 rad;摊开:`(UP, -out)`;盖牌:`(DOWN, -out)`。
  - 暗杠在未亮牌且非人类时盖牌显示。
- 每座位一行 = 手牌 + 副露(摊开)整体居中于 `HAND_R`;摸的牌在行尾多留 0.3 缝。牌河每行 6 张向中心延伸。牌墙 4 边 × 21 槽(`side=slot/21, col=within/2, layer=within%2`),槽位由 `wall_slot` 固定。
- **动画**:`_move_tile(node, basis, pos, delay)` 比对 `base_transform`,变了才动;位移 >1.4 走抛物线(`_arc_step` + `Callable.bind`,0.30s),否则 0.22s 补间;`deal_stagger` 为真时手牌延迟 `i*0.035+s*0.012`、牌墙 `slot*0.004`,用完即清。
- 相机 `(0, 12.2, 11.8)`,fov 44,look_at `(0,0,1.0)`;开场从 `(0,16.5,15.6)` 推入(autoplay 跳过)。

## 7. 交互管线

`_unhandled_input` 记录左键 → `_physics_process` 里从相机发射线(`collision_mask=1`)→ 命中 TileNode 即悬停(抬牌 + 手型光标 + "打 X 后听:…"预览)→ 有点击则 `_submit({action:"discard", id})`。
碰撞层:**1 = 可点(仅人类手牌、playing 且未亮牌)**,2 = 其他一切。`can_discard` 只在 `mode=="turn"` 的 ask_actions 后为真,submit 即清。

## 8. UI 树(全代码构建,_build_ui)

CanvasLayer → Control(全屏,IGNORE,Theme=雅黑)
├ PanelContainer(左上):局数/庄家/余牌 + 4 行座位分数(▶=行动中)+ 音效 CheckButton
├ MarginContainer(右下)→ HBox `action_bar`:动态按钮(胡/杠/碰/吃×n/过)
├ MarginContainer(左下)→ `hint_label`:听牌提示/悬停预览
├ `announce_label`(中央,LabelSettings 金字黑边):缩放回弹 + 淡入淡出
└ `result_panel`(中央):标题/番数明细/总分/下一局按钮

## 9. 音效(sfx.gd + main._build_audio)

全部静态函数合成 `AudioStreamWAV`(32kHz/16bit/单声道,种子固定可复现):`clack`(出牌,5 个 AudioStreamPlayer3D 池定位播放)、`tick`(摸牌/按钮)、`thud`(吃碰杠)、`fanfare`(胡)、`sad`(流局)、`shuffle`(发牌)。全局音量已调避免叠加削波;`_play(name)` 带 ±4% 随机变调。静音开关直接 mute 总线 0。

## 10. 已验证基线(回归时对照)

- autoplay 多轮 6 局跑通:覆盖 自摸、点炮、门前清、断幺九、抢杠胡 路径;分数每局后总和为 0;庄家轮转/连庄正确。
- Movie Maker 帧检:发牌瀑布、抛物线出牌、副露/牌河/墙布局、亮牌、结算面板均正常;mj.wav 有实际波形(音效在响)。
