# OT6 v0.6 — Vector / Magitek Research Facility reference

## 7. Switches `$01B0`-`$01B7` are not story bits

They are never set by a `switch` opcode, and reading them as story flags is a
category error.

Switch `$01B0` = `$1E80 + ($1B0>>3)` = **`$1EB6` bit 0**. `$1EB6` is an engine
state byte:

```
ff6/notes/field-ram.txt:1072-1080
      $1EB6 sotaldru
            s: serpent trench arrow direction
            o: map's object data needs to be loaded
            t: tile event bit (gets cleared when the party moves to a new tile)
            a: A button is down
            l: character is facing left
            d: character is facing down
            r: character is facing right
            u: character is facing up
```

(The notes list bit 7 first; confirmed by the same file's `$1EB9 up?s????`
against `field-ram.txt:427`, "Clear event bit `$1EB9.7`".)

Confirmed in code, three ways:

```
ff6/src/field/event.asm:5415-5433   UpdateCtrlFlags
        lda $087f,y        ; party facing direction (0=UP 1=RIGHT 2=DOWN 3=LEFT,
        tax                ;  const.inc:72-77 EVENT_DIR)
        lda $1eb6
        and #$f0
        ora f:BitOrTbl,x   ; BitOrTbl = BIT_0..BIT_7  (event.asm:5523-5524)
        sta $1eb6
        lda $06            ; A button
        bpl :+
        lda $1eb6 / ora #$10 / sta $1eb6      ; bit 4 = A held
:       lda $1eb6 / and #$ef / sta $1eb6
```
```
ff6/src/field/event.asm:92     jsr UpdateCtrlFlags   (top of ExecEvent, every event tick)
ff6/src/field/player.asm:529-531   lda $1eb6 / and #$df / sta $1eb6   ; clear bit5 each step
ff6/src/field/init.asm:465-476     bit6 = object-map-update flag
```

Therefore:

| switch | meaning |
|---|---|
| `$01B0` | party is facing **UP** |
| `$01B1` | party is facing **RIGHT** |
| `$01B2` | party is facing **DOWN** |
| `$01B3` | party is facing **LEFT** |
| `$01B4` | **A button is held this frame** |
| `$01B5` | tile-event bit (cleared on every step — a "once per tile" latch) |
| `$01B6` | map object data needs loading (map-init guard) |
| `$01B7` | serpent-trench arrow direction |

This is what arms the opera weight trap (`_cab497` needs `$01B0=1 && $01B4=1` =
*face up and hold A*), and it is load-bearing across the Vector area:

- `_cc96c9` (Vector sneak ledge): `$01B2` = face DOWN.
- `_cc7a60` (esper tube room): `$01B0 && $01B4` = face UP + hold A.
- `_cc76cc` / `_cc76f1` (map 262 platform hops): `$01B1`/`$01B3` + `$01B4`.
- `$01B5` guards every one-shot door-opening trigger on map 262
  (`_cc7735`/`_cc7753`/`_cc77b0`/`_cc77ce`, `event_main.asm:94960-95050`).

**Consequence for the driver:** `navTo` releases the pad between steps and never
presses A on the open field (`ot6_field.lua:340-351`). Every one of these
triggers needs a bespoke "arrive facing D, then hold A" step. This is not
optional and it is not discoverable by walking.

`$022F` note, while on the subject: `if_switch $022F=0, X` appears 83 times in
`event_main.asm` and **`switch $022F=…` appears zero times**. It is the
disassembly's rendering of an unconditional long jump. Read those as `goto X`.

---

## Appendix — key addresses

| thing | citation |
|---|---|
| Vector world trigger | `event_trigger.asm:36-37` → `event_main.asm:14196` `_ca5ecf` |
| Vector old man (choice) | `npc_prop.asm:10770` → `event_main.asm:99897` `_cc9627`; `$01F0=1` at `:100017` |
| Vector sneak ledge | `event_trigger.asm:1067` → `event_main.asm:100025` `_cc96c9` |
| Vector "caught" trap | `event_trigger.asm:1070-1072` → `event_main.asm:99473` `_cc93dc` → `battle 29` |
| Factory door | map 242 long entrance `(57,2)` len 2 → map 262 `(28,8)` |
| Kefka esper-drain | `event_main.asm:94409` `_cc7451`, `switch $005F=1` `:94620` |
| Chute 263→264 | `event_main.asm:94649` `_cc7588`, `load_map 264` `:94665` |
| Ifrit / Shiva NPCs | `npc_prop.asm:12289`, `:12298` (map 264) |
| Ifrit fight | `event_main.asm:95260` `_cc7937`, **`battle 70` `:95283`** → formation 439; the live species words `$57C0` read `0109 0108 0109 0108 FFFF FFFF` — **Ifrit and Shiva are both present from the first frame**, no AI-script entrance |
| esper hand-off | `event_main.asm:95331` `_cc79a4`; magicite `_cc79cd` `:95359`, `_cc79dd` `:95372` |
| Number 024 | `npc_prop.asm:12478` → `event_main.asm:95385` `_cc79ed`, **`battle 72`** → formation 441 = `$010a` |
| tube-room switch | `event_trigger.asm:1216` → `event_main.asm:95456` `_cc7a60` (facing UP + A) |
| six espers | `event_main.asm:95777-95782` |
| Celes leaves | `event_main.asm:96148-96158` |
| lift | `event_trigger.asm:1217` → `event_main.asm:96313` `_cc7f43` |
| minecart | `event_main.asm:96580` `cutscene TRAIN`; script `world/train_script.asm:615-660` |
| **Number 128** | `world/train_script.asm:899-917` `TrainCmd_e2`, event battle `$49` = **battle 73** → formation 442 = `$010b` + `$0140` + `$013f` |
| escape control point | `event_main.asm:96684-96690` (map 240, save point (58,7)) |
| Setzer joins | `event_main.asm:96980-96985` |
| Cranes | `event_main.asm:46907` `_cb3ff1` → **`battle 71`** `:47070` → formation 440 = `$010d` + `$010e` |
| Terra return chain | `event_main.asm:30250` `_cac3c7` → `:30361` `_cac4b0` → flashback → `:25241` `_caa4e0` |
| **Terra available** | `event_main.asm:25542` `switch $02F0=1` (= `$1EDE` bit 0) |
| v0.6 stop line | `event_main.asm:25669` `call _cacb95` (map 6, Blackjack cabin) |
| `$01B0`-`$01B7` decode | `notes/field-ram.txt:1072-1080`; `field/event.asm:5415-5433`, `:92`, `:5523`; `field/player.asm:529-531`; `include/const.inc:72-77` |
| `$02F0`-`$02FD` decode | `notes/field-ram.txt:1114-1116`; `field/event.asm:4443-4448`; `event_main.asm:30939-31010` |
| event-battle → formation | `field/battle.asm:506-517`; `field/event.asm:1907-1935`; `battle/battle_main.asm:16494-16505` |
| ROM/vanilla data identity | `ff6/rom/ff6-en.map:200,201,226,289,323,325` |
