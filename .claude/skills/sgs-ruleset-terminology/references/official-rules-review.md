# Official Rules Review Notes

Source reviewed: [三国杀官方规则集 3.0](https://gltjk.com/sanguosha/rules/)

This note records the main places where the draft is either confirmed by the official rules text or should be tightened for consistency.

## Confirmed by the Official Rules

- `为` vs `视为` in the value section: the rules explicitly distinguish ordinary assignment from a treated-as value that remains the final assigned value.
- `使用` vs `打出`: the rules define them separately in `2.8 游戏牌的操作`.
- `抵消` vs `取消`: the rules define them separately in `2.7 事件、响应与结算`.
- `展示` vs `亮出`: the rules define different face-up behaviors in `2.8 游戏牌的操作`.
- `无效` vs `无视`: the rules define different mechanics in `2.7 事件、响应与结算`.
- `角色的牌` vs `角色拥有的牌`: the rules define ownership and judgment-zone exceptions in `2.3 区域`.
- `横置`, `重置`, `连环状态`, and `翻面`: the rules define these separately in `2.9 武将牌的操作`.

## Draft Issues To Correct

### 1. `游戏牌` -> avoid `Library Card`

The official rules only define `游戏牌` as the shared cards used during the game. `Library Card` is not grounded in the source and clashes with the draft's own sentence `Every Game Card...`.

Recommended project term: `Game Card`

### 2. `西` faction naming is internally inconsistent

The draft uses `Xi-faction` in running prose but maps `西 -> Western` in the faction list. Pick one and keep it everywhere. Because faction names behave like proper nouns, `Xi` is the safer project label.

Recommended project term: `Xi`

### 3. `展示` and `亮出` should not both collapse to bare `Reveal`

The draft currently distinguishes them with parenthetical notes, which is directionally correct, but this is fragile inside actual skill text. The official rules distinguish temporary face-up showing from turning a card face-up.

Recommended project terms:
- `展示` -> `Show`
- `亮出` -> `Reveal`

### 4. `打出` -> `Play out` is understandable but clunky

The official rules define `打出` as its own operation. The project should keep it distinct from `使用`, but `Play out` is not a very stable term for repeated UI and glossary use.

Recommended project term: `Play`

### 5. `横置` translated as `horizontal position` loses the verbal sense

The source defines an operation, not only a state. Use an action label.

Recommended project term: `Turn sideways`

### 6. `准备阶段` and `出牌阶段` should use stable phase labels

The source provides only Chinese names. If you keep English phase labels, use a single style across all phase names. `Starting Phase` plus `Action Phase` is workable, but `Preparation Phase` plus `Play Phase` tracks the Chinese operations more closely and matches the skill terminology elsewhere.

Recommended project terms:
- `准备阶段` -> `Preparation Phase`
- `出牌阶段` -> `Play Phase`

## Source Anchors

- `2.3 区域`: ownership, judgment zone, and `角色的牌`
- `2.4 数值`: `为`, `视为`, HP-related numeric terminology
- `2.7 事件、响应与结算`: `无效`, `无视`, `抵消`, `取消`
- `2.8 游戏牌的操作`: `使用`, `打出`, `展示`, `亮出`, `代替`, `替换`, `获得`, `失去`
- `2.9 武将牌的操作`: `横置`, `重置`, `连环状态`, `翻面`
- `3.1 游戏的流程` and `3.14-3.15`: turn flow plus dying and death procedures
