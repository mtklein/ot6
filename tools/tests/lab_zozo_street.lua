-- @manual
-- lab_zozo_street.lua -- the Zozo street random lab (issue #155): the
-- SlamDancer that one-shot EDGAR for 371 in the v0.16 qualification
-- (build/states/dadaluma_entry.log, map 225, "partyhp=353,349,0,407
-- roundcost=0,0,371,0"), and the care stop's Fenix Down after it.
--
-- THE FIGHT, DECODED (monster_prop.dat / ai_script.asm / ot6_hud.asm)
--
--   map 225 (the crane maze interiors) rolls encounter group 77
--   (tools/audit_encounters.py 225):
--     31.25%  $069  SlamDancer($052) x1        <- the fight in the log
--     31.25%  $06b  Harvester($04e) x1
--     31.25%  $06c  Harvester x2 + SlamDancer x1   (pincer possible)
--      6.25%  $06a  SlamDancer x1 + Gabbldegak($0df) x3
--   The log's single monster read "monhp=s0:392/sh2" at full HP, and 392
--   is SlamDancer's HP exactly (Harvester is 428).
--
--   $052 SlamDancer  L15  HP 392  MP 120  speed 35  atk 13  def 115
--                    mdef 145  mpow 10   weak POISON ($08)  absorb none
--                    shields 2, NO class key (Ot6ShieldTbl, ot6_hud.asm
--                    :1671, the first-match row; the second $0052 row at
--                    :1854 with SLASH|PIERCE is dead code -- Ot6SeedShields
--                    scans from the top and stops at the first hit,
--                    ot6_break.asm:74-83)
--                    Every stat is byte-identical to the vanilla ROM record.
--   AI (ai_script.asm:925 "slamdancer"):
--       if_one_monster_type            <- true in $069 (and $06b/$06c no)
--           attack FIRE_2, ICE_2, BOLT_2   (one of the three, every turn)
--       else Battle/Battle/Nothing, Battle/Battle/Special
--   So the solo formation casts a tier-2 elemental every turn.  Fire 2 /
--   Ice 2 / Bolt 2 are power 60/62/61 (magic_prop_en.dat), MAGIC: rows do
--   not apply.  EDGAR took the 371 in the BACK row ("[zozo rows] c1=front
--   c4=back c5=back c6=back"), at L15 371/398 HP, wearing MithrilBlade /
--   Buckler / Leather Hat / LeatherArmor / Star Pendant.  A single-target
--   tier-2 cast; not a critical, not a row matter, not a boosted enemy
--   turn (monsters bank no BP, ot6_boost.asm:156).
--
--   $04e Harvester   L16 HP 428 speed 50 atk 13 mpow 10, weak poison, 2 sh
--   $053 HadesGigas  L16 HP 1200 speed 40 atk 18 mpow 5, weak poison, 2 sh
--   $0df Gabbldegak  L15 HP 350 speed 30 atk 13 mpow 10, weak poison, 2 sh
--
-- THE LAB
--
--   Fixture: build/states/zozolab_pre.mss -- the stair-room landing on map
--   225 at (59,34), captured by build/zozolab/gen_bake.lua, which is
--   gen_zozo4_dadaluma.lua with a saveState inserted after
--   climbCare("after P11a") (the exact tile the qualification stepped
--   off).  Reached from zozo_arrival by the generator's own play: care,
--   the equip stop, rows, three doors and their fights under the control
--   driver.  Ancestry is the bake log, build/zozolab/bake.log.
--
--   Per attempt: load the fixture, apply the policy's FIELD setup (rows,
--   a menu drive), hold the pad neutral until wGameTimeFrames ($021e,
--   period 60) has advanced SEED phases (the battle seed is $021e*4,
--   lib/ot6.lua "battle rng seed"), then walk (59,34)->(52,30) and back
--   until a random rolls.  Whatever rolls is fought under the policy and
--   logged.  After the fight, the generator's own care stop (fieldCare
--   0.9) runs, so a Fenix spent there is counted the way audit_fenix
--   counts it.
--
--   What the seed can and cannot vary (field/battle.asm CheckBattleSub):
--   the encounter check draws RNGTbl[$1fa1] once per STEP and the
--   formation slot draws RNGTbl[$1fa2] once per BATTLE; both counters
--   live in the snapshot and no idle frame moves them.  So from this
--   fixture the first step always rolls, and always rolls formation $069
--   (SlamDancer x1) -- the formation under study, but not a formation
--   spread; other formations are covered by the whole-street runs
--   (zozolab_street.py).  The hold varies the BATTLE seed only, and the
--   hold-to-step latency is quantized to 4 frames (seeds 2/4, 6/8, 10/12,
--   14/16 drew identical battles), so the declared spread is seeds 0..56
--   step 4: 15 distinct battle seeds, the whole $021e cycle.  Policies
--   that change nothing on the field (control, breakfirst, runic) share
--   the exact pre-battle state per seed -- a paired A/B; the row policies
--   spend a menu drive first and so draw their own 15.
--
--   POLICY (the one variable, @POLICY@ substituted by zozolab_batch.sh):
--     control     gen_zozo4_dadaluma's encounters() driver, rows as the
--                 route sets them (LOCKE front, the other three back)
--     allback     the same driver, LOCKE also moved to the back row
--     allfront    the same driver, everyone in the front row (the
--                 contrast: if rows mattered, this is the worst case)
--     breakfirst  bank = 0: every BP is spent as soon as it exists, so
--                 EDGAR's first Bio Blaster (the only key the party
--                 holds: poison, all enemies) goes out boosted on turn 1
--                 and everyone else boost-Fights
--     runic       CELES answers the command menu with RUNIC every turn
--                 (the tier-2 casts are magic; Runic eats them and pays
--                 her MP), LOCKE runs the item medic line since a Cure
--                 would be Runic'd too; otherwise the control driver
--
--   Privileged-information label: none of these policies reads hidden
--   state.  The poison key is what the route already ships (the Bio
--   Blaster is in the bag for this town; the generator's header says
--   why), and Runic is CELES's own command against an enemy that visibly
--   casts.  The lab's CPU observers (ExecCmd / SaveForMimic exec
--   callbacks, the seed store) are read-only measurement.
--
--   Reads and pad presses only.  A wipe is the measurement, not a retry
--   (allowGameOver).  One machine-readable [result] line per run.
local H = dofile("tools/tests/lib/ot6.lua")

