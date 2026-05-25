# 股市AI对手设计文档（做空庄家Boss + 行为树）

> 项目：《不要怕，是技术性调整！》（GameJam_Paper / Godot 4.6）
> 文档版本：v1 — 2026-05-24
> 范围：本文档定义"商战对手"系统的完整规则与代码接入方式，作为后续实施计划（plan）的输入。

---

## 0. 一句话总结

每关一个**做空庄家 Boss**，行为由**硬规则链 + 加权选择器**驱动。玩家通过把股价拉到 Boss 的**平仓线**之上来"强平"击败它；Boss 在场期间会反向打压玩家。三关三个不同性格、递增难度的 Boss，击败后获得**市场情绪 Buff + 一张专属奖励卡**。

---

## 1. 核心数值模型

### 1.1 对手内部状态

| 字段 | 含义 | 默认初值（见 §4 各 Boss 表） |
|------|------|------------------------------|
| `short_position` | 做空仓位（股） | N0（按 Boss 配） |
| `entry_avg_price` | 开空均价（滚动加权） | 入场瞬间的股价 |
| `safety_pool` | 保证金池（对手"现金"） | M0（按 Boss 配） |
| `liquidation_price` | 平仓线（派生）= `entry_avg_price + safety_pool / short_position` | — |
| `present` | 是否在场 | false |
| `defeated_this_level` | 本关是否已被击败 | false |

### 1.2 派生：血条 HUD

```
health_pct = clamp((liquidation_price - current_price) / liquidation_price, 0.0, 1.0)
```
- 当前价远低于平仓线 → 血条接近满
- 当前价 = 平仓线 → 血条 0 → **触发强平**

### 1.3 三种状态转移事件

| 事件 | `short_position` | `entry_avg_price` | `safety_pool` | `liquidation_price` | 股价 |
|------|------------------|-------------------|---------------|---------------------|------|
| **加空 N 股** | += N | `(old_avg×pos + curr_price×N) / (pos+N)` 加权 | 不变 | 重算（一般略下移） | 直接 −X% |
| **主动减仓 M 股** | −= M | 不变 | 不变 | **上移**（分母变小） | 不变 |
| **强平触发** | → 0 | — | × 剩余比例 → 玩家奖励 | — | — |

### 1.4 入场即满仓
- 入场瞬间 `short_position = N0`、`entry_avg_price = 当前股价`、`safety_pool = M0`
- 入场即触发一次**加空动作**（戏剧性，让玩家立刻感到压力）
- 入场后第一个真正的"行为树tick"在下一回合

### 1.5 击败判定时机
- 调用 `apply_price_change()` 后立刻检查 `current_price >= liquidation_price`
- 也在自然波动结算后再检查一次
- 触发即清仓退场，本关不再出现（`defeated_this_level = true`）

---

## 2. 遭遇 / 跨天持久化 / 退场逻辑

### 2.1 出现判定（每回合开始时检查一次）

伪代码：
```
if 当前关卡为第1关 且 day ≤ 2: skip       # 教学保护期
elif defeated_this_level: skip             # 已击败，本关不再出现
elif present: skip                         # 已在场
else:
    if (当日开盘价→当前价涨幅 ≥ TRIGGER_RISE_PCT[level]) OR
       (rand() < TRIGGER_PROB_PER_TURN[level]):
        spawn_opponent()
```

### 2.2 触发参数（按关卡 1/2/3）

| 关卡 | 入场概率/回合 | 拉升必现阈值 |
|------|--------------|--------------|
| 第1关 | 15% | 单日涨幅 ≥ 20% |
| 第2关 | 25% | 单日涨幅 ≥ 15% |
| 第3关 | 40% | 单日涨幅 ≥ 10% |

### 2.3 在场期间的行动节奏

- **每回合行动一次**
- 时机：玩家 `end_turn()` 之后、`_settle_turn()` 中的自然波动**之前**
- 行动产物：一根 `kind="opponent"` 的分时K，附 action 字段说明，与玩家出牌 K 并列
- 头像旁文字气泡仅在**行为树分支切换**或**高戏剧性动作**时弹

### 2.4 跨天持久化

- 全部对手状态保留到次日
- 商店阶段不行动
- 次日开盘价 = 前一天收盘价 × 事件倍率 → 平仓线相对位置可能改变

### 2.5 退场分两种

| 原因 | 后续 |
|------|------|
| **强平**（击败） | 触发 §5 奖励，`defeated_this_level = true` |
| **关卡5天结束** | 静默退场，无奖励 |

