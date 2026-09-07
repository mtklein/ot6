-- @manual
-- lab_rizopas_template.lua -- the Rizopas strategy lab (#162), experiment
-- half.
--
-- Boots falls_prejump.mss (lab_rizopas_bake.lua: the post-arrival tile
-- (15,10) on map 156, SABIN+CYAN, the generator's own walk), walks onto
-- the jump row (13,11) the way gen_sabin_falls does, stands still IDLE
-- frames there to shift the battle-RNG phase ($021e, period 60; the seed
-- a battle draws is phase*4 -- lib/ot6.lua "battle rng seed"), holds up
-- and answers "Jump?" (battle 18: five Piranhas, then Rizopas surfaces in
-- slot 5 when the school's timer runs out), fights it under ONE declared
-- policy, and reports one machine-readable [result] line, PASSing either
-- way -- this file measures, it does not assert.  A win, a wipe and the
-- frame cap are all measurements.
--
-- The batch runner (rizopaslab_batch.sh) substitutes the @TOKEN@ defaults
-- below (sed).  Tokens:
--   POLICY  one of POLICIES below
--   IDLE    frames to stand still on the jump row (only IDLE mod 60 matters)
--
-- Per attempt the log carries, read-only: the seed InitBattle drew ($be at
-- the store) and $be at battle-up (the probe's reading, ten draws later),
-- every change to Rizopas's HP and shield count with the battle frame it
-- landed on, every party HP write, every party death and raise, every
-- ExecCmd/SaveForMimic pair for party and monsters alike (who did what,
-- with what, and what it did), the BP both carry when Rizopas surfaces,
-- and the live bag.
--
-- ---- Rizopas, decoded (not recalled) --------------------------------------
-- monster_prop.dat row $155 (32 bytes at +$2AA0, ROM $CF2AA0):
--   28 0e 64 00 00 6e af 03 07 03 27 00 00 00 00 00 0d e0 00 cd e6 09 00
--   80 00 04 ff 00 00 01 00 20
-- speed 40, attack 14, hit 100, evade 0, m.block 0, defense 110, m.def 175,
-- m.pow 3, HP 775, MP 39, level 13; absorb $80 WATER; null $00; weak $04
-- BOLT.  Byte 31 = $20: the special attack (LoadRageProp -> $322d;
-- battle_main.asm:8443-8480) is plain physical damage (bit 7 clear: can
-- miss; bit 6 clear: deals damage; $20-$20 = +0 to the multiplier).
-- Row bytes 28-31 = 00 01 00 20: status 3&4 word $0001 = the flying flag
-- (Float).  Ot6ShieldTbl (ot6_hud.asm:1601): 4 shields, class-weak
-- SLASH|BLUDG ($05).  No Ot6ElemAddTbl row; Ot6HpMulTbl ships $10 (1x),
-- so 775 HP is what the fight sees.
-- AI (ai_script.asm:7328-7337):
--   attack BATTLE, SPECIAL, MEGA_VOLT     ; one of three, at random
--   attack BATTLE, ICE, ICE
--   wait
--   attack EL_NINO, BATTLE, BATTLE
--   end                                  ; loops; boss_death on death
-- MEGA_VOLT $B8 (magic_prop_en.dat): bolt, power 20, single target, hit 150.
-- ICE $01: ice, power 22, single target.  EL_NINO $6F: WATER, power 61,
-- targeting $7E (the whole party), hit byte 0 (unmissable).  BATTLE $EE
-- and the SPECIAL: physical, attack 14.
-- Piranha $154 (ai_script.asm:7290-7326): HP 10, level 9, attack 13, weak
-- BOLT, 1 shield SLASH|BLUDG.  On a death: if the battle timer has passed
-- 60 and no other monster stands, hide the school and surface MONSTER_6
-- (Rizopas) from the WATER; otherwise restore two or three of the school
-- -- the wave is a fixed-length tax before the boss.
-- ----------------------------------------------------------------------------
-- ---- What SABIN and CYAN carry (lab_rizopas_bake.lua, at the falls) --------
-- CYAN  char 2, L14, 307/358 HP, 96/96 MP, Ashura $2B (katana: SLASH),
--       shield $5B, helm $69, armor $84, no relics; SwdTech known $07 =
--       Dispatch, Retort, Slash.
-- SABIN char 5, L14, 292/363 HP, 15/94 MP, MetalKnuckle $53 (claw: SLASH on
--       Fight; Pummel/Suplex bludgeon regardless), shield $5A, helm $69,
--       armor $86, relics $B1 $B5; Blitz known $07 = Pummel, AuraBolt, Suplex.
-- Bag: Tonic 91, Potion 2, Fenix Down 15.
-- Every Fight swing of either chips (both weapons are SLASH; the row is
-- SLASH|BLUDG); a 1-BP Fight is 3 swings = 3 chips, 2 BP = 5, 3 BP = 7
-- (M.fightSwings).  Pummel is two bludgeoning hits = 2 chips.
-- ----------------------------------------------------------------------------
local H = dofile("tools/tests/lib/ot6.lua")

local POLICY = "@POLICY@"
local IDLE = tonumber("@IDLE@") or 0
if POLICY:find("@") then POLICY = "control" end

local SABIN, CYAN = 5, 2
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local PUMMEL, AURABOLT, SUPLEX = 0x5D, 0x5E, 0x5F
local RIZOPAS = 0x0155
local CAP = 24000                    -- battle frames (the qualification's
                                     -- attempt 1 soloed to ~f18800 = ~9800)
local SHORE_CAP = 8000               -- frames after the battle to reach map 159

-- The policies.  "control" is gen_sabin_falls' own fighter, copied
-- verbatim below.  Every other one is a set of the lib's fight-driver
-- options -- the same controller the route's other generators use,
-- steered differently -- so a policy here is one a person can execute
-- through the menus.  None reads hidden HP or future RNG.  The driver
-- heals with Potions before Tonics and raises the fallen with Fenix Down
-- before healing anyone (ot6.lua makePlan), so "items = true" IS the
-- revive-and-Potion discipline.
local POLICIES = {
  control = "gen",
  -- boosted Fight from both (spend what you have), Potions to whoever is
  -- under 40% or inside a round of death, Fenix Down for the fallen
  care = { tactical = false, boost = true, bank = 0, items = true,
           healPercent = 40 },
  -- break-first cadence: chip unboosted (BP regenerates) until the bank
  -- holds 2, then a 5-swing Fight breaks the 4-shield gauge and lands
  -- the surplus swing broken; care as `care`
  bank2 = { tactical = false, boost = true, bank = 2, items = true,
            healPercent = 40 },
  -- all-in: every turn is a boosted Fight from turn 1; no items, no care,
  -- no raises
  allin = { tactical = false, boost = true, bank = 0, items = false,
            cure = false },
  -- bank for the boss (the lab's own): Fight the school unboosted -- a
  -- Piranha has 10 HP and one shield, a boosted swing on it is waste --
  -- and unload the banked BP the moment Rizopas surfaces (bank flips
  -- 99 -> 0 on the surface, a thing the player sees on screen); care as
  -- `care`
  bankboss = { tactical = false, boost = true, bank = 99, items = true,
               healPercent = 40, flipOnSurface = true },
  -- SABIN's Blitz (tactical: Pummel at boost, CYAN Fights); care as `care`
  pummel = { tactical = true, boost = true, bank = 0, items = true,
             healPercent = 40 },
}
local opts = POLICIES[POLICY]
assert(opts, "unknown POLICY " .. POLICY)

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local CH_SEL, CH_MAX, NAME_MENU = 0x056E, 0x056F, 0x0200

-- ===================== verbatim from gen_sabin_falls.lua =====================
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local rizo = { seen = false, species = 0, shields = 0, smax = 0, wkc = 0,
               mask0 = nil }

local MENU, ACTOR = 0x7BCA, 0x62CA
local BP = 0x3E9C
local fightTier = 1
local lost = nil
local wipeN = 0
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(0x3bf4 + e * 2),
      H.readWord(0x3c1c + e * 2))
  end
  return table.concat(p, " ")
end
local MSTATE = 0x7BC2
local ST_CMD, ST_ITEM, ST_TGT, ST_TOOLS = 0x05, 0x0A, 0x38, 0x30
local CMD_ITEM = 0x01
local CMDTBL, CMDROW = 0x202E, 0x890F
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local function itemIdxOf(a)
  return H.readByte(ITEMSCR + a) + H.readByte(ITEMROW + a)
end
local BATTINV = 0x2686
local function pHPf(e) return H.readWord(0x3BF4 + e * 2) end
local function pMaxHPf(e) return H.readWord(0x3C1C + e * 2) end
local function battItemIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end
local function cmdRowOf(actor, cmdId)
  for i = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + i * 3) == cmdId then return i end
  end
  return nil
end
local fPlan, fPlanActor, fBtn = nil, nil, nil
local fTick, fStreak = 0, 0
local function makeFightPlan(actor)
  local hp, mx = pHPf(actor), pMaxHPf(actor)
  local itemRow = cmdRowOf(actor, CMD_ITEM)
  local rizoUp = rizo.seen and monPresent(5)
  local thresh = rizoUp and 6 or 8
  if mx > 0 and hp > 0 and hp * 10 < mx * thresh and itemRow then
    local id = nil
    if mx - hp >= 60 and battItemIdx(POTION) then id = POTION
    elseif battItemIdx(TONIC) then id = TONIC
    elseif battItemIdx(POTION) then id = POTION end
    if id then
      H.log(string.format("[falls] heal f%d e%d %s (hp %d/%d) [%s]",
        H.frame, actor, id == TONIC and "TONIC" or "POTION", hp, mx,
        partyLine()))
      return { kind = "item", item = id, row = itemRow }
    end
  end
  local bp = H.readByte(BP + actor * 2)
  local boost = bp >= 1 and math.min(bp, 3) or 0
  H.log(string.format("[falls] cast f%d e%d boost=%d tier=%d [%s]",
    H.frame, actor, boost, fightTier, partyLine()))
  return { kind = "fight", boostLeft = boost }
end
local function fightButton()
  local st = H.readByte(MSTATE)
  local actor = H.readByte(ACTOR)
  if fPlan == nil or fPlanActor ~= actor then
    if st ~= ST_CMD then
      if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT then
        return { "b" }
      end
      return nil
    end
    fPlan, fPlanActor = makeFightPlan(actor), actor
    return nil
  end
  local plan = fPlan
  if st == ST_CMD then
    if plan.kind == "fight" then
      if plan.boostLeft > 0 then
        plan.boostLeft = plan.boostLeft - 1
        return { "r" }
      end
      local cur = H.readByte(CMDROW + actor) & 3
      if cur ~= 0 then return { "up" } end
      return { "a" }
    end
    local cur = H.readByte(CMDROW + actor) & 3
    if cur == plan.row then return { "a" } end
    if plan.rowStall and plan.rowStall > 2 then
      plan.rowStall = 0
      return { ({ [0]="up", [1]="left", [2]="right", [3]="down" })[plan.row] }
    end
    plan.rowStall = (plan.rowStall or 0) + 1
    return { cur < plan.row and "down" or "up" }
  end
  if st == ST_ITEM and plan.kind == "item" then
    local want = battItemIdx(plan.item)
    if want == nil then return { "b" } end
    local cur = itemIdxOf(actor)
    if cur < want then return { "down" } end
    if cur > want then return { "up" } end
    return { "a" }
  end
  if st == ST_TGT then
    fPlan, fPlanActor = nil, nil
    return { "a" }          -- item: default self; Fight: default enemy
  end
  if st == ST_TOOLS then return { "b" } end
  return nil
end
local fHeld, fHb = 0, -300
local function fightPulse(_)
  if H.readByte(MENU) == 0 then
    fPlan, fPlanActor, fStreak, fHeld = nil, nil, 0, 0
    fTick = fTick + 1
    H.setPad(fTick % 8 < 4 and { "a" } or {})
    return
  end
  fStreak = fStreak + 1
  if fStreak < 4 then H.setPad({}); return end
  fTick = fTick + 1
  if H.frame - fHb >= 300 then
    fHb = H.frame
    local a = H.readByte(ACTOR)
    H.log(string.format("[falls] fmenu f%d st=%02X actor=%d row=%d itm=%d " ..
      "plan=%s held=%d [%s]", H.frame, H.readByte(MSTATE), a,
      H.readByte(CMDROW + a) & 3, itemIdxOf(a),
      fPlan and fPlan.kind or "-", fHeld, partyLine()))
  end
  local ph = fTick % 30
  if ph == 0 then
    if fPlan ~= nil then
      fHeld = fHeld + 1
      if fHeld > 40 then
        H.log(string.format("[falls] plan stalled 40 pulses (st=%02X) -- " ..
          "backing out", H.frame and H.readByte(MSTATE) or 0))
        fPlan, fPlanActor, fHeld = nil, nil, 0
        fBtn = { "b" }
        H.setPad(fBtn)
        return
      end
    else
      fHeld = 0
    end
    fBtn = fightButton()
  end
  H.setPad(ph < 6 and fBtn or {})
end
local function wipeWatch(tag)
  local wiped = H.partyWipedInBattle()
  wipeN = wiped and wipeN + 1 or 0
  if (H.gameOverFired or 0) > 0 and not lost then
    lost = string.format("%s: GAME OVER counted by the canary at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[falls] LOST -- " .. lost)
  end
  if wipeN >= 90 and not lost then
    lost = string.format("%s: PARTY WIPED at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[falls] LOST -- " .. lost)
  end
end
-- =================== end of the verbatim generator copy ====================

-- ------------------------------------------------------------- the lab --
local F = opts ~= "gen" and H.newFightDriver("Rizopas", opts) or nil

-- The field bag ($1969) syncs from the battle module only at teardown, so
-- mid-fight the count comes from the battle inventory: $2686, records of 5
-- bytes, +0 item, +3 quantity.  Not populated during battle load: hand
-- back the baseline then.
local function bagNow(id, baseline)
  if H.battleActive() then
    for i = 0, 255 do
      if H.readByte(0x2686 + i * 5) == id then return H.readByte(0x2689 + i * 5) end
    end
    return baseline
  end
  if H.battleLoadStarted() then return baseline end
  return H.invCountOf(id)
end

-- the seed InitBattle draws, read off the `sta $be` store the way
-- H.newSeedLadder reads it (lib/ot6.lua "battle rng seed")
local seedDrawn, seedN = nil, 0
local function armSeedWatch()
  local addr = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    seedN = seedN + 1
    local seed = emu.getState()["cpu.a"] & 0xff
    if seedDrawn == nil then seedDrawn = seed end
    H.log(string.format("[lab] battle %d seeded $be=$%02X from $021e=%d at f%d",
      seedN, seed, H.readByte(0x021E), H.frame))
  end, emu.callbackType.exec, addr, addr)
end

-- Rizopas is slot 5: entity 9.  HP $3BF4 + 18, shields OT6_SHIELD_CUR
-- $3E40 + 10, broken ticks $3E90 + 10, statuses $3EE4/$3EE5 + 8 + 10 and
-- $3EF8/$3EF9 + 8 + 10 (the gen's own reads: 0x3E38 + 8 + 10 etc.).
local RHP, RSH, RBRK = 0x3C06, 0x3E4A, 0x3E9A
local function monLine()
  local p = {}
  for s = 0, 5 do
    if monPresent(s) then p[#p + 1] = string.format("s%d:%d", s, H.readWord(0x3BFC + s * 2)) end
  end
  return table.concat(p, ",")
end

-- Per-action attribution, read off the engine the way the lib's recovery
-- trace does: ExecCmd runs with X = the acting entity offset and $b5/$b6
-- the command/attack after queue-time folding; SaveForMimic runs right
-- after the normal-action path returns.  Party (x < 8) and monsters
-- (x = 8..18, slot = x/2 - 4) alike.  Observers only.
local actT = 0
local function armActionWatch()
  local function hook(addr, fn)
    emu.addMemoryCallback(function() fn(emu.getState()) end, emu.callbackType.exec, addr, addr)
  end
  hook(H.sym("ExecCmd@battle_code"), function(cpu)
    local x = cpu["cpu.x"] & 0xffff
    if x < 20 and x % 2 == 0 then
      H.log(string.format("[act] t=%d start e%d cmd=$%02X atk=$%02X tgt=$%04X rizo=%d/sh%d brk=%d st=%02X,%02X,%02X,%02X hp=%d,%d bp=%d mons=%s",
        actT, x // 2, H.readByte(0xB5), H.readByte(0xB6), H.readWord(0xB8),
        H.readWord(RHP), H.readByte(RSH), H.readByte(RBRK),
        H.readByte(0x3EE4 + 18), H.readByte(0x3EE5 + 18), H.readByte(0x3EF8 + 18), H.readByte(0x3EF9 + 18),
        H.readWord(0x3BF4), H.readWord(0x3BF6),
        x < 8 and H.readByte(0x3E9C + x) or 0, monLine()))
    end
  end)
  hook(H.sym("ExecRetal"), function(cpu)
    local x = cpu["cpu.x"] & 0xffff
    H.log(string.format("[retal] t=%d e%d counters (cmd list ptr $%02X) rizo=%d/sh%d hp=%d,%d",
      actT, x // 2, H.readByte(0x32CD + x), H.readWord(RHP), H.readByte(RSH),
      H.readWord(0x3BF4), H.readWord(0x3BF6)))
  end)
  hook(H.sym("SaveForMimic"), function(cpu)
    local x = cpu["cpu.x"] & 0xffff
    if x < 20 and x % 2 == 0 then
      H.log(string.format("[act] t=%d end   e%d rizo=%d/sh%d hp=%d,%d mons=%s",
        actT, x // 2, H.readWord(RHP), H.readByte(RSH),
        H.readWord(0x3BF4), H.readWord(0x3BF6), monLine()))
    end
  end)
end

local res = { deaths = {}, raises = 0, hits = 0 }
local t, why = 0, nil
local battleUp, battleDown, surfaceT, deadT = nil, nil, nil, nil
local beUp = nil
local fenix0, potion0, tonic0
local fenixLive, potionLive, tonicLive
local monHp, monSh = nil, nil
local hpLast = {}
local bpAtSurface = "?"
local shoreAt = nil

-- the per-frame ledger, called on every ride frame
local function ledger()
  if battleUp == nil and H.battleLoadStarted() then
    battleUp = H.frame
    beUp = H.readByte(0xBE)
    H.log(string.format("[lab] battle up at f%d: $BE=$%02X $021e=%d store seed=%s",
      H.frame, beUp, H.readByte(0x021E), seedDrawn and string.format("$%02X", seedDrawn) or "none"))
  end
  if battleUp == nil then return end
  t = H.frame - battleUp
  actT = t
  if not H.battleActive() then return end
  -- the bag sample walks 256 records; every 16th frame is plenty (an item
  -- use takes far longer than that to resolve) and keeps the emulator fast
  if t % 16 == 0 then
    fenixLive = bagNow(FENIX_DOWN, fenixLive or fenix0)
    potionLive = bagNow(POTION, potionLive or potion0)
    tonicLive = bagNow(TONIC, tonicLive or tonic0)
  end
  if not rizo.seen and monPresent(5) then
    rizo.seen = true
    rizo.species = H.readWord(0x57C0 + 10)
    rizo.shields = H.readByte(0x3E38 + 8 + 10)
    rizo.smax    = H.readByte(0x3E39 + 8 + 10)
    rizo.wkc     = H.readByte(0x3E9C + 8 + 10)
    surfaceT = t
    bpAtSurface = string.format("%d,%d", H.readByte(BP), H.readByte(BP + 2))
    H.log(string.format("[lab] t=%d slot 5 SURFACED: species=$%04X hp=%d shields=%d/%d wkc=$%02X party=[%s] bp=%s",
      t, rizo.species, H.readWord(RHP), rizo.shields, rizo.smax, rizo.wkc, partyLine(), bpAtSurface))
    if opts ~= "gen" and opts.flipOnSurface then
      opts.bank = 0
      H.log(string.format("[lab] t=%d bankboss: the boss is up -- bank 99 -> 0, spend everything", t))
    end
  end
  if rizo.seen then
    local hp, sh = H.readWord(RHP), H.readByte(RSH)
    if monHp ~= nil and (hp ~= monHp or sh ~= monSh) then
      res.hits = res.hits + 1
      H.log(string.format("[hit] t=%d rizopas hp=%d (%+d) sh=%d (%+d) brk=%d bp=%d,%d",
        t, hp, hp - monHp, sh, sh - monSh, H.readByte(RBRK), H.readByte(BP), H.readByte(BP + 2)))
    end
    if monHp == nil then monHp, monSh = hp, sh end
    if hp > 0 or monHp ~= nil then monHp, monSh = hp, sh end
    if deadT == nil and hp == 0 then
      deadT = t
      H.log(string.format("[lab] t=%d RIZOPAS DOWN (%d frames after surfacing) party=[%s]", t, t - surfaceT, partyLine()))
    end
  end
  for e = 0, 1 do
    local php = H.readWord(0x3BF4 + e * 2)
    if hpLast[e] ~= nil and php ~= hpLast[e] then
      H.log(string.format("[hp] t=%d entity %d %d -> %d (%+d)", t, e, hpLast[e], php, php - hpLast[e]))
      if hpLast[e] > 0 and php == 0 then
        res.deaths[#res.deaths + 1] = string.format("e%d@%d", e, t)
        H.log(string.format("[death] t=%d entity %d rizo=%s", t, e, rizo.seen and (H.readWord(RHP) .. "/sh" .. H.readByte(RSH)) or "not up"))
      elseif hpLast[e] == 0 and php > 0 then
        res.raises = res.raises + 1
        H.log(string.format("[raise] t=%d entity %d to %d hp", t, e, php))
      end
    end
    hpLast[e] = php
  end
end

-- The generator's ride, with the fighter swapped for the policy under
-- test and the ledger on every frame.  Dialogs tap A, the "Jump?" choice
-- is answered 0 (the gen's choiceWant), the GAU name menu after the win
-- is closed with START, the direction is held otherwise.
local function ride(dir, pred, what, budget, choiceWant)
  local phase, hb, quiet = 0, -900, 0
  return H.driveUntil(pred, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      ledger()
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format(
          "ride[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s b=%s ch=%d/%d rizo=%s",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle()), H.readByte(CH_SEL), H.readByte(CH_MAX),
          rizo.seen and (H.readWord(RHP) .. "/sh" .. H.readByte(RSH)) or "-"))
      end
      wipeWatch(what)
      if lost then H.setPad({}); return end

      if inBattle() or H.battleLoadStarted() then
        if not rizo.mask0 and H.battleLoadStarted() then
          local m = 0
          for s = 0, 5 do if monPresent(s) then m = m | (1 << s) end end
          rizo.mask0 = m
          H.log(string.format("[falls] battle-up present mask=$%02X", m))
        end
        if opts == "gen" then fightPulse(phase) else F.frame() end
        return
      end
      if F and F.idle and battleUp and battleDown == nil then F.idle() end

      if H.readByte(CH_MAX) >= 2 and H.dialogWaiting() then
        local sel, want = H.readByte(CH_SEL), choiceWant or 0
        if sel < want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      end

      if H.readByte(NAME_MENU) == 1 and H.readByte(0x0059) ~= 0
         and (H.readByte(0x0026) == 0x5F or H.readByte(0x0027) == 0x5F) then
        quiet = quiet + 1
        if quiet >= 30 then
          if quiet == 30 then
            H.log(string.format("[falls] NAME MENU at f%d -- START", H.frame))
          end
          H.setPad(phase < 4 and { "start" } or {})
          return
        end
        H.setPad({})
        return
      end
      quiet = 0

      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad(dir and { [dir] = true } or {})
    end),
  }, what)
end

H.run({ maxFrames = 50000, allowGameOver = true }, {
  H.loadState("build/states/falls_prejump.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 156, "the prejump fixture is on the falls top (156)")
    H.assertEq(H.fieldX() == 15 and H.fieldY() == 10, true, "standing at (15,10)")
    H.assertEq(inParty(5) and inParty(2), true, "SABIN and CYAN in the party")
    armSeedWatch()
    armActionWatch()
    fenix0, potion0, tonic0 = H.invCountOf(FENIX_DOWN), H.invCountOf(POTION), H.invCountOf(TONIC)
    -- field HP off the character records ($1600 + 37*c + 9/11), the bake's
    -- own read, so the fixture's entry HP is on every run's log
    H.log(string.format("[lab] set-off policy=%s idle=%d phase=%d bag f/p/t=%d/%d/%d field hp SABIN=%d/%d CYAN=%d/%d at f%d",
      POLICY, IDLE, H.readByte(0x021E), fenix0, potion0, tonic0,
      H.readWord(0x1600 + 37 * SABIN + 9), H.readWord(0x1600 + 37 * SABIN + 11),
      H.readWord(0x1600 + 37 * CYAN + 9), H.readWord(0x1600 + 37 * CYAN + 11), H.frame))
  end),
  H.navTo(13, 11, { maxFrames = 5000, playBattles = "tactical" }),
  -- the seed knob: stand still IDLE frames on the jump row ($021e ticks
  -- once a frame, period 60)
  H.waitFrames(IDLE),
  H.call(function()
    H.log(string.format("[lab] at (%d,%d) after %d idle frames; phase now %d, f%d",
      H.fieldX(), H.fieldY(), IDLE, H.readByte(0x021E), H.frame))
  end),
  ride("up", function()
    if lost ~= nil then return true end
    if battleUp and battleDown == nil and not H.battleLoadStarted() and not H.battleActive()
       and not H.partyWipedInBattle() then
      battleDown = H.frame
      H.log(string.format("[lab] battle down at f%d (t=%d) party=[%s] rizo=%s",
        H.frame, t, partyLine(), rizo.seen and (H.readWord(RHP) .. "/sh" .. H.readByte(RSH)) or "never surfaced"))
    end
    if battleUp and t >= CAP then why = "cap"; return true end
    if battleDown and H.frame - battleDown > SHORE_CAP then why = "shore_cap"; return true end
    if mapIdx() == 159 and sw(0x3F) == 1 and H.hasControl() and H.tileAligned() and bright() >= 15 then
      shoreAt = H.frame
      return true
    end
    return false
  end, "jump + battle 18 + the shore", CAP + SHORE_CAP + 6000, 0),
  H.release(),
  H.call(function()
    H.setPad({})
    if F and F.idle then F.idle() end
    local fenix1, potion1, tonic1 = fenixLive or fenix0, potionLive or potion0, tonicLive or tonic0
    local outcome
    if lost then
      outcome = lost:find("GAME OVER") and "lost_gameover" or "lost_wiped"
    elseif deadT ~= nil and battleDown ~= nil then
      outcome = "won"
    elseif why then
      outcome = "lost_" .. why
    else
      outcome = "unknown"
    end
    H.log(string.format(
      "[result] policy=%s idle=%d seed=%s be_up=%s outcome=%s t=%s t_surface=%s t_boss=%s fenix=%d potion=%d tonic=%d "
      .. "deaths=%s raises=%d hits=%d rizo_hp=%s rizo_sh=%s bp_at_surface=%s shore=%s nseeds=%d party=[%s]",
      POLICY, IDLE, seedDrawn and string.format("$%02X", seedDrawn) or "none",
      beUp and string.format("$%02X", beUp) or "none", outcome,
      battleDown and tostring(battleDown - battleUp) or tostring(t),
      tostring(surfaceT), (deadT and surfaceT) and tostring(deadT - surfaceT) or "none",
      fenix0 - fenix1, potion0 - potion1, tonic0 - tonic1,
      #res.deaths > 0 and table.concat(res.deaths, ";") or "none", res.raises, res.hits,
      tostring(monHp), tostring(monSh), bpAtSurface,
      shoreAt and tostring(shoreAt - (battleDown or shoreAt)) or "no", seedN, partyLine()))
  end),
})
