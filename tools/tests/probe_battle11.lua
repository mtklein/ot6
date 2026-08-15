-- probe_battle11.lua -- #74/#75: why battle 11 (the South Figaro gate
-- soldier) ends after a single action with both sides alive.
--
--   tools/tests/run.sh tools/tests/probe_battle11.lua
--
-- The measurement this exists to explain, taken 2026-08-11 over six battle
-- RNG seeds and identical on all six: solo LOCKE (168 hp, back row, armed
-- through the real Equip->Optimum walk) opens his command window ONCE, his
-- one Fight takes the HeavyArmor from 495/sh3 to 489/sh2, the soldier takes
-- him to 111, and then every value in the battle freezes for ~420 frames
-- before the module is torn down and the party lands on map 75 (47,43) with
-- the disguise switches cleared.  That landing is `_ca85ba`
-- (event_main.asm:20346), the scenario reset, and it is reached from
-- `_ca854f` (:20296) by FALLING THROUGH `if_b_switch $40` -- EventCmd_b7
-- jumps when the bit is CLEAR (field/event.asm:4053-4060) -- so the reset
-- means battle switch $40 was SET.  The only writer of that bit inside the
-- battle module is LoseBattle (`lda #$01 / tsb $3ebc`, battle_main.asm:
-- 16041-16042, "game over after battle ends").  So the game believes the
-- party was wiped while LOCKE is standing at 111 of 168.
--
-- Driver-level logging cannot see past that.  This probe hooks the battle
-- module itself and samples the cells the end-of-battle decision is made
-- from, logging only on change:
--
--   $3A74/$3A76  characters alive (mask / count), rebuilt by UpdateDead
--                (battle_main.asm:12551-12610).  CheckBattleEnd (:12153)
--                calls LoseBattle with battle message $29 "annihilated"
--                when $3A74 reads zero (:12170, :12822-12830).
--   $3A75/$3A77  monsters alive, the other termination condition.
--   $3AA0/$3AA8  the per-entity "target present" bit ($xx.0), which
--                UpdateDead reads before it looks at status at all: an
--                entity that is not PRESENT is not alive, whatever its hp.
--   $3EE4+e*2    status 1 per entity; bits $C2 (wound/petrify/zombie) drop
--                an entity out of $3A74 with its hp untouched.
--   $2F4C/$2F4E  can't-be-targetted / can-be-targetted masks, which
--                UpdateDead applies before everything else.
--   $3EBC        the battle termination flags themselves ($01 game over,
--                $10 banquet timeout, $20 timer expired, $80 zone eater).
--   $1DD1        the FIELD copy of that byte on the way in: bit 5 set on
--                entry makes CheckBattleEnd end the battle immediately at
--                its first call, whatever the hp are (:12163-12166).
--   $2D6E/$2D6F  the battle script's message command and index, which names
--                the message the end sequence is about to draw.
--   $3A6E/$3EE0  the end-of-battle special event and its enable, which
--                divert CheckBattleEnd into BattleEndTbl (:12155-12160).
--
-- and puts exec callbacks on CheckBattleEnd, LoseBattle, WinBattle,
-- BattleEnd_01/_04, ShowMsg and TerminateBattle so the decision is
-- attributed to a named routine rather than inferred from a sample.  Every
-- symbol here is unique in ff6-en.dbg (checked: trap 3 is `ExecCmd`, which
-- this does not hook).
--
-- This probe asserts nothing about the outcome.  It fights the soldier the
-- way gen_sfigaro does -- same equip stop, same row, same H.rideOut fight
-- driver -- and reports.  A probe that required a win could not run at all
-- while the win is the thing that does not happen.
--
-- ANSWER, measured 2026-08-12 (build/probe11.log, ROM b91da4fb9cef):
-- **the party is wiped.  LOCKE dies.  Nothing exotic happens at all.**
-- The frame-by-frame watch:
--
--   f1140  battle up: LOCKE 168, HeavyArmor 495 / 3 shields
--   f1385  LOCKE 168 -> 111          the soldier's 1st action, 57 damage
--   f1504  HeavyArmor 495 -> 489     LOCKE's one Fight, and one shield
--   f1957  LOCKE 111 -> 0, $3EE4 = $80 (wound)
--                                    the soldier's 2nd action, >=111 damage
--   f2218  UpdateDead: $3A74 01 -> 00, $3A76 1 -> 0
--   f2235  LoseBattle, A = $29 ("annihilated")
--   f2236  $3EBC 00 -> 01            -> battle switch $40
--   f2268  message $29 drawn
--   f2290  TerminateBattle
--   then `if_b_switch $40` falls through to _ca85ba: map 75 (47,43),
--   $0104 = 0, LOCKE revived at full hp.
--
-- Hook fire counts for the whole battle: LoseBattle 1, ShowMsg 1,
-- TerminateBattle 1, CheckBattleEnd 367, UpdateDead 5, and WinBattle,
-- BattleEnd_01 and BattleEnd_04 zero.  So no scripted end-of-battle event
-- is involved: $3EE0 reads $FF all battle but $3A6E stays 0, which is the
-- second half of CheckBattleEnd's guard (:12155-12159), so BattleEndTbl is
-- never entered.  $1DD1 reads $00 on the way in, so the "end battle if
-- timer expires" path (:12163-12166) is not armed either.
--
-- The "both sides alive, everything frozen for 420 frames" reading came
-- from the fight driver's own log, and it is an artifact of where that log
-- stops.  M.battleLoadStarted() calls a party table of all zeros "not a
-- battle" -- its documented and accepted limit (lib/ot6.lua:436-440) -- so
-- the frame LOCKE hits 0 the driver switches to F.idle(), battleTick
-- resets, and no further `battle f+N` line is ever printed.  The last line
-- printed is therefore the last frame LOCKE was alive, showing him at 111,
-- and it is followed by silence rather than by a death.  Reading back from
-- the log, that silence looks like a battle that stopped responding.  The
-- identical lines before it are real: between LOCKE's swing at f1504 and
-- his death at f1957 neither side had a turn, because at this level one
-- ATB round is about 570 frames.
--
-- WHAT KILLS HIM, measured rather than inferred (second run, with
-- ShowAttackName hooked).  Three attack resolutions in the whole fight:
--
--   f1384  x=$0008 (monster)  $3A7C=$00  $B3=$DF  $3A70=1   168 -> 111
--   f1503  x=$0000 (LOCKE)    $3A7C=$00  $B3=$DF  $3A70=1   495 -> 489
--   f1956  x=$0008 (monster)  $3A7C=$0C  $B3=$FF  $3A70=0   111 -> 0
--
-- `$3A7C` is the command byte (`stz $3a7c ; change command to fight`,
-- battle_main.asm:449).  $00 is Fight, so the first two are weapon swings
-- and carry `$B3` bit 7 CLEAR, which is what the row code halves — the
-- soldier's 57 is the halved physical, exactly the "~53" the 2026-08-09
-- record describes.  The killing action is command **$0C**, `Cmd_0c` /
-- `_actbluemagic0` (:3740), the monster-magic path, and it carries
-- `$B3 = $FF`, so **the back row does not halve it** (HANDOFF: "$B3 = $FF
-- for every command and only the weapon swing clears it").  It lands once,
-- `$3A70 = 0`, for over 111 — it is one big row-exempt hit, not two small
-- ones.  That is the AI's turn-2 line `attack BATTLE, TEK_LASER, SPECIAL`
-- (ai_script.asm:342-357) rolling one of the two non-physicals; the macro
-- emits `$F0`, one of three at random (ai_script.inc's `attack` macro).
--
-- So the fight ends on a single row-exempt special that one-shots LOCKE
-- from 66% of his HP.  No bag fixes that: the heal rule cannot fire between
-- 66% and death, and no Tonic covers a 111-damage hit.  His own Fight takes
-- 6 off 495 and one shield off three, and the bag holds exactly one weapon
-- (item $00, the Dirk, power 26 at item_prop_en.dat +$14), so
-- The named loadout already puts on the best gear there is.
--
-- This is why the 2026-08-09 "solo LOCKE beats the gate soldier" record
-- (95efb39) cannot be reproduced, and two of its own numbers do not survive
-- checking.  It claims "shields 3 -> 0 three times over, 495 hp -> 0, LOCKE
-- never below 112", which needs about fourteen monster turns without the
-- 2-in-3 non-physical roll ever coming up.  And it claims LOCKE "inherits 12
-- Tonics and 4 Potions"; no locke_scenario fixture has ever held that,
-- including the Jul-22 file the owner still has, which holds Tonic x2 and
-- Potion x4 — and gen_sfigaro can only spend from that bag, never add to it.
-- Checked and NOT the difference: LOCKE's level (8), HP (168) and only
-- weapon (the Dirk) are identical across all three locke_scenario fixtures
-- from Jul 22 to Aug 12; HeavyArmor's authored 3 shields and SLASH|PIERCE
-- weakness are byte-identical at 95efb39 and today (ot6_hud.asm's
-- Ot6ShieldTbl); the multi-hit dial hooks only the Blitz and Tools command
-- handlers (ot6_hitcount.asm), so a monster cannot pick a count up from it;
-- and Ot6FightBoost refuses non-characters outright ("monsters never boost",
-- ot6_boost.asm:490-492).  The "21 damage a swing" in that record was the
-- FRONT-row armed swing, measured before the row fix in the same commit;
-- halved by the row and halved again by a shield it is the 6 measured here.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/locke_scenario.mss.lua"

local function map() return H.mapId() & 0x1ff end

-- ------------------------------------------------------------- the watch --
-- byte cells, sampled every frame and logged only when one moves.  Words
-- are listed separately so the log reads as numbers rather than as bytes.
local BYTES = {
  { "3A74 charsAlive", 0x3A74 }, { "3A75 monsAlive", 0x3A75 },
  { "3A76 nChars", 0x3A76 },     { "3A77 nMons", 0x3A77 },
  { "3A78", 0x3A78 },            { "3A79", 0x3A79 },
  { "3AA0 c0pres", 0x3AA0 },     { "3AA2 c1pres", 0x3AA2 },
  { "3AA8 m0pres", 0x3AA8 },
  { "2F4C", 0x2F4C },            { "2F4D", 0x2F4D },
  { "2F4E", 0x2F4E },            { "2F4F", 0x2F4F },
  { "3EBC term", 0x3EBC },       { "3EBD", 0x3EBD },
  { "3EE4 c0st1", 0x3EE4 },      { "3EE5 c0st2", 0x3EE5 },
  { "3EEC m0st1", 0x3EEC },      { "3EED m0st2", 0x3EED },
  { "3A40 asEnemy", 0x3A40 },    { "3A42 charMons", 0x3A42 },
  { "3A46", 0x3A46 },            { "3A95 lastHidden", 0x3A95 },
  { "3A6E endEvent", 0x3A6E },   { "3EE0 endEnable", 0x3EE0 },
  { "2D6E msgCmd", 0x2D6E },     { "2D6F msgIdx", 0x2D6F },
  { "3408", 0x3408 },            { "3409", 0x3409 },
  { "3219 c0atb", 0x3219 },      { "3221 m0atb", 0x3221 },
  { "3A70 nAtk", 0x3A70 },       { "3A7C atkIdx", 0x3A7C },
  { "B3 rowflag", 0x00B3 },
}
local WORDS = {
  { "hpC0", 0x3BF4 }, { "hpM0", 0x3BFC },
}

local watching, prev = false, {}
local function sampleLine()
  local out = {}
  for _, c in ipairs(BYTES) do
    out[#out + 1] = string.format("%s=%02X", c[1], H.readByte(c[2]))
  end
  for _, c in ipairs(WORDS) do
    out[#out + 1] = string.format("%s=%d", c[1], H.readWord(c[2]))
  end
  return table.concat(out, " ")
end

local function watchTick()
  if not watching then return end
  local changed = {}
  for _, c in ipairs(BYTES) do
    local v = H.readByte(c[2])
    if prev[c[1]] ~= v then
      changed[#changed + 1] = string.format("%s %s->%02X", c[1],
        prev[c[1]] and string.format("%02X", prev[c[1]]) or "--", v)
      prev[c[1]] = v
    end
  end
  for _, c in ipairs(WORDS) do
    local v = H.readWord(c[2])
    if prev[c[1]] ~= v then
      changed[#changed + 1] = string.format("%s %s->%d", c[1],
        prev[c[1]] and tostring(prev[c[1]]) or "--", v)
      prev[c[1]] = v
    end
  end
  if #changed > 0 then
    H.log(string.format("[watch f%d] %s", H.frame, table.concat(changed, "  ")))
  end
end

-- ------------------------------------------------------------- the hooks --
-- Each hook prints the whole sampled state, not just its own name: the
-- question is what the module believed at the moment it decided, and a bare
-- "LoseBattle fired" would only move the question one step back.
-- Names are spelled out at each H.sym call rather than looped over a list of
-- strings: compose.py injects OT6_SYMS by scanning the source for literal
-- `sym("Name")` occurrences (lib/compose.py:439-449), so `H.sym(name)` with
-- a variable resolves nothing and raises "symbol not in ff6-en.dbg" at run
-- time.  Measured here on the first run of this probe.
local fires = {}
local function hook(name, addr, cap)
  local n = 0
  emu.addMemoryCallback(function()
    n = n + 1
    fires[name] = n
    if n > (cap or 8) then return end
    local st = emu.getState()
    H.log(string.format("[hook f%d] %s #%d @$%06X a=%02X x=%04X | %s",
      H.frame, name, n, addr, st["cpu.a"] & 0xFF, st["cpu.x"] & 0xFFFF,
      sampleLine()))
  end, emu.callbackType.exec, addr, addr)
  H.log(string.format("hooked %s at $%06X", name, addr))
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75, occupied South Figaro")
    H.assertEq(H.hasControl(), true, "controllable")
  end),
  H.equipLoadout(1, {
    { 0, 0x00 }, -- Dirk: the only weapon in this checkpoint's bag
    { 2, 0x69 }, -- Leather Hat
    { 3, 0x84 }, -- LeatherArmor
  }, { tag = "LOCKE battle-11 control kit" }),
  H.setRows({ [1] = true }, { tag = "locke solo rows" }),

  H.call(function()
    -- The field copy of the battle-termination byte on the way in.  Bit 5
    -- here is the "end battle immediately" path (battle_main.asm:12163):
    -- if it is already set before the fight, every battle on this route
    -- ends at its first CheckBattleEnd call regardless of hp.
    local bsw = {}
    for a = 0x1DC9, 0x1DD8 do bsw[#bsw + 1] = string.format("%02X", H.readByte(a)) end
    H.log(string.format("pre-battle: $1DD1=%02X $1DD2=%02X $1DC9..$1DD8=%s",
      H.readByte(0x1DD1), H.readByte(0x1DD2), table.concat(bsw, " ")))
    H.log(string.format("pre-battle: obj26 at (%d,%d), party at (%d,%d)",
      H.objX(26), H.objY(26), H.fieldX(), H.fieldY()))
    -- The bag and LOCKE's record, at the fight rather than at the fixture.
    -- The 2026-08-09 winning run says it inherited 12 Tonics and 4 Potions
    -- and swung for 21; whether this run has the same inputs is what
    -- separates "the route regressed" from "the fight was retuned".
    local bag = {}
    for i = 0, 63 do
      local id, q = H.readByte(0x1869 + i), H.readByte(0x1969 + i)
      if id ~= 0xFF and q > 0 then
        bag[#bag + 1] = string.format("$%02X x%d", id, q)
      end
    end
    H.log("pre-battle bag: " .. table.concat(bag, " "))
    local r = 0x1600 + 37
    H.log(string.format("pre-battle LOCKE: L%d hp %d/%d gear %02X %02X %02X %02X %02X  gp=%d",
      H.readByte(r + 8), H.readWord(r + 9), H.readWord(r + 11),
      H.readByte(r + 0x1F), H.readByte(r + 0x20), H.readByte(r + 0x21),
      H.readByte(r + 0x22), H.readByte(r + 0x23),
      H.readByte(0x1860) | (H.readByte(0x1861) << 8) | (H.readByte(0x1862) << 16)))
    -- Attribute every damage event to an attack rather than guessing from
    -- its size.  $3A7C is the attack index ExecAttack works from, $3A70 is
    -- the engine's one multi-hit counter (0 = one attack,
    -- ot6_hitcount.asm:14-22), and $B3 bit 7 is what the row code reads --
    -- together they say what struck, how many times, and whether the back
    -- row halved it.  The 2026-08-09 record has this fight won with every
    -- monster hit at the halved ~53; the killing hit measured here is over
    -- 111, so which of the AI's three turn-2 rolls it was, and whether it
    -- landed once or twice, is the whole question.
    hook("ShowAttackName", H.sym("ShowAttackName"), 40)
    hook("CheckBattleEnd", H.sym("CheckBattleEnd"), 60)
    hook("LoseBattle", H.sym("LoseBattle"), 8)
    hook("WinBattle", H.sym("WinBattle"), 8)
    hook("BattleEnd_01", H.sym("BattleEnd_01"), 8)
    hook("BattleEnd_04", H.sym("BattleEnd_04"), 8)
    hook("ShowMsg", H.sym("ShowMsg"), 16)
    hook("TerminateBattle", H.sym("TerminateBattle"), 8)
    hook("UpdateDead", H.sym("UpdateDead"), 0)
    emu.addEventCallback(function() watchTick() end, emu.eventType.startFrame)
    watching = true
  end),

  H.talkToObj(26, "gate soldier (battle 11)"),
  H.rideOut("ride battle 11 out", 30000, 75),

  H.call(function()
    watching = false
    local t = {}
    for k, v in pairs(fires) do t[#t + 1] = string.format("%s=%d", k, v) end
    table.sort(t)
    H.log("hook fire counts: " .. table.concat(t, " "))
    H.log(string.format("after: map=%d (%d,%d) $1DD1=%02X",
      map(), H.fieldX(), H.fieldY(), H.readByte(0x1DD1)))
    H.log(string.format("outcome: %s",
      (H.fieldX() == 47 and H.fieldY() == 43) and "SCENARIO RESET (loss)"
        or "not the reset tile"))
  end),
})
