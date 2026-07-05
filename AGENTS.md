# AGENTS.md — 3D 中国麻将(Godot 4.7 / GDScript)

面向 AI 编码助手的开发指南。改代码前先读完本文;领域细节与算法见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 项目速览

- 完整可玩的 3D 中国麻将:136 张牌,人类(座位 0)+ 3 个 AI,支持吃/碰/明杠/暗杠/补杠/抢杠胡/自摸/点炮/流局,按番计分跨局累计。
- Godot **4.7 stable**,**Mobile** 渲染器,D3D12,Jolt 物理,窗口 1600×900。
- **整个游戏(3D 场景、UI、音效)全部由代码构建**。[scenes/main.tscn](scenes/main.tscn) 刻意只有一个挂 `main.gd` 的根节点——不要往 tscn 里加节点,一切改动都在 GDScript 里做。
- 无外部资源:牌面是 Label3D 汉字(系统微软雅黑),音效由 `sfx.gd` 启动时程序化合成。

## 环境与命令

Godot 可执行文件(本机路径,其他机器换成任意 Godot 4.7 stable):

```
C:\Users\86131\Desktop\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe
```

用 `*_console.exe` 而不是无 console 版,否则看不到日志。

| 任务 | 命令 |
|---|---|
| 注册/刷新脚本类(新增或重命名 `class_name` 后**必须**跑) | `godot --headless --path <项目> --import` |
| 逻辑回归测试(AI 代打人类座位,20 倍速自动打 6 局后退出) | 设 `MJ_AUTOPLAY=1` 后 `godot --headless --path <项目> --quit-after 200000` |
| 视觉验证(渲染 PNG 帧序列 + mj.wav 音轨,需要 GPU,会闪一下窗口) | `godot --path <项目> --write-movie <目录>\mj.png --quit-after 240` |
| 正常运行 | `godot --path <项目>`(或编辑器里 F5) |

PowerShell 设环境变量:`$env:MJ_AUTOPLAY='1'`;bash:`MJ_AUTOPLAY=1 godot ...`。

### 验证清单(每次改动后)

1. `--import` 无 `SCRIPT ERROR`(GDScript 解析错误只在这里暴露)。
2. autoplay 回归:6 局全部打印 `[第N局]` 结果、无报错、**四家分数总和恒为 0**(零和不变量)。
3. 改了视觉/布局:渲染帧序列,查看发牌完成帧(约第 100 帧)和中盘帧。
4. 退出时 "N ObjectDB instances leaked" 警告是 quit 时 Tween 未释放,已知无害,忽略。

## 代码地图

| 文件 | 职责 | 依赖 |
|---|---|---|
| [scripts/rules.gd](scripts/rules.gd) | `Rules`(纯静态):和牌判定、听牌、算番、牌名/颜色 | 无 |
| [scripts/ai.gd](scripts/ai.gd) | `AI`(纯静态):向听数搜索、出牌/鸣牌决策、死牌意识 | 无 |
| [scripts/game.gd](scripts/game.gd) | `MahjongGame extends Node`:全部游戏状态 + async 流程驱动,经信号对外 | Rules, AI |
| [scripts/tile_node.gd](scripts/tile_node.gd) | `TileNode extends StaticBody3D`:单张 3D 牌(牌身/牌背/Label3D/碰撞体) | Rules |
| [scripts/sfx.gd](scripts/sfx.gd) | `Sfx`(纯静态):合成 AudioStreamWAV(32kHz 单声道) | 无 |
| [scripts/main.gd](scripts/main.gd) | 主场景:建世界/136 张牌/UI/音频,布局重算,鼠标拾取,信号消费 | 全部 |

**分层规则:游戏逻辑(game/rules/ai)绝不接触 3D 或 UI;main.gd 绝不改游戏状态,只读状态 + 调 `game.submit()`。** 所有视觉刷新走一条路:`game.changed` 信号 → `main._relayout()` 全量重摆 136 张牌(按 `base_transform` 差异增量补间)。

## 核心约定(改逻辑前必读)