---

## 3. 行为树（公共结构 + 加权选择器）

### 3.1 顶层结构（Selector 优先级链，第一个命中执行）

```
对手行为树（每回合 tick 一次）：

├─ 1. 保命分支  if  health_pct ≤ CRITICAL_THRESHOLD[boss]
│      └─ 加权抽: [主动减仓 ×W1] [减仓+利空连击 ×W2] [硬扛 ×W3]
│
├─ 2. 拉升反应  if  本回合股价涨幅 ≥ REACTION_THRESHOLD[boss]
│      └─ 加权抽: [加空] [散播利空] [加空+利空连击]   # 必出手
│
├─ 3. 引诱反扑  if  玩家持仓 == 0  AND  玩家现金 < TIGHT_CASH_THRESHOLD（默认 current_price × 50，即买不起50股）
│      └─ 加权抽: [拉抬陷阱*] [静观]  # *仅高难解锁
│
└─ 4. 默认日常  加权抽: [加空] [散播利空] [主动减仓] [静观]
```

### 3.2 动作菜单（叶子节点）

| 动作 id | 效果 | 备注 |
|---------|------|------|
| `add_short` 加空 | `position += N`；按当前价加权更新 `entry_avg_price`；**直接压股价 −X%** | 卖压模型 |
| `bad_news` 散播利空 | 上涨情绪 −K | 不直接影响股价（让自然波动偏负） |
| `cover` 主动减仓 | `position -= M` | 平仓线上移，不影响股价 |
| `idle` 静观 | 什么都不做 | 一根空 K，仍会触发日志 |
| `pump_trap` 拉抬陷阱 | 股价 +Y%（短期诱饵） | 仅"狡猾型"Boss 解锁 |
| **连击复合动作**：`add_short + bad_news` 同回合执行 | 两个原子动作叠加 | 高难 / 拉升反应分支 |

### 3.3 加权抽签公式

```
weight(action) = base_weight[action]
               × situational_modifier(action, game_state)
               × personality_weight[boss][action]
```

**情境系数**（情境调节，所有 Boss 共用）：

| 动作 | 情境调节 |
|------|---------|
| `add_short` | 玩家持仓>0 ×1.5；上涨情绪>70 ×1.3；health<30% ×0.3 |
| `bad_news` | 上涨情绪>50 ×1.4；情绪<30 ×0.5 |
| `cover` | health<50% ×2.0；health>80% ×0.3 |
| `idle` | 玩家持仓=0 ×2.0；玩家本回合没出牌 ×1.5 |
| `pump_trap` | 玩家无筹码 AND 玩家现金紧 ×3.0 |

> 难度只影响**动作参数大小**（N、M、X、K、Y），个性只影响**权重**。两者正交，可独立调参。

### 3.4 文字气泡触发规则

| 触发时机 | 行为 |
|----------|------|
| 入场 | 弹 Boss 专属入场台词 |
| 行为树分支切换（如默认→保命）| 弹切换台词 |
| 执行"拉抬陷阱"等高戏剧动作 | 弹动作台词 |
| 即将被强平（health_pct < 5%） | 弹挣扎台词 |
| 强平瞬间 | 弹败北台词 |
| 默认日常分支内部 | **不弹**（避免过度刷屏） |

### 3.5 行为树调用 API

新增 `OpponentBrain.tick(opponent_state, game_state)` 返回 `Dictionary`：
```
{
  "action": "add_short" / "bad_news" / ...,
  "params": {"N": 200, "X": 0.025, ...},  # 实际数值
  "bubble": "你给我等着" 或 ""             # 是否要弹气泡
}
```
然后由 `GameState._apply_opponent_action()` 真正改状态、压股价、发信号、追加分时K。

---

## 4. 三档 Boss 配置

### 4.1 第1关：保守型 "老六"（稳健派）

- **战斗风格**：稳健派，倾向减仓自救，行动温和
- **个性权重**：

| 加空 | 利空 | 减仓 | 静观 | 拉抬陷阱 |
|------|------|------|------|----------|
| 1.0 | 1.0 | 1.5 | 1.5 | 0 |

- **难度参数**：

| 参数 | 值 |
|------|---|
| 起始仓位 N0 | 500 股 |
| 保证金池 M0 | 25,000 元 |
| 加空动作 N | 100 股/次，压股价 −1.5% |
| 散播利空 情绪 K | −3 |
| 主动减仓 M | 80 股/次 |
| 保命阈值 CRITICAL | 0.20 |
| 拉升反应阈值 REACTION | +3% |
| 硬扛权重（保命分支） | 0.1 |