local POLICY  = "@POLICY@"
local SEED    = tonumber("@SEED@") or 0
if POLICY:find("@") then POLICY = "control" end

local LOCKE, EDGAR, SABIN, CELES = 1, 4, 5, 6
local BIO_BLASTER = H.BIO_BLASTER
local FENIX_DOWN = 0xF0
local CMD_RUNIC = 0x0B
local SLAMDANCER, HARVESTER, HADESGIGAS, GABBLDEGAK = 0x0052, 0x004E, 0x0053, 0x00DF
local ZOZO = { SLAMDANCER, HARVESTER, HADESGIGAS, GABBLDEGAK }
local SPECIES = { [0x0052] = "SlamDancer", [0x004E] = "Harvester",
                  [0x0053] = "HadesGigas", [0x00DF] = "Gabbldegak" }
local ATTACK = { [0x00] = "Fire", [0x01] = "Ice", [0x02] = "Bolt",
                 [0x05] = "Fire2", [0x06] = "Ice2", [0x07] = "Bolt2",
                 [0x7D] = "BioBlaster", [0x5D] = "Pummel", [0x2D] = "Cure",
                 [0xA4] = "BioBlaster", [0xFF] = "Fight",
                 [0xEE] = "Battle", [0xEF] = "Special" }
local function atkName(id)
  return ATTACK[id] or string.format("$%02X", id)
end

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local ST_CMD, ST_TGT = 0x05, 0x38
local BCHP, BCMAXHP = 0x3BF4, 0x3C1C
local function map() return H.mapId() & 0x1ff end
local function charLevel(c) return H.readByte(0x1600 + 37 * c + 8) end
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

