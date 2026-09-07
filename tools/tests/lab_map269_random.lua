-- @manual
-- lab_map269_random.lua -- the map-269 random lab (issue #171): the first
-- random after the Ifrit & Shiva save, which killed full-HP L16 LOCKE (447)
-- and CELES (443) in one hit each in the n024_entry regeneration
-- (build/states/n024_entry.log: "slot 4's smallest hit this fight so far:
-- 447, on entity 2 (447 -> 0)" / "443, on entity 3 (443 -> 0)").
--
-- THE FIGHT, DECODED (monster_prop.dat / ai_script.asm / magic_prop_en.dat
-- / ot6_hud.asm; every byte below was compared with the vanilla ROM)
--
--   map 269 rolls encounter group 105 (tools/audit_encounters.py 269):
--     31.25%  $077  General($066) x2                 (pincer possible)
--     31.25%  $078  Pipsqueak($041) x2 + General x1   (pincer possible)
--     37.50%  $076  Trapper($02d) x3                 <- the fight in the log
--   The log's three monsters read 555/555 with two shields each; 555 is
--   Trapper's HP exactly (General 650, Pipsqueak 250).  battle_monsters.dat
--   $076 = present mask $1c, species $2d $2d $2d in slots 2-4 (the log's
--   "monhp=s2,s3,s4").
--
--   $02d Trapper   L19  HP 555  MP 80  speed 35  atk 13  def 180  mdef 135
--                  mpow 10   weak BOLT|WATER ($84)  absorb/null none
--                  XP 235  GP 200.  All 32 bytes identical to the vanilla
--                  ROM record (monster_prop.dat +$05A0 vs "Final Fantasy
--                  III (USA).sfc" $0F05A0).
--                  shields 2, class key OT6_BLUDG (Ot6ShieldTbl,
--                  ot6_hud.asm:1748); no Ot6ElemAddTbl row.
--                  special $57 = "Program 18": bit $40 set = deals NO
--                  damage (battle_main.asm:8447-8450 clears the attack
--                  power), effect $17 = status bit 23 = Reflect.
--   AI (ai_script.asm:1262 "trapper", AIScript::_45):
--       attack SPECIAL, L5_DOOM,   NOTHING   ; turn 1: one of the three
--       wait
--       attack SPECIAL, L4_FLARE,  NOTHING   ; turn 2
--       wait
--       attack SPECIAL, L3_MUDDLE, NOTHING   ; turn 3, then loop
--   It never uses Battle (a plain physical).  The only damage it can do is
--   L4 Flare ($95): power 66 (Fire 2 is 60), MAGIC, flags +2 = $60 =
--   IGNORE DEFENCE | NO SPLIT, +8 = 4: it hits EVERY target whose level is
--   a multiple of 4, each for the full unsplit roll, defence and row
--   ignored.  L5 Doom kills level-multiple-of-5 targets outright; L3
--   Muddle confuses level-multiple-of-3 targets.  All three spell records
--   are byte-identical to vanilla.
--
--   The routed party at the save (audit_levels / savestate_party over
--   magicite_ifrit_shiva.mss): LOCKE L16 447/447, EDGAR L17 502/502,
--   SABIN L17 0/511 (DEAD, status1 $80 -- battle 70 killed him and the
--   generator saved without a care stop), CELES L16 443/443 with 6/126 MP.
--   Rows: LOCKE front, EDGAR/SABIN/CELES back (the Zozo rows, $1850 bit
--   $20).  Gear: LOCKE ThunderBlade (BOLT, the element key) + Guardian via
--   Genji Glove; EDGAR RegalCutlass (slash, no key); SABIN MetalKnuckle
--   (slash on Fight; his Pummel is OT6_BLUDG, the class key); CELES
--   MithrilBlade (slash, no key), Ramuh (bolt, 25 MP) unaffordable at 6 MP.
--   Bag: 84 Tonics, 13 Fenix Downs, 2 Tinctures, 3 Elixirs, 1 X-Potion.
--   XP: LOCKE 13097 (L17 at 14152: 1055 short), CELES 13033 (1119 short).
--
--   So: L16 is a multiple of 4 and L17 is a multiple of nothing the
--   Trapper casts.  The two L16s are exactly the two who died; the two L17s
--   cannot be touched by any of its three spells.  "447 -> 0" is the roll
--   clamped to LOCKE's HP; the raw roll is measured below.
--
-- THE LAB
--
--   Fixture: build/states/m269lab_pre.mss -- the map-269 landing (44,53),
--   baked by tools/tests/probe_m269lab_bake.lua = gen_n024_entry's first
--   leg verbatim from magicite_ifrit_shiva (no care, no menu).  Ancestry:
--   build/m269lab/bake.log.
--
--   Per attempt: load the fixture, apply the policy's FIELD setup (a care
--   stop, rows: menu drives, logged), hold the pad neutral until
--   wGameTimeFrames ($021e, period 60) has advanced SEED phases (the
--   battle seed is $021e*4, lib/ot6.lua "battle rng seed"), then walk the
--   generator's own leg (44,53)->(42,12) until a random rolls.  Whatever
--   rolls is fought under the policy and logged.  After the fight the
--   generator's own care stop (navTo's newCareDriver, threshold 0.65,
--   Tonics only) runs, so a Fenix spent there counts the way audit_fenix
--   counts it.
--
--   CheckBattleSub (field/battle.asm) draws the encounter check from
--   RNGTbl[$1fa1] once per STEP and the formation slot from RNGTbl[$1fa2]
--   once per BATTLE; both counters live in the snapshot and neither an
--   idle frame nor a menu moves them, so from this fixture the first
--   random always rolls at the same step and always rolls $076 (Trapper
--   x3) -- the formation under study, not a formation spread; the other
--   two formations are covered by MODE=walk, which plays the whole map-269
--   leg.  The hold varies the BATTLE seed only, quantized to 4 frames
--   (the Zozo lab measured seeds 2/4, 6/8, ... drawing identical battles),
--   so the declared spread is seeds 0..56 step 4: 15 distinct battle
--   seeds, the whole $021e cycle.  control shares nothing with the cared
--   policies (they spend a menu drive first, so their $021e phase at the
--   step differs); cared / breakfirst / boostfight share the exact
--   pre-battle state per seed (a paired A/B); allback spends a second menu
--   drive and draws its own 15.
--
--   POLICY (@POLICY@, substituted by m269lab_batch.sh):
--     control     gen_n024_entry's leg as it ships: no care at the save
--                 (SABIN dead, CELES 6 MP), navTo's "tactical" driver with
--                 its defaults (tactical, boost, items, healPercent 55, no
--                 bank, AutoCrossbow, no designated healer)
--     cared       one fieldCare (threshold 0.95, the gen's own pre-battle-70
--                 stop) at the landing -- SABIN raised, HP topped -- then
--                 the control driver.  The owner's heal-outside-battles
--                 rule applied where the route skipped it.
--     allback     cared + LOCKE moved to the back row (the other three are
--                 already back): the row lever, for the record -- L4 Flare
--                 is magic and ignores row and defence
--     breakfirst  cared + bank 0: BP is spent as it comes, so LOCKE's first
--                 ThunderBlade Fight (bolt key, x4 through the element
--                 channel) and SABIN's first Pummel (bludgeon key) go out
--                 boosted on turn 1, and the driver focuses one Trapper at
--                 a time
--     boostfight  cared + bank 0 + tactical=false: everyone boost-Fights
--                 from turn 1 (no AutoCrossbow, no Pummel -- the memory's
--                 "boost-Fight through randoms" default; SABIN's Fight is
--                 slash, so this policy holds only LOCKE's key)
--
--   Privileged-information label: none of these policies reads hidden
--   state.  The bolt and bludgeon keys are the weapons the party already
--   wears; the level-multiple rule is what the screen says when "L.4
--   Flare" lands.  The lab's CPU observers (ExecCmd / _writedamage /
--   SaveForMimic exec callbacks, the seed store) are read-only measurement.
--
--   MODE (@MODE@): fight = one random, then the care stop, then [result];
--   walk = the whole leg (44,53)->(42,12) onto map 271, every random fought
--   under the policy with the care stop after each, one [walkbattle] line
--   per fight and a [walkresult] line at the end.
--
--   Reads and pad presses only.  A wipe is the measurement, not a retry
--   (allowGameOver).  One machine-readable [result]/[walkresult] line per
--   run.
local H = dofile("tools/tests/lib/ot6.lua")

local POLICY  = "@POLICY@"
local SEED    = tonumber("@SEED@") or 0
local MODE    = "@MODE@"
if POLICY:find("@") then POLICY = "control" end
if MODE:find("@") then MODE = "fight" end

local LOCKE, EDGAR, SABIN, CELES = 1, 4, 5, 6
local FENIX_DOWN, TONIC = 0xF0, 0xE8
local TRAPPER, GENERAL, PIPSQUEAK = 0x002D, 0x0066, 0x0041
local SPECIES = { [TRAPPER] = "Trapper", [GENERAL] = "General", [PIPSQUEAK] = "Pipsqueak" }
local ATTACK = { [0x00] = "Fire", [0x01] = "Ice", [0x02] = "Bolt",
                 [0x05] = "Fire2", [0x06] = "Ice2", [0x07] = "Bolt2",
                 [0x2D] = "Cure", [0x2F] = "Cure2", [0x5D] = "Pummel",
                 [0x94] = "L5Doom", [0x95] = "L4Flare", [0x96] = "L3Muddle",
                 [0x7D] = "BioBlaster", [0xA4] = "BioBlaster",
                 [0x7C] = "AutoCrossbow", [0xAA] = "AutoCrossbow",
                 [0xFF] = "Fight", [0xEE] = "Battle", [0xEF] = "Special" }
local function atkName(id)
  if id == 0x1FE then return "Nothing" end
  return ATTACK[id] or string.format("$%02X", id)
end

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local BCHID = 0x3ED8
local BCHP, BCMAXHP = 0x3BF4, 0x3C1C
local function map() return H.mapId() & 0x1ff end
local function charLevel(c) return H.readByte(0x1600 + 37 * c + 8) end
local function charXp(c)
  local b = 0x1600 + 37 * c + 0x11
  return H.readByte(b) | (H.readByte(b + 1) << 8) | (H.readByte(b + 2) << 16)
end
local function isBack(c) return (H.readByte(0x1850 + c) & 0x20) ~= 0 end
local function slotChar(s) return H.readByte(BCHID + s * 2) end
local function monSpecies(i) return H.readWord(0x57C0 + i * 2) end
local function monHp(i) return H.readWord(0x3BFC + i * 2) end
local function monShields(i) return H.readByte(0x3E40 + i * 2) end
local function monPresent(i) return H.readByte(0x3AA8 + i * 2) % 2 == 1 end
local function partyHp()
  local p = {}
  for e = 0, 3 do p[e + 1] = H.readWord(BCHP + e * 2) end
  return p
end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2), H.readWord(BCMAXHP + e * 2))
  end
  return table.concat(p, ",")