- **台词样例**（key 写进 opponents.csv，UI 层渲染）：

| 时机 | 台词 |
|------|------|
| 入场 | "看见你赚得不错啊…叔叔来分一杯羹。" |
| 拉升反应 | "别太嚣张。" |
| 保命 | "顶不住了，先收一点。" |
| 强平 | "妈的，算我栽了。" |

### 4.2 第2关：强攻型 "大刀"（激进派）

- **战斗风格**：疯狂加空，敢硬扛
- **个性权重**：

| 加空 | 利空 | 减仓 | 静观 | 拉抬陷阱 |
|------|------|------|------|----------|
| 1.5 | 0.8 | 0.5 | 0.5 | 0 |

- **难度参数**：

| 参数 | 值 |
|------|---|
| 起始仓位 N0 | 1,000 股 |
| 保证金池 M0 | 60,000 元 |
| 加空动作 N | 200 股/次，压股价 −2.5% |
| 散播利空 情绪 K | −5 |
| 主动减仓 M | 100 股/次 |
| 保命阈值 CRITICAL | 0.10 |
| 拉升反应阈值 REACTION | +2% |
| 硬扛权重（保命分支） | 0.4 |

- **台词样例**：

| 时机 | 台词 |
|------|------|
| 入场 | "小鬼，别皮了。" |
| 拉升反应 | "敢拉？给我等着。" |
| 保命 | "草……" |
| 强平 | "*&%#！" |

### 4.3 第3关：狡猾型 "老蛇"（陷阱派）

- **战斗风格**：用拉抬陷阱诱玩家追高
- **个性权重**：

| 加空 | 利空 | 减仓 | 静观 | 拉抬陷阱 |
|------|------|------|------|----------|
| 1.0 | 1.5 | 1.0 | 1.0 | 1.2 |

- **难度参数**：

| 参数 | 值 |
|------|---|
| 起始仓位 N0 | 1,500 股 |
| 保证金池 M0 | 100,000 元 |
| 加空动作 N | 250 股/次，压股价 −3% |
| 散播利空 情绪 K | −7 |
| 主动减仓 M | 150 股/次 |
| 拉抬陷阱 Y | +2% |
| 保命阈值 CRITICAL | 0.18 |
| 拉升反应阈值 REACTION | +2.5% |
| 硬扛权重（保命分支） | 0.2 |

- **台词样例**：

| 时机 | 台词 |
|------|------|
| 入场 | "我看你像条肥鱼。" |
| 拉抬陷阱 | "看，涨了吧？追啊。" |
| 拉升反应 | "上钩了。" |
| 保命 | "啧，算你狠。" |
| 强平 | "你…怎么会…" |

---

## 5. 奖励系统

### 5.1 击败瞬间结算

- **市场情绪 Buff**：上涨情绪 `+15`（受 `clamp(0,100)` 限制）
- **本日剩余回合 buff**：所有"利空/砸盘"类卡牌的负面效果 ×0.5（一次性，到日结束失效）
- **专属奖励卡**：直接加入玩家 `draw_pile`（下次洗牌时随机进入抽牌堆）

### 5.2 三张专属奖励卡（占位设计，可在 implementation 阶段精调）

| 来源Boss | effect_id | 名称 | 类型 | 效果 | cost |
|----------|-----------|------|------|------|------|
| 老六 | `reward_six` | 保命之道 | SKILL | 上涨情绪 +8，本回合卖出获得现金 ×1.1 | 0 |
| 大刀 | `reward_blade` | 大刀斩盘 | SKILL | 直接压股价 −5%（玩家版砸盘卡，用于做T） | 1 |
| 老蛇 | `reward_snake` | 蛇影迷踪 | SKILL | 额外抽 3 张牌，不消耗行动力 | 0 |

> 这三张卡需要新增到 `data/cards.csv` 的行内，`in_starter=FALSE, in_shop=FALSE`，仅由"击败奖励"事件投放进牌组。

### 5.3 奖励UI反馈

- 击败瞬间弹出全屏 toast（淡入淡出 2s）："强平成功！获得《奖励卡名》+ 市场情绪 +15"
- 日志区追加一条 `[强平]` 高亮记录

---

## 6. UI / 视觉化

### 6.1 对手面板（左下，沿用现有 `enemy_panel.gd` 占位）

**布局**：