-- ------------------------------------------------------ the observers --
-- Read-only CPU exec callbacks.  Events are buffered and flushed from the
-- frame loop (prints inside a CPU callback interleave badly with the live
-- stream).  ExecCmd@battle_code runs with X = the acting entity's offset
-- (party $00..$06, monsters $08..$12), $b5/$b6 the command/attack after
-- spell folding, $b8 the target word (lib/ot6.lua's recovery trace
-- documents the same three).  SaveForMimic runs right after the command
-- resolves, so party HP before/after is the damage the action did.
local pending, events = {}, {}
local lastSeed = nil
local monsterHits = {}       -- { atk, targets, dmg = {..}, kills }
local partyActs = {}         -- { char, cmd, atk }
local maxHit, maxHitWho, maxHitAtk = 0, nil, nil
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
    local x = emu.getState()["cpu.x"] & 0xFFFF
    local p = pending[x]
    if not p then return end
    pending[x] = nil
    local after = partyHp()
    if x >= 8 then
      local slot = (x - 8) // 2
      local dmg, kills = {}, 0
      for e = 1, 4 do
        dmg[e] = p.hp[e] - after[e]
        if p.hp[e] > 0 and after[e] == 0 then kills = kills + 1 end
        if dmg[e] > maxHit then maxHit, maxHitWho, maxHitAtk = dmg[e], slotChar(e - 1), p.atk end
      end
      monsterHits[#monsterHits + 1] = { atk = p.atk, kills = kills }
      events[#events + 1] = string.format(
        "[hit] f%d %s(s%d) cmd=%02X atk=%s tgt=%04X dmg=%d,%d,%d,%d kills=%d party=%s",
        H.frame, SPECIES[monSpecies(slot)] or "?", slot, p.cmd, atkName(p.atk), p.tgt,
        dmg[1], dmg[2], dmg[3], dmg[4], kills, table.concat(after, ","))
    else
      local slot = x // 2
      local md = {}
      for i = 0, 5 do
        if monPresent(i) or p.mhp[i + 1] > 0 then
          md[#md + 1] = string.format("s%d:%d->%d/sh%d->%d", i, p.mhp[i + 1], monHp(i),
            p.msh[i + 1], monShields(i))
        end
      end
      partyActs[#partyActs + 1] = { char = slotChar(slot), cmd = p.cmd, atk = p.atk }
      events[#events + 1] = string.format(
        "[act] f%d c%d(slot%d) cmd=%02X atk=%s tgt=%04X mon=%s party=%s",
        H.frame, slotChar(slot), slot, p.cmd, atkName(p.atk), p.tgt,
        table.concat(md, " "), table.concat(after, ","))
    end
  end, emu.callbackType.exec, H.sym("SaveForMimic"), H.sym("SaveForMimic"))
end
local function flushEvents()
  for _, e in ipairs(events) do H.log("[zozolab] " .. e) end
  events = {}
end

-- ------------------------------------------------------ the policies --
local FOCUS = {
  { slot = 0, mask = 0x01 }, { slot = 1, mask = 0x02 },
  { slot = 2, mask = 0x04 }, { slot = 3, mask = 0x08 },
  { slot = 4, mask = 0x10 }, { slot = 5, mask = 0x20 },
}
-- gen_zozo4_dadaluma.lua encounters(): the control driver, verbatim
local function controlOpts()
  return { tactical = true, boost = true, bank = 3, items = true, healPercent = 60,
           healer = CELES, cadence = 12, tool = BIO_BLASTER, focus = FOCUS }
end
local driverOpts = controlOpts()
local rowSpec = nil
if POLICY == "allback" then
  rowSpec = { [LOCKE] = true, [EDGAR] = true, [SABIN] = true, [CELES] = true }
elseif POLICY == "allfront" then
  rowSpec = { [LOCKE] = false, [EDGAR] = false, [SABIN] = false, [CELES] = false }
elseif POLICY == "breakfirst" then
  driverOpts.bank = 0
elseif POLICY == "runic" then
  driverOpts.healer = LOCKE
  driverOpts.cure = false
elseif POLICY ~= "control" then
  error("unknown POLICY " .. POLICY, 0)
end

local F = H.newFightDriver("zozolab " .. POLICY, driverOpts)
local runicTick, runicSaid = 0, false
local function runicRow(actor)
  for r = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + r * 3) == CMD_RUNIC then return r end
  end
  return nil
