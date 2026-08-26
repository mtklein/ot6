# Sealed Gate / Banquet route survey

## 1. The route, segment by segment

### Segment 7 — Vector → Albrook → the voyage → Crescent Island

Exit the castle and Vector; world walk to Albrook, `(138/139,203) → 323
(2,17)` — **33 steps** (offline BFS) from Vector's south exit.

With `$007D=1` the port gate at 323 (43,26)/(45,26) opens
(`_cc62f2/_cc632d`, `:91543/:91585`), and Albrook NPCs switch to pre-departure
lines (the `$007D` branch cluster, `:90701-91940`). The port is **map 332**
(via `323 long (43,29) → 332 (22,2)`; Leo NPCs in `NPCProp::_332`,
`npc_prop.asm:14422+`):

- If GAU is available (he is, on this chain), he follows the party and refuses to
  board at 332 (10,10)/(11,10): "He hates ships. We must…leave him behind!" The
  script runs **`char_party GAU, 0` and `switch $02FB=0`** (`_cbcb74/_cbcbde`,
  `:67905/:67978`).
- The pier scene (`_cbcc84`, `:68091+`): Leo introduces the traveling party,
  **"General CELES…and SHADOW"** (dlg `$0768`, `:68254`). Celes appears
  here as an **NPC**, not a party member, and Shadow gets his codex intro. After
  "Our departure isn't till tomorrow" there is a controllable night window in
  Albrook (`$0084/$0085`, `:68308-68310`).
- "Right… let's go" (`$0083=1`, `:68383`) → scripted sail: `load_map 0
  {138,206}` + `ship_gfx` world script (`:68390-68393`), back aboard (the
  ship interior is part of map 332); night watch: **`char_party LOCKE, 0`,
  `party_chars TERRA`** (`:68483-68488`) — Terra alone for the Leo
  conversation (`_cbcefc`, `:68497+`), then the Shadow scene ("In this world
  are many like me who've killed their emotions", `:68854`), Locke's
  seasickness scene, second sail segment `load_map 0 {193,157}` (`:68963`),
  `$0086=1` (`:69018`), and Leo's split briefing: "CELES and I will form one
  group. TERRA, you go with LOCKE and SHADOW" (`_cbd1f3`, `:69024`).
- Landing (`:69154-69190`): `char_party LOCKE, 1`, **`create_obj SHADOW` +
  `char_party SHADOW, 1` + `$02F3=1` + `norm_lvl SHADOW`**, `set_b_switch
  $4B`, and the party is placed on the world map at **(232,150)**, Crescent
  Island, controllable.

The **stop line** is: world (232,150), party TERRA · LOCKE · SHADOW,
`$007D=1 $0083=1 $0086=1`, airship still unavailable (`$007A=1`), Gau
unavailable (`$02FB=0`). The Thamasa world trigger (`_cbd2ee`, `:69190` → map
343 (23,46)) is at **(250,128)**, a 40+ step walk from the stop line across
encounter-active ground, so it is not usable as an entry point. Crescent
Island's world trash is split by terrain across three encounter groups, not one.

---

## Appendix — key addresses

| thing | citation |
|---|---|
| Albrook port gate | `_cc62f2/_cc632d` `:91543/:91585` (323 (43,26)/(45,26)) |
| Gau refuses the ship | `_cbcb74/_cbcbde` `:67905/:67978`; `$02FB=0` `:67952` |
| Celes+Shadow intro | dlg `$0768` `:68254` |
| voyage / night deck | sail `:68390`; `party_chars TERRA` `:68488`; Leo talk `_cbcefc` `:68497`; second sail `:68963` |
| landing / SHADOW joins | `:69154-69160`; world **(232,150)** `:69188` |
| Thamasa world trigger | `_cbd2ee` `:69190` → map 343 (23,46), world (250,128) |
| world battle indexing | `field/battle.asm:97-147` (`CheckBattleWorld`); sub chain per `break-coverage-vector.md` §1 |