```
┌─ 对手面板 ─────────────────┐
│  ┌──┐  ┌─ 名牌 ─┐         │
│  │头│  │ 老六  │  气泡 →  │
│  │像│  └───────┘           │
│  └──┘  仓位: 500           │
│        均价: ¥120.5        │
│        保证金: ¥25,000     │
│        平仓线: ¥170.0      │
│  ▰▰▰▰▰▱▱▱▱▱  health 50%  │
└────────────────────────────┘
```

**字段**：
- 头像（占位用纯色矩形+名字，后期替换）
- 名牌：Boss 名 + "(在场)" / "(未出现)"
- 数值列表：仓位 / 均价 / 保证金 / 平仓线（明牌）
- **血条**：横向条，颜色 health > 60% 绿、30–60% 黄、< 30% 红
- 气泡：右侧浮出，淡入淡出 3s 后消失

### 6.2 K线区集成

- 分时K新增 `kind = "opponent"`，颜色统一红色实心（与玩家"出牌K"区分）
- tooltip 显示对手动作详情："加空 200 股 −2.5%"
- 入场瞬间在分时K里插一根 `kind="opponent_entry"`（特别图标）

### 6.3 日志

- 每个对手动作 push 一条带 tag 的日志：
  - `[庄家] 老六 加空 100 股, 压股价 −1.5%`
  - `[庄家] 老蛇 散播利空, 上涨情绪 −7`
  - `[庄家] 大刀 主动减仓 100 股, 平仓线 ¥175 → ¥182`
- 强平瞬间：`[强平] 老六 被击败！获得《保命之道》、市场情绪 +15`

---

## 7. 代码架构 与 现有系统接入

### 7.1 新增文件

```
Project/
├─ data/
│  └─ opponents.csv                          # 三个 Boss 的全部参数表
├─ scripts/
│  ├─ systems/
│  │  ├─ opponent_state.gd                   # RefCounted，对手数值状态
│  │  ├─ opponent_brain.gd                   # RefCounted，行为树+加权选择
│  │  └─ opponent_database.gd                # RefCounted，从 Cfg 读 Boss 配置
│  └─ views/
│     └─ enemy_panel.gd                      # 扩展现有占位为实际面板
└─ tests/                                    # 测试，沿用现有 run_rule_test 模式
   └─ opponent_brain_test.gd
```

### 7.2 修改现有文件

| 文件 | 改动 |
|------|------|
| `scripts/config/config_loader.gd` | 新增 `opponents` 字典加载 + `get_opponent_template(id)` + `opponents_csv` 路径常量 |
| `scripts/game_state.gd` | 新增 `_opponent_state`、`_opponent_brain`；接入 `_start_turn` 的入场判定、`_settle_turn` 自然波动前的行动 tick、`apply_price_change` 后的强平检测、新信号 |
| `scripts/main.gd` | 监听新信号、刷新对手面板 |
| `scenes/Main.tscn` | 替换 EnemyPanel 占位为实际 enemy_panel 节点 |
| `data/cards.csv` | 新增 3 张奖励卡条目（`reward_six` / `reward_blade` / `reward_snake`） |
| `data/balance.json` | 新增关卡→Boss 绑定 `LEVEL_OPPONENT_ID = ["boss_six","boss_blade","boss_snake"]` |

### 7.3 `opponents.csv` 列结构

```
opponent_id, display_name, personality, level,
n0, m0, action_n, action_x_pct, action_k_emotion, action_m_cover, pump_trap_y_pct,
critical_threshold, reaction_threshold, hard_hold_weight,
w_add_short, w_bad_news, w_cover, w_idle, w_pump_trap,
trigger_prob_per_turn, trigger_rise_pct,
dialog_enter, dialog_react, dialog_cover, dialog_trap, dialog_dying, dialog_defeat,
reward_card_id
```

### 7.4 新信号（`game_state.gd`）

```
signal opponent_entered(opponent_id: String)
signal opponent_acted(action_id: String, params: Dictionary)
signal opponent_state_changed                                # 仓位/平仓线/保证金任一变化
signal opponent_defeated(opponent_id: String, reward_card_id: String)
signal opponent_bubble(text: String)                         # 文字气泡
```

### 7.5 接入点（`game_state.gd`）伪代码