end
-- CELES's turns: steer the command cursor to RUNIC and confirm (Runic has
-- no target window).  Every other frame belongs to the control driver,
-- which never sees CELES's window and so never plans for her.
local function policyFrame()
  if POLICY == "runic" and H.readByte(MENU) ~= 0 then
    local actor = H.readByte(ACTOR) & 3
    if slotChar(actor) == CELES then
      runicTick = runicTick + 1
      local st = H.readByte(MSTATE)
      local ph = runicTick % 12
      if runicTick % 60 == 1 then
        H.log(string.format("[zozolab runic-diag] f%d menu=%02X actor=%d st=%02X cur=%d cmds=%02X,%02X,%02X,%02X flags=%02X,%02X,%02X,%02X",
          H.frame, H.readByte(MENU), actor, st, H.readByte(CMDROW + actor) & 3,
          H.readByte(CMDTBL + actor * 12), H.readByte(CMDTBL + actor * 12 + 3),
          H.readByte(CMDTBL + actor * 12 + 6), H.readByte(CMDTBL + actor * 12 + 9),
          H.readByte(CMDTBL + actor * 12 + 1), H.readByte(CMDTBL + actor * 12 + 4),
          H.readByte(CMDTBL + actor * 12 + 7), H.readByte(CMDTBL + actor * 12 + 10)))
      end
      if st == ST_CMD then
        local row = runicRow(actor)
        if row ~= nil then
          local cur = H.readByte(CMDROW + actor) & 3
          local btn = cur == row and "a" or (cur < row and "down" or "up")
          if not runicSaid and btn == "a" then
            runicSaid = true
            H.log(string.format("[zozolab] CELES (slot %d) -> RUNIC on row %d", actor, row))
          end
          H.setPad(ph < 4 and { [btn] = true } or {})
          return
        end
      elseif st == ST_TGT then
        -- Runic opens a target window here (measured: state $38 after the
        -- confirm); take the default target
        H.setPad(ph < 4 and { a = true } or {})
        return
      elseif st ~= 0x01 then
        -- some other window opened on her turn: back out
        H.setPad(ph < 4 and { b = true } or {})
        return
      end
    else
      runicSaid = false
    end
  end
  F.frame()
end

-- ------------------------------------------------------ the attempt --
local phaseSum, phasePrev = 0, nil
local walkLegs = 0
local battle = { started = nil, over = nil, wiped = false, form = nil, seed = nil,
                 fenix0 = 0, deaths = 0, maxDead = 0 }
local careFenix = 0
local wipeN, offN = 0, 0

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