- **牌编码**:种类 `kind` 0..33(0-8 万,9-17 筒,18-26 条,27-30 东南西北,31-33 中发白);实例 `id` 0..135,`kind = id >> 2`。手牌数组直接 `sort()` 即按种类有序。
- **座位**:0=你(屏幕下方,+z),1=下家(右,+x),2=对家(上,-z),3=上家(左,-x);出牌顺序 0→1→2→3(逆时针)。吃只能吃上家(即 `q == (p+1)%4` 才给吃选项)。座风 = `(seat - dealer + 4) % 4` → 东南西北。
- **人机交互模型**:游戏循环是 async 的;需要人类决策时 `ask_actions.emit(data)` 然后 `await _human_choice`;UI 通过 `game.submit(choice)` 恢复协程。choice 字典形如 `{"action": "discard", "id": 17}`、`{"action": "peng"}`、`{"action": "chi", "kinds": [3,4,5]}`、`{"action": "pass"}`。
- **鸣牌仲裁**:一次弃牌后收集全部候选(AI 同步决策、人类 await),按优先级 胡(3) > 杠=碰(2) > 吃(1),同级取离弃牌者座位顺序近者。
- **摸牌方向**:正常摸 `wall.pop_back()`,杠后补牌 `wall.pop_front()`(靠 `_next_draw_from_end` 标志);碰/吃后不摸牌直接出(`_skip_draw`)。
- **自摸约束**:只有 `just_drew` 为真才允许自摸/暗杠/补杠(碰吃之后没有摸牌事件,不能胡)。补杠不增加向听数计算里的副露数(碰已计入)。
- `announce` 信号的 text 是有限集合:`自摸 暗杠 补杠 抢杠胡 胡 杠 碰 吃 流局`——main 里音效映射按字符串匹配,改文案要同步 `_on_announce`。

## GDScript 陷阱(本项目实际踩过)

1. **Variant 推断**:无类型 `Array` 取下标得 Variant,喂给 `:=` 直接解析错误 "Cannot infer the type"。先赋给带类型局部变量:`var river: Array = game.rivers[s]`。遍历字面量数组的循环变量也是 Variant(用 `range()` 代替)。
2. **多行 lambda**:作为**唯一/末尾参数**且右括号独占一行时合法(见 `_add_action_button` 的用法);后面还跟其他参数就会解析失败——此时用普通方法 + `Callable.bind()`(见 `_arc_step`、`_camera_step`)。
3. **submit 死锁**:`ask_actions` 的处理器里**不得同步调用** `game.submit()`(信号发出时 `await` 还没开始,选择会丢失)。必须延迟:autoplay 用 `_autoplay_choice.call_deferred(data)`。人类点击天然异步,没这个问题。
4. 整数除法有 warning,项目内统一写 `int(x / 6.0)`。
5. 缩进用 **Tab**(GDScript 标准);注释、UI 文案用中文。

## 常见改动配方

- **加番种**:只改 `Rules.calc_fan`,append `["番名", 番数]`;分数自动按 2^min(总番,8) 结算。跑 autoplay 确认番会出现在结果里。
- **加音效**:`sfx.gd` 加静态合成函数 → `main._build_audio()` 注册进 `snd` 字典 → `_play("名字")`。
- **加玩家可选动作**:四处同步——`game._do_turn`(或 `_gather_claims`)生成选项、`main._on_ask_actions` 加按钮、`main._autoplay_choice` 加 AI 分支、`game` 的 match 加处理。漏掉 autoplay 分支会让回归测试卡死(表现为 6 局打不完直到超时)。
- **调布局/镜头**:只动 `main.gd` 顶部常量(`TILE_SIZE/HAND_R/RIVER_R/WALL_R`)和 `_build_world` 里 camera 参数,然后渲染帧序列目检。
- **调 AI 强度**:`ai.gd` 的 `_tile_value`(弃牌取舍)与 `claim_choice` 的向听数比较阈值。

## 其他事实

- 项目当前**不是 git 仓库**;需要提交历史请先 `git init`。
- 字体依赖 Windows 系统微软雅黑(SystemFont 回退链);导出到其他平台需自带 CJK 字体文件并替换 `main._load_font()`。
- `MJ_AUTOPLAY=1` 同时会把 `Engine.time_scale` 设为 20 并在 6 局后 `quit()`——正常游玩不受影响。