```gdscript
# 1) 关卡开始时绑定 Boss
func new_level() -> void:
    ...
    _opponent_state = OpponentState.new(_resolve_boss_id_for_current_level())
    _opponent_brain = OpponentBrain.new()

# 2) 每回合开始检查入场
func _start_turn() -> void:
    ...
    _check_opponent_spawn()    # 若满足条件 → 入场+立刻一次加空+发信号+气泡

# 3) 玩家 end_turn 之后, 自然波动之前, 对手行动
func _settle_turn() -> void:
    if _opponent_state.present and not _opponent_state.defeated_this_level:
        var decision = _opponent_brain.tick(_opponent_state, self)
        _apply_opponent_action(decision)
    # 然后才是 自然波动 + 提交回合K

# 4) 价格变化后立刻检查强平
func apply_price_change(rate, ignore_mod=false) -> void:
    ...   # 原有逻辑
    _check_opponent_liquidation()

# 5) 击败处理
func _on_opponent_liquidated() -> void:
    var reward_id = _opponent_state.reward_card_id
    apply_emotion_delta_bull(15)
    var card = CardDatabase.make_by_effect(reward_id, "reward_%s" % reward_id)
    draw_pile.append(card)
    _opponent_state.defeated_this_level = true
    _opponent_state.present = false
    emit_signal("opponent_defeated", _opponent_state.opponent_id, reward_id)
```

### 7.6 测试覆盖（最小集合）

| 测试 | 目标 |
|------|------|
| `opponent_brain_test.gd::test_critical_branch` | health 低于阈值 → 行为树进保命分支 |
| `opponent_brain_test.gd::test_reaction_branch` | 拉升触发反应分支必出 add_short 或 bad_news |
| `opponent_brain_test.gd::test_pump_trap_only_snake` | 老六/大刀的拉抬陷阱权重=0，永远不抽到 |
| `opponent_state_test.gd::test_liquidation_math` | 加空压平仓线、减仓推平仓线，数值与公式吻合 |
| `opponent_state_test.gd::test_liquidation_trigger` | current_price ≥ liquidation_price 立即触发 |
| 端到端：拉升 ≥20% 必触发入场 ; 击败后市场情绪+15、奖励卡进 draw_pile |

---

## 8. 风险与开放问题

| 风险 / 待精调 | 缓解 |
|---------------|------|
| 入场即满仓 + 立刻加空可能让玩家瞬间血崩，体感太挫败 | 用配置数值压制第1关（N0=500、X=1.5%）；后续可调 |
| 三档难度参数都是估值，需实测调 | balance.json 全部走配置，调参不改代码 |
| 行为树分支阈值若太敏感会刷屏弹气泡 | §3.4 已限定只在切换/高戏剧动作时弹 |
| 奖励卡 effect 用现有 CardEffectSystem 5 个原子操作（buy_pct/sell_pct/price_pct/emotion_delta/trade_price_pct），可能无法完整表达"本日剩余回合 buff" | "本日剩余回合 buff" 作为 GameState 上的临时 flag，结算时检查；与卡效系统解耦 |
| Boss 头像/图标资源缺失 | 先用纯色色块+名字占位，资源后补 |

---

## 9. 验收清单

- [ ] 新关卡开始时按 `LEVEL_OPPONENT_ID` 绑定到对应 Boss
- [ ] 第1关 day ≤ 2 永不触发对手
- [ ] 拉升必现阈值与概率触发都生效
- [ ] 对手数值（仓位/均价/保证金/平仓线）实时显示并刷新
- [ ] 血条颜色随 health_pct 在 60/30 阈值切换
- [ ] 加空动作压股价、减仓动作推平仓线、行为均反映在数值与日志
- [ ] 当前价 ≥ 平仓线 → 强平 → 情绪 +15、奖励卡入 draw_pile、本关不再触发
- [ ] 跨天保留：第二天对手状态延续，平仓线相对新开盘价正常计算
- [ ] 文字气泡在分支切换/高戏剧动作/强平时弹
- [ ] 全部参数走 `opponents.csv` + `balance.json`，改参数不改代码
- [ ] 测试通过：行为树各分支、强平数学、端到端入场→击败→奖励

---

## 10. 不在本设计内的范围（YAGNI）

- 复杂的剧情对话（仅几句台词，不做剧情树）
- 对手头像/立绘美术资源（先占位）
- 多对手并存（每关只一个）
- "潜伏状态对手"、第二/三章高级关卡（未来）
- 普通关卡的借款利息机制
- 监管系统（挑战关，已明确不做）

---

> 实施计划（plan）由后续 `writing-plans` 阶段产出，逐步拆解为：① 数据层接入 opponents.csv → ② 数值与行为树纯逻辑 → ③ GameState 接入信号 → ④ UI 面板与气泡 → ⑤ 奖励卡与端到端测试。