end
local function monsterLine()
  local m = {}
  for i = 0, 5 do
    if monPresent(i) then
      m[#m + 1] = string.format("s%d:%s:%d/sh%d", i, SPECIES[monSpecies(i)] or
        string.format("$%04X", monSpecies(i)), monHp(i), monShields(i))
    end
  end
  return table.concat(m, " ")
end
local function formationName()
  local n = {}
  for i = 0, 5 do
    local w = H.readWord(0x57C0 + i * 2)
    if w ~= 0xFFFF and w ~= 0 then n[#n + 1] = SPECIES[w] or string.format("$%04X", w) end
  end
  return #n > 0 and table.concat(n, "+") or "none"
end
local function fieldParty(tag)
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    local base = 0x1600 + 37 * c
    out[#out + 1] = string.format("c%d=L%d:%d/%d:%dmp:%s%s", c, charLevel(c),
      H.readWord(base + 0x09), H.readWord(base + 0x0B) & 0x3FFF,
      H.readWord(base + 0x0D), isBack(c) and "back" or "front",
      (H.readByte(base + 0x14) & 0x80) ~= 0 and ":DEAD" or "")
  end
  return string.format("[m269lab %s] %s tonic=%d fenix=%d", tag,
    table.concat(out, " "), H.invCountOf(TONIC), H.invCountOf(FENIX_DOWN))
end

-- ------------------------------------------------------ the observers --
-- Read-only CPU exec callbacks (lab_zozo_street.lua's, verbatim).  Events
-- are buffered and flushed from the frame loop.  ExecCmd@battle_code runs
-- with X = the acting entity's offset (party $00..$06, monsters $08..$12),
-- $b5/$b6 the command/attack after spell folding, $b8 the target word.
-- _writedamage walks $33d0 + entity*2 (the 14-bit damage word) before
-- ApplyDmg clamps it to HP: a kill's true roll.  SaveForMimic runs right
-- after the command resolves.
local pending, events = {}, {}
local lastSeed = nil
local monsterHits = {}       -- { atk, kills, tgt }
local partyActs = {}         -- { char, cmd, atk }
local maxHit, maxHitWho, maxHitAtk = 0, nil, nil
local maxRaw, maxRawAtk = 0, nil
local flareRolls = {}        -- every raw L4 Flare word seen, per target
local function hookObservers()
  emu.addMemoryCallback(function()
    lastSeed = emu.getState()["cpu.a"] & 0xFF
  end, emu.callbackType.exec, H.seedStoreAddr(), H.seedStoreAddr())
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x % 2 ~= 0 or x > 0x12 then return end
    pending[x] = { frame = H.frame, cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
      tgt = H.readWord(0xB8), hp = partyHp(),
      mhp = { monHp(0), monHp(1), monHp(2), monHp(3), monHp(4), monHp(5) },
      msh = { monShields(0), monShields(1), monShields(2), monShields(3), monShields(4), monShields(5) } }
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"), H.sym("ExecCmd@battle_code"))
  emu.addMemoryCallback(function()
    local mx = nil
    for x = 8, 0x12, 2 do if pending[x] then mx = x end end
    if not mx then return end
    local raw = {}
    for e = 1, 4 do
      local w = H.readWord(0x33D0 + (e - 1) * 2)
      raw[e] = (w == 0xFFFF) and 0x3FFF or (w & 0x3FFF)
    end
    pending[mx].raw = raw
  end, emu.callbackType.exec, H.sym("_writedamage"), H.sym("_writedamage"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    local p = pending[x]
    if not p then return end
    pending[x] = nil
    local after = partyHp()
    if x >= 8 then
      local slot = (x - 8) // 2
      local dmg, kills, raw = {}, 0, {}
      for e = 1, 4 do
        dmg[e] = p.hp[e] - after[e]
        raw[e] = (p.raw and p.raw[e]) or 0x3FFF
        if p.hp[e] > 0 and after[e] == 0 then kills = kills + 1 end
        if dmg[e] > maxHit then maxHit, maxHitWho, maxHitAtk = dmg[e], slotChar(e - 1), p.atk end
        if raw[e] ~= 0x3FFF and dmg[e] > 0 and raw[e] > maxRaw then maxRaw, maxRawAtk = raw[e], p.atk end
        if p.atk == 0x95 and raw[e] ~= 0x3FFF then
          flareRolls[#flareRolls + 1] = string.format("c%d:%d", slotChar(e - 1), raw[e])
        end
      end
      -- the AI's "attack ... NOTHING" third resolves through ExecCmd as
      -- command $12 with a stale $b6 (measured: atk read Bolt / $E8 / $F0,
      -- whatever the last party action left, always tgt=0000, no damage
      -- words); label it rather than the leftover
      local atk = (p.cmd == 0x12) and 0x1FE or p.atk
      monsterHits[#monsterHits + 1] = { atk = atk, kills = kills, tgt = p.tgt }
      events[#events + 1] = string.format(
        "[hit] f%d %s(s%d) cmd=%02X atk=%s tgt=%04X dmg=%d,%d,%d,%d raw=%d,%d,%d,%d kills=%d party=%s",
        H.frame, SPECIES[monSpecies(slot)] or "?", slot, p.cmd, atkName(atk), p.tgt,
        dmg[1], dmg[2], dmg[3], dmg[4], raw[1], raw[2], raw[3], raw[4], kills, table.concat(after, ","))
      -- the pips each victim fell holding (#175): OT6_BP_CLASS $3e9c + e*2
      for e = 1, 4 do
        if p.hp[e] > 0 and after[e] == 0 then
          events[#events + 1] = string.format(
            "[death] f%d entity %d c%d from %d by %s(s%d) %s bp=%d party_bp=%d,%d,%d,%d",
            H.frame, e - 1, slotChar(e - 1), p.hp[e], SPECIES[monSpecies(slot)] or "?", slot,
            atkName(atk), H.readByte(0x3E9C + (e - 1) * 2),
            H.readByte(0x3E9C), H.readByte(0x3E9E), H.readByte(0x3EA0), H.readByte(0x3EA2))
        end
      end
    else
      local slot = x // 2
      local md = {}
      for i = 0, 5 do
        if monPresent(i) or p.mhp[i + 1] > 0 then
          md[#md + 1] = string.format("s%d:%d->%d/sh%d->%d", i, p.mhp[i + 1], monHp(i),
            p.msh[i + 1], monShields(i))
        end
      end
      -- a dead (or otherwise skipped) member's turn resolves the same way
      -- as the monsters' Nothing: command $12, stale $b6, tgt=0000
      local atk = (p.cmd == 0x12) and 0x1FE or p.atk
      partyActs[#partyActs + 1] = { char = slotChar(slot), cmd = p.cmd, atk = atk }
      events[#events + 1] = string.format(
        "[act] f%d c%d(slot%d) cmd=%02X atk=%s tgt=%04X mon=%s party=%s",
        H.frame, slotChar(slot), slot, p.cmd, atkName(atk), p.tgt,
        table.concat(md, " "), table.concat(after, ","))
    end
  end, emu.callbackType.exec, H.sym("SaveForMimic"), H.sym("SaveForMimic"))
end
local function flushEvents()
  for _, e in ipairs(events) do H.log("[m269lab] " .. e) end
  events = {}
end

-- ------------------------------------------------------ the policies --
-- navTo's "tactical" driver as gen_n024_entry's first leg builds it
-- (lib/ot6_field.lua navTo: tactical, boost, items, healPercent 55, and
-- every other option nil): the control.
local function controlOpts()
  return { tactical = true, boost = true, items = true, healPercent = 55 }
end
local driverOpts = controlOpts()
local preCare = false
local rowSpec = nil
if POLICY == "control" then
  -- as shipped
elseif POLICY == "cared" then
  preCare = true
elseif POLICY == "allback" then
  preCare = true
  rowSpec = { [LOCKE] = true, [EDGAR] = true, [SABIN] = true, [CELES] = true }
elseif POLICY == "breakfirst" then
  preCare = true
  driverOpts.bank = 0
  -- one Trapper at a time: formation $076 puts them in slots 2,3,4; the
  -- $7B7E mask bits follow the on-screen layout, and for a three-body row
  -- the driver's own doc says slot n <-> bit n
  driverOpts.focus = { { slot = 2, mask = 0x04 }, { slot = 3, mask = 0x08 }, { slot = 4, mask = 0x10 },
                       { slot = 0, mask = 0x01 }, { slot = 1, mask = 0x02 }, { slot = 5, mask = 0x20 } }
elseif POLICY == "boostfight" then
  preCare = true
  driverOpts.bank = 0
  driverOpts.tactical = false
else
  error("unknown POLICY " .. POLICY, 0)
end

local F = H.newFightDriver("m269lab " .. POLICY, driverOpts)

-- ------------------------------------------------------ the attempt --
local phaseSum, phasePrev = 0, nil
local walkLegs = 0
local careFenixPre = 0
local fenixAtStart = 0
local wipeN, offN = 0, 0
local battles = {}           -- every fight this run (walk mode has several)
local battle = nil

local function newBattle()
  return { started = nil, over = nil, wiped = false, form = nil, seed = nil,
           fenix0 = 0, deaths = 0, maxDead = 0, careFenix = 0, careTonic = 0,
           hits0 = #monsterHits, acts0 = #partyActs }
end

local function heldUntilPhase()
  return H.driveUntil(function()
    local ph = H.readByte(0x021E)
    if phasePrev ~= nil then
      local d = ph - phasePrev
      if d < 0 then d = d + 60 end
      phaseSum = phaseSum + d
    end
    phasePrev = ph
    return phaseSum >= SEED
  end, 60 * 70 + 200, { H.call(function() H.setPad({}) end) }, "seed hold")
end

local function settled()
  return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
     and not H.battleLoadStarted() and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
end

-- gen_n024_entry's leg: navTo(42,12) toward the map-271 door, stopped at
-- the first battle load (or the door)
local function walkLeg()
  return H.navTo(42, 12, {
    maxFrames = 25000, playBattles = "tactical", care = false,
    arrive = function() return H.battleLoadStarted() or map() == 271 end,
  })
end

local function fightStep()
  return H.driveUntil(function()
    if battle.over then return true end
    if H.battleLoadStarted() then
      offN = 0
      if battle.started == nil then
        battle.started = H.frame
        battle.seed = lastSeed
        battle.fenix0 = H.invCountOf(FENIX_DOWN)
      end
      if battle.form == nil and formationName() ~= "none" then
        battle.form = formationName()
        local lv, rows = {}, {}
        for s = 0, 3 do
          local c = slotChar(s)
          lv[#lv + 1] = string.format("c%d=L%d", c, charLevel(c))
          rows[#rows + 1] = string.format("c%d=%s", c, isBack(c) and "back" or "front")
        end
        H.log(string.format("[m269lab] battle up f%d (+%d) form=%s bseed=%s phase=%d at=(%d,%d) levels=%s rows=%s party=%s vs %s",
          H.frame, H.frame - battle.started, battle.form, battle.seed and string.format("%02X", battle.seed) or "?",
          H.readByte(0x021E), H.fieldX(), H.fieldY(), table.concat(lv, " "), table.concat(rows, " "), partyLine(), monsterLine()))
      end
      battle.party = partyLine()
      local dead, any = 0, false
      for e = 0, 3 do
        if H.readWord(BCMAXHP + e * 2) > 0 then
          any = true
          if H.readWord(BCHP + e * 2) == 0 then dead = dead + 1 end
        end
      end
      if dead > battle.maxDead then battle.maxDead = dead end
      battle.lastDead = dead
      if any and dead == 4 then wipeN = wipeN + 1 else wipeN = 0 end
      if wipeN >= 120 then
        battle.wiped = true
        battle.over = H.frame
        H.log(string.format("[m269lab] WIPED f%d (%d frames in) party=%s vs %s",
          H.frame, H.frame - battle.started, partyLine(), monsterLine()))
        return true
      end
      if (H.frame - battle.started) % 300 == 0 then
        H.log(string.format("[m269lab] f+%d party=%s vs %s", H.frame - battle.started,
          partyLine(), monsterLine()))
      end
      return false
    end
    if battle.started ~= nil then
      offN = offN + 1
      if offN >= 30 then
        battle.over = H.frame
        F.idle()
        local dead = battle.lastDead or 0
        battle.deaths = dead
        H.log(string.format("[m269lab] battle over f%d (%d frames) party=%s deaths=%d maxdead=%d fenix %d->%d",
          H.frame, battle.over - battle.started, battle.party or "-", dead, battle.maxDead,
          battle.fenix0, H.invCountOf(FENIX_DOWN)))
        return true
      end
    end
    return false
  end, 40000, {
    H.call(function()
      flushEvents()
      if H.battleLoadStarted() then F.frame() else H.setPad({}) end
    end),
  }, "the fight")
end

-- navTo's own between-battles care stop, exactly as the generator's leg
-- runs it after a mid-walk battle (ot6_field.lua navTo: newCareDriver,
-- threshold 0.65, Tonics only)
local function careStep()
  local careD = nil
  return H.driveUntil(function()
    if careD == nil then careD = H.newCareDriver({ threshold = 0.65, tag = "care after battle (m269lab navTo)" }) end
    careD.frame()
    return careD.done()
  end, 6000, { H.call(function() end) }, "care after the fight")
end

local function summarize(b)
  local acts, hits, flares = {}, {}, 0
  for i = b.acts0 + 1, #partyActs do
    local a = partyActs[i]
    acts[#acts + 1] = string.format("c%d:%s", a.char, atkName(a.atk))
  end
  for i = b.hits0 + 1, #monsterHits do
    local h = monsterHits[i]
    hits[#hits + 1] = atkName(h.atk) .. (h.kills > 0 and ("!" .. h.kills) or "")
    if h.atk == 0x95 then flares = flares + 1 end
  end
  return acts, hits, flares
end

local function result(note)
  local b = battle or newBattle()
  local acts, hits, flares = summarize(b)
  H.log(string.format(
    "[result] policy=%s seed=%d mode=%s form=%s bseed=%s frames=%s deaths=%d maxdead=%d wiped=%s " ..
    "fenix_pre=%d fenix_battle=%d fenix_care=%d maxhit=%d(c%s,%s) maxraw=%d(%s) flares=%d flare_rolls=%s " ..
    "hp_end=%s legs=%d monhits=%s acts=%s note=%s",
    POLICY, SEED, MODE, b.form or "none",
    b.seed and string.format("%02X", b.seed) or "-",
    b.started and tostring((b.over or H.frame) - b.started) or "-",
    b.deaths, b.maxDead, tostring(b.wiped),
    careFenixPre,
    b.started and (b.fenix0 - H.invCountOf(FENIX_DOWN) - b.careFenix) or 0, b.careFenix,
    maxHit, tostring(maxHitWho), maxHitAtk and atkName(maxHitAtk) or "-",
    maxRaw, maxRawAtk and atkName(maxRawAtk) or "-",
    flares, #flareRolls > 0 and table.concat(flareRolls, ",") or "-",
    b.party or "-", walkLegs, table.concat(hits, ","), table.concat(acts, ","), note or ""))
end

local function walkBattleLine(n)
  local b = battle
  local acts, hits, flares = summarize(b)
  H.log(string.format(
    "[walkbattle] policy=%s seed=%d n=%d form=%s bseed=%s at=%s frames=%s deaths=%d maxdead=%d wiped=%s " ..
    "fenix_battle=%d fenix_care=%d flares=%d monhits=%s acts=%s hp_end=%s",
    POLICY, SEED, n, b.form or "none", b.seed and string.format("%02X", b.seed) or "-",
    b.at or "?", b.started and tostring((b.over or H.frame) - b.started) or "-",
    b.deaths, b.maxDead, tostring(b.wiped),
    b.started and (b.fenix0 - H.invCountOf(FENIX_DOWN) - b.careFenix) or 0, b.careFenix,
    flares, table.concat(hits, ","), table.concat(acts, ","), b.party or "-"))
end

local function afterFight()
  return H.cond(function() return not battle.wiped end, {
    H.waitUntilSoft(settled, 1800, "settled after the fight", 5),
    H.waitFrames(90),
    H.call(function()
      battle.careFenix = H.invCountOf(FENIX_DOWN)
      battle.careTonic = H.invCountOf(TONIC)
    end),
    H.cond(settled, { careStep() }, {
      H.logStep("[m269lab] care SKIPPED -- not settled after the fight"),
    }),
    H.call(function()
      battle.careFenix = battle.careFenix - H.invCountOf(FENIX_DOWN)
      battle.careTonic = battle.careTonic - H.invCountOf(TONIC)
      H.log(fieldParty("after care"))
    end),
  }, {})
end

-- fight mode: the generator's leg until the first random, fought once
local fightMode = {}
do
  local legs = {}
  for n = 1, 3 do
    legs[#legs + 1] = H.cond(function() return battle.started == nil and not H.battleLoadStarted() and map() == 269 end, {
      H.call(function() walkLegs = walkLegs + 1 end),
      walkLeg(),
    }, {})
  end
  fightMode = {
    H.call(function() battle = newBattle() end),
    H.cond(function() return true end, legs),
    H.cond(function() return battle.started ~= nil or H.battleLoadStarted() end, {
      H.call(function() battle.at = string.format("(%d,%d)", H.fieldX(), H.fieldY()) end),
      fightStep(),
      H.call(flushEvents),
      afterFight(),
      H.call(function() result(battle.wiped and "wiped" or "fought") end),
    }, {
      H.call(function() result("no battle rolled in " .. walkLegs .. " legs") end),
    }),
  }
end

-- walk mode: the whole leg, every random fought, until map 271
local walkMode = {}
do
  local wipedRun = false
  local legs = {}
  for n = 1, 14 do
    legs[#legs + 1] = H.cond(function() return map() == 269 and not wipedRun end, {
      H.call(function()
        battle = newBattle()
        walkLegs = walkLegs + 1
      end),
      walkLeg(),
      H.cond(function() return H.battleLoadStarted() end, {
        H.call(function() battle.at = string.format("(%d,%d)", H.fieldX(), H.fieldY()) end),
        fightStep(),
        H.call(flushEvents),
        afterFight(),
        H.call(function()
          battles[#battles + 1] = battle
          walkBattleLine(#battles)
          if battle.wiped then wipedRun = true end
        end),
      }, {}),
    }, {})
  end
  walkMode = {
    H.cond(function() return true end, legs),
    H.call(function()
      local deaths, fc, frames, flares, forms = 0, 0, 0, 0, {}
      for _, b in ipairs(battles) do
        deaths = deaths + b.deaths
        fc = fc + b.careFenix
        frames = frames + ((b.over or H.frame) - (b.started or H.frame))
        local _, _, fl = summarize(b)
        flares = flares + fl
        forms[#forms + 1] = b.form or "?"
      end
      local lv = {}
      for _, c in ipairs(H.partyMembers()) do lv[#lv + 1] = string.format("c%d=L%d:%d", c, charLevel(c), charXp(c)) end
      H.log(string.format(
        "[walkresult] policy=%s seed=%d reached=%s map=%d at=(%d,%d) battles=%d forms=%s deaths=%d wiped=%s " ..
        "fenix_pre=%d fenix_total=%d fenix_care=%d battle_frames=%d flares=%d maxhit=%d(c%s,%s) maxraw=%d(%s) frames=%d tonic=%d fenix=%d levels=%s",
        POLICY, SEED, tostring(map() == 271), map(), H.fieldX(), H.fieldY(), #battles,
        table.concat(forms, ";"), deaths, tostring(wipedRun),
        careFenixPre, fenixAtStart - H.invCountOf(FENIX_DOWN) - careFenixPre, fc, frames, flares,
        maxHit, tostring(maxHitWho), maxHitAtk and atkName(maxHitAtk) or "-",
        maxRaw, maxRawAtk and atkName(maxRawAtk) or "-",
        H.frame, H.invCountOf(TONIC), H.invCountOf(FENIX_DOWN), table.concat(lv, " ")))
    end),
  }
end

H.run({ maxFrames = 200000, allowGameOver = true }, {
  -- compose.py embeds savestates by scanning loadState string LITERALS
  H.loadState("build/states/m269lab_pre.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    hookObservers()
    H.assertEq(map(), 269, "the lab fixture is on map 269")
    H.assertEq(H.fieldX() == 44 and H.fieldY() == 53, true, "the lab fixture is the (44,53) landing")
    H.log(string.format("[m269lab] POLICY=%s SEED=%d MODE=%s f%d phase=%d", POLICY, SEED, MODE,
      H.frame, H.readByte(0x021E)))
    H.log(fieldParty("at the landing"))
  end),
  H.cond(function() return preCare end, {
    H.call(function() careFenixPre = H.invCountOf(FENIX_DOWN) end),
    H.fieldCare({ tag = "m269lab care at the landing", threshold = 0.95 }),
    H.call(function()
      careFenixPre = careFenixPre - H.invCountOf(FENIX_DOWN)
      H.log(fieldParty("after the landing care"))
    end),
  }, {}),
  H.cond(function() return rowSpec ~= nil end, {
    H.setRows(rowSpec or {}, { tag = "m269lab rows " .. POLICY }),
    H.call(function() H.log(fieldParty("rows set")) end),
  }, {}),
  H.waitUntil(settled, 1200, "settled before the seed hold", 5),
  heldUntilPhase(),
  H.call(function()
    fenixAtStart = H.invCountOf(FENIX_DOWN) + careFenixPre
    H.log(string.format("[m269lab] seed hold done: phase=%d after %d phases f%d",
      H.readByte(0x021E), phaseSum, H.frame))
  end),
  H.cond(function() return MODE == "walk" end, walkMode, fightMode),
})