local function walkLeg(tx, ty)
  return H.navTo(tx, ty, {
    maxFrames = 6000, playBattles = "tactical", spare = ZOZO, care = false,
    tool = BIO_BLASTER, healer = CELES, bank = 3, healPercent = 60,
    arrive = function() return H.battleLoadStarted() end,
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
        H.log(string.format("[zozolab] battle up f%d (+%d) form=%s bseed=%s phase=%d levels=%s rows=%s party=%s vs %s",
          H.frame, H.frame - battle.started, battle.form, battle.seed and string.format("%02X", battle.seed) or "?",
          H.readByte(0x021E), table.concat(lv, " "), table.concat(rows, " "), partyLine(), monsterLine()))
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
        H.log(string.format("[zozolab] WIPED f%d (%d frames in) party=%s vs %s",
          H.frame, H.frame - battle.started, partyLine(), monsterLine()))
        return true
      end
      if (H.frame - battle.started) % 300 == 0 then
        H.log(string.format("[zozolab] f+%d party=%s vs %s", H.frame - battle.started,
          partyLine(), monsterLine()))
      end
      return false
    end
    if battle.started ~= nil then
      offN = offN + 1
      if offN >= 30 then
        battle.over = H.frame
        F.idle()
        -- battle RAM is torn down by now; the last in-battle sample counts
        local dead = battle.lastDead or 0
        battle.deaths = dead
        H.log(string.format("[zozolab] battle over f%d (%d frames) party=%s deaths=%d maxdead=%d fenix %d->%d",
          H.frame, battle.over - battle.started, battle.party or "-", dead, battle.maxDead,
          battle.fenix0, H.invCountOf(FENIX_DOWN)))
        return true
      end
    end
    return false
  end, 30000, {
    H.call(function()
      flushEvents()
      if H.battleLoadStarted() then policyFrame() else H.setPad({}) end
    end),
  }, "the fight")
end

local function settled()
  return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
     and not H.battleLoadStarted() and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
end

local function result(note)
  local acts = {}
  for _, a in ipairs(partyActs) do acts[#acts + 1] = string.format("c%d:%s", a.char, atkName(a.atk)) end
  local hits = {}
  for _, h in ipairs(monsterHits) do hits[#hits + 1] = atkName(h.atk) .. (h.kills > 0 and ("!" .. h.kills) or "") end
  H.log(string.format(
    "[result] policy=%s seed=%d form=%s bseed=%s frames=%s deaths=%d maxdead=%d wiped=%s " ..
    "fenix_battle=%d fenix_care=%d maxhit=%d(c%s,%s) hp_end=%s legs=%d monhits=%s acts=%s note=%s",
    POLICY, SEED, battle.form or "none",
    battle.seed and string.format("%02X", battle.seed) or "-",
    battle.started and tostring((battle.over or H.frame) - battle.started) or "-",
    battle.deaths, battle.maxDead, tostring(battle.wiped),
    battle.started and (battle.fenix0 - H.invCountOf(FENIX_DOWN) - careFenix) or 0, careFenix,
    maxHit, tostring(maxHitWho), maxHitAtk and atkName(maxHitAtk) or "-",
    battle.party or "-", walkLegs, table.concat(hits, ","), table.concat(acts, ","), note or ""))
end

local legs = {}
for n = 1, 8 do
  local tx, ty = (n % 2 == 1) and 52 or 59, (n % 2 == 1) and 30 or 34
  legs[#legs + 1] = H.cond(function() return battle.started == nil and not H.battleLoadStarted() end, {
    H.call(function() walkLegs = walkLegs + 1 end),
    walkLeg(tx, ty),
  }, {})
end

H.run({ maxFrames = 60000, allowGameOver = true }, {
  -- compose.py embeds savestates by scanning loadState string LITERALS,
  -- so the fixture is spelled out (FIXTURE only names it in the log line)
  H.loadState("build/states/zozolab_pre.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    hookObservers()
    H.assertEq(map(), 225, "the lab fixture is on map 225")
    H.assertEq(H.invCountOf(BIO_BLASTER) > 0, true, "the Bio Blaster is in the bag")
    local lv, rows = {}, {}
    for _, c in ipairs(H.partyMembers()) do
      lv[#lv + 1] = string.format("c%d=L%d", c, charLevel(c))
      rows[#rows + 1] = string.format("c%d=%s", c, isBack(c) and "back" or "front")
    end
    H.log(string.format("[zozolab] POLICY=%s SEED=%d at (%d,%d) map %d f%d phase=%d levels=%s rows=%s fenix=%d",
      POLICY, SEED, H.fieldX(), H.fieldY(), map(), H.frame, H.readByte(0x021E),
      table.concat(lv, " "), table.concat(rows, " "), H.invCountOf(FENIX_DOWN)))
  end),
  H.cond(function() return rowSpec ~= nil end, {
    H.setRows(rowSpec or {}, { tag = "zozolab rows " .. POLICY }),
    H.call(function()
      local rows = {}
      for _, c in ipairs(H.partyMembers()) do
        rows[#rows + 1] = string.format("c%d=%s", c, isBack(c) and "back" or "front")
      end
      H.log("[zozolab] rows set: " .. table.concat(rows, " "))
    end),
  }, {}),
  H.waitUntil(settled, 1200, "settled before the seed hold", 5),
  heldUntilPhase(),
  H.call(function()
    H.log(string.format("[zozolab] seed hold done: phase=%d after %d phases f%d",
      H.readByte(0x021E), phaseSum, H.frame))
  end),
  H.cond(function() return true end, legs),
  H.cond(function() return battle.started ~= nil or H.battleLoadStarted() end, {
    fightStep(),
    H.call(flushEvents),
    H.cond(function() return not battle.wiped end, {
      H.waitUntilSoft(settled, 1800, "settled after the fight", 5),
      H.waitFrames(90),
      H.call(function() careFenix = H.invCountOf(FENIX_DOWN) end),
      H.cond(settled, {
        H.fieldCare({ tag = "zozolab care after the fight", threshold = 0.9 }),
      }, {
        H.logStep("[zozolab] care SKIPPED -- not settled after the fight"),
      }),
      H.call(function() careFenix = careFenix - H.invCountOf(FENIX_DOWN) end),
    }, {}),
    H.call(function() result(battle.wiped and "wiped" or "fought") end),
  }, {
    H.call(function() result("no battle rolled in " .. walkLegs .. " legs") end),
  }),
})
