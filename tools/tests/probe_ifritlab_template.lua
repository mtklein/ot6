-- probe_ifritlab_template.lua -- Ifrit & Shiva lab (battle 70), experiment half.
--
-- Hand-run instrument (probe_): boots the ifritlab_entry.mss fixture banked
-- by probe_ifritlab_bake.lua (map 264 (3,7), the gen's own care level,
-- weapons still the checkpoint's), equips the strategy's own loadout,
-- stands still SEED frames to shift the battle-RNG phase ($021e, period 60;
-- the seed a battle draws is phase*4), presses A into IFRIT (battle 70),
-- runs the fight under one strategy, and reports one machine-readable
-- [result] line, PASSing either way -- this file measures, it does not
-- assert a win.
--
-- The batch runner (ifritlab_batch.sh) substitutes the @TOKEN@ defaults
-- below (sed).  Tokens:
--   STRATEGY  gen      the gen's own play today: ThunderBlade loadout (both
--                      siblings null bolt; slash chips only Shiva) + lib
--                      newFightDriver {tactical, boost, bank=3, items,
--                      healPercent=60, cadence=12} -- the baseline
--             classfix the class-correct loadout (pierce daggers/spear for
--                      Ifrit's 6 pierce shields, non-elem slash for Shiva's
--                      6 slash) + the same lib driver + healer designation
--                      + nuke={Ice}
--             bespoke  the design-doc play, per-turn: CELES casts boosted
--                      Ice ONLY while IFRIT holds the stage (Shiva absorbs
--                      ice), everyone else Fights with the class-correct
--                      loadout (unboosted while the stage sibling still has
--                      shields -- chip is per-hit, so fast turns break
--                      sooner and bank BP -- then boosted bursts once
--                      broken), one designated item healer, any actor
--                      revives with a Fenix Down
--             taps     blind A-taps, the floor
--   SEED      frames to stand still before engaging (only SEED mod 60
--             matters; the [result] line carries the phase and $be the
--             engage actually drew, so collisions are visible, not assumed)
--   HEALPCT / BANK / HEALER(char id) knobs; FIXTURE picks the .mss.
--
-- Win/loss is the gen's own: a battle-70 win flips switch $0060 in the
-- _cc7937 tail; a loss is the event GameOver, read-fired into
-- H.gameOverFired (allowGameOver).

local H = dofile("tools/tests/lib/ot6.lua")

local STRATEGY = "@STRATEGY@"
local FIXTURE  = "@FIXTURE@"
local SEED     = tonumber("@SEED@")    or 0
local HEALPCT  = tonumber("@HEALPCT@") or 60
local BANK     = tonumber("@BANK@")    or 3
local HEALER   = tonumber("@HEALER@")  or 1
if STRATEGY:find("@") then STRATEGY = "bespoke" end
if FIXTURE:find("@") then FIXTURE = "ifritlab_entry" end

local LOCKE, EDGAR, SABIN, CELES = 1, 4, 5, 6
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ICE_SPELL, FIRE_SPELL = 0x01, 0x00
local IFRIT, SHIVA = 0x0109, 0x0108
local CONFIRM_BATTLE_GONE = 90
local MAXBATT = 90000

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end

-- ------------------------------------------------------- battle reads --
local function eoff(m) return 8 + m * 2 end
local function mshields(m) return H.readByte(0x3E38 + eoff(m)) end
local function mticks(m)   return H.readByte(0x3E88 + eoff(m)) end
local function mhp(m)      return H.readWord(0x3BFC + m * 2) end
local function onfield(m)  return H.readByte(0x3AA8 + m * 2) & 1 end
local function mspecies(m) return H.readWord(0x57C0 + m * 2) end

-- ------------------------------------------- loss + seed + death watch --
local function armLossWatch()
  local ok, addr = pcall(function() return H.sym("GameOver") end)
  if ok then
    emu.addMemoryCallback(function()
      H.gameOverFired = H.gameOverFired + 1
    end, emu.callbackType.read, addr, addr)
  end
  local ok2, addr2 = pcall(function() return H.sym("TitleScreen") end)
  if ok2 then
    emu.addMemoryCallback(function()
      H.gameOverFired = H.gameOverFired + 1
    end, emu.callbackType.exec, addr2, addr2)
  end
  H.log(string.format("[lab] loss watch armed: GameOver(read)=%s TitleScreen(exec)=%s",
    tostring(ok), tostring(ok2)))
end

local res = { seeds = {}, phases = {}, deaths = 0, bframes = 0 }
local function armSeedWatch()
  local addr = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    local seed = emu.getState()["cpu.a"] & 0xff
    res.seeds[#res.seeds + 1] = seed
    res.phases[#res.phases + 1] = H.readByte(0x021E)
    H.log(string.format("[lab] battle seeded $be=$%02X from $021e=%d at f%d",
      seed, H.readByte(0x021E), H.frame))
  end, emu.callbackType.exec, addr, addr)
end

local wasAlive = {}
local function trackDeaths()
  for e = 0, 3 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      local alive = H.readWord(0x3BF4 + e * 2) > 0
      if wasAlive[e] and not alive then
        res.deaths = res.deaths + 1
        H.log(string.format("[lab] slot %d (char $%02X) DOWN at f%d (death #%d)",
          e, H.readByte(0x3ED8 + e * 2), H.frame, res.deaths))
      end
      wasAlive[e] = alive
    else
      wasAlive[e] = nil
    end
  end
end

-- -------------------------------------------------- per-strategy equip --
local function wornWeapon(c) return H.readByte(0x1600 + 37 * c + 0x1F) end
local function charPos(charId)
  return function() return (H.readByte(0x1850 + charId) >> 3) & 0x03 end
end
local function equipPref(charId, cands, tag)
  local steps = {}
  for _, id in ipairs(cands) do
    steps[#steps + 1] = H.cond(function()
      for _, w in ipairs(cands) do
        if wornWeapon(charId) == w then return false end
      end
      return H.invCountOf(id) > 0
    end, {
      H.equipWeapon(charPos(charId), id,
        { slot = 0, tag = string.format("%s $%02X", tag, id) }),
    }, {})
  end
  steps[#steps + 1] = H.call(function()
    H.log(string.format("[equipPref] %s ends holding $%02X",
      tag, wornWeapon(charId)))
  end)
  return seq(steps)
end

-- the gen's own loadout today (the baseline's arms)
local function genLoadout()
  return seq({
    H.equipLoadout(LOCKE, { { 0, 0x0F }, { 1, 0x5A }, { 2, 0x69 }, { 3, 0x84 } },
      { tag = "LOCKE gen kit (ThunderBlade)" }),
    H.equipLoadout(EDGAR, { { 0, 0x0F }, { 1, 0x5A }, { 2, 0x69 }, { 3, 0x84 } },
      { tag = "EDGAR gen kit (ThunderBlade)" }),
    H.equipLoadout(SABIN, { { 0, 0x53 }, { 1, 0x5A }, { 2, 0x73 }, { 3, 0x86 } },
      { tag = "SABIN gen kit" }),
    H.equipLoadout(CELES, { { 0, 0x0A }, { 2, 0x6A }, { 3, 0x84 } },
      { tag = "CELES gen kit" }),
  })
end

-- class-correct: pierce (non-elem) on LOCKE/EDGAR for Ifrit's shields,
-- slash (non-elem) on SABIN/CELES for Shiva's
local function classLoadout()
  return seq({
    equipPref(LOCKE, { 0x04, 0x02, 0x01, 0x00 }, "LOCKE pierce dagger"),
    H.equipLoadout(LOCKE, { { 1, 0x5A }, { 2, 0x69 }, { 3, 0x84 } },
      { tag = "LOCKE armor" }),
    equipPref(EDGAR, { 0x1F, 0x1D, 0x01, 0x00 }, "EDGAR pierce spear"),
    H.equipLoadout(EDGAR, { { 1, 0x5A }, { 2, 0x69 }, { 3, 0x84 } },
      { tag = "EDGAR armor" }),
    H.equipLoadout(SABIN, { { 0, 0x53 }, { 1, 0x5A }, { 2, 0x73 }, { 3, 0x86 } },
      { tag = "SABIN kit (MetalKnuckle)" }),
    equipPref(CELES, { 0x0B, 0x0A }, "CELES slash sword"),
    H.equipLoadout(CELES, { { 2, 0x6A }, { 3, 0x84 } }, { tag = "CELES armor" }),
  })
end

-- ------------------------------------------------------- the bespoke --
-- The design-doc play (docs/design/magicite-ifrit-shiva.md §2.2-2.3,
-- bosses-wob.md §13): read the stage.  IFRIT (6 pierce shields, weak ice,
-- absorbs fire, nulls the rest) opens; every landed hit or Magic command
-- advances the swap counter, so after ~6 the siblings trade places.  A
-- broken sibling takes no turns, so pierce chip into Ifrit both silences
-- Fire 2 and opens the 4x damage window; Celes' Ice rides his weakness but
-- must never fly while SHIVA (absorbs ice) holds the stage.  The fight
-- ends by script when either sibling's HP reaches 0.
local MENU_B, ACTOR_B, MSTATE_B = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL_B, CMDROW_B = 0x202E, 0x890F
local BCHID_B, BCHP_B, BCMAXHP_B = 0x3ED8, 0x3BF4, 0x3C1C
local BP_B = 0x3E9C
local ST_CMD_B, ST_TGT_B, ST_ITEM_B = 0x05, 0x38, 0x0A
local CMD_FIGHT_B, CMD_ITEM_B, CMD_MAGIC_B = 0x00, 0x01, 0x02
local ST_MAGIC_B = 0x0E
local ITEMSCR_B, ITEMROW_B, BATTINV_B = 0x8947, 0x894F, 0x2686
local MLISTPTR_B = 0x302C
local MSCROLL_B, MCOL_B, MROW_B = 0x8913, 0x8917, 0x891B
local CURMP_B = 0x3C08
local bespokeCharTC = H.targetCursor({ mask = 0x7B7D,
  dirs = { "down", "up", "left", "right" } })

local function spellCellB(actor, id, strict)
  local base = H.readWord(MLISTPTR_B + actor * 2)
  if base < 0x2000 or base > 0x2600 then return nil end
  for cell = 0, 53 do
    local a = base + (cell + 1) * 4
    if H.readByte(a) == id then
      local cost = H.readByte(a + 3)
      if H.readWord(CURMP_B + actor * 2) < cost then return nil end
      if strict and (H.readByte(a + 1) & 0x80) ~= 0 then return nil end
      return cell, cost
    end
  end
  return nil
end
local function cmdRowB(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL_B + actor * 12 + r * 3) == cmd then return r end
  end
  return nil
end
local function bagIdxOfB(ids)
  for i = 0, 251 do
    local id = H.readByte(BATTINV_B + i * 5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(BATTINV_B + i * 5 + 3) > 0 then return i end
    end
  end
  return nil
end

local function newBespokePlan(tag, slots)
  local F = {}
  local phase, mf = 0, 0
  local turnActor, turnPlan = nil, nil
  local iceCasts, bursts = 0, 0
  local function stageSibling()
    -- whichever sibling is on stage and alive right now
    if onfield(slots.I) == 1 and mhp(slots.I) > 0 then return "ifrit" end
    if onfield(slots.S) == 1 and mhp(slots.S) > 0 then return "shiva" end
    return nil
  end
  local function stageShields()
    local s = stageSibling()
    if s == "ifrit" then return mshields(slots.I) end
    if s == "shiva" then return mshields(slots.S) end
    return 0
  end
  local function decideTurn(actor)
    local charId = H.readByte(BCHID_B + actor * 2)
    local hp = H.readWord(BCHP_B + actor * 2)
    local mx = H.readWord(BCMAXHP_B + actor * 2)
    -- 1. revive, any actor: a down member is a quarter of the offense
    --    and the wipe fuse both
    local downSlots = {}
    for e = 0, 3 do
      if H.readWord(BCMAXHP_B + e * 2) > 0
         and H.readWord(BCHP_B + e * 2) == 0 then
        downSlots[#downSlots + 1] = e
      end
    end
    if #downSlots > 0 and bagIdxOfB({ FENIX_DOWN }) then
      return { kind = "item", ids = { FENIX_DOWN }, target = downSlots[1] }
    end
    -- 2. the healer's item line, plus anyone's own last-ditch self-heal
    local isHealer = charId == HEALER
    if isHealer then
      local needy, worst = nil, HEALPCT
      for e = 0, 3 do
        local ehp = H.readWord(BCHP_B + e * 2)
        local emx = H.readWord(BCMAXHP_B + e * 2)
        if emx > 0 and ehp > 0 then
          local pct = ehp * 100 // emx
          if pct < worst then needy, worst = e, pct end
        end
      end
      if needy and bagIdxOfB({ POTION, TONIC }) then
        return { kind = "item", ids = { POTION, TONIC }, target = needy }
      end
    elseif mx > 0 and hp > 0 and hp * 100 < mx * 25
       and bagIdxOfB({ POTION, TONIC }) then
      return { kind = "item", ids = { POTION, TONIC }, target = actor }
    end
    -- 3. offense, staged on who holds the stage
    local stage = stageSibling()
    if charId == CELES and stage == "ifrit" then
      -- boosted Ice into the ice weakness; never while Shiva is up
      if spellCellB(actor, ICE_SPELL, true) then
        return { kind = "magic", spell = ICE_SPELL, boost = true }
      end
    end
    -- everyone else (and Celes in a Shiva phase): Fight.  Unboosted while
    -- the stage sibling still has shields (chip is per-hit; fast turns
    -- break sooner and regenerate BP), boosted bursts once it is broken.
    return { kind = "fight", boost = stageShields() == 0 }
  end
  local function buttonFor(actor, st)
    local plan = turnPlan
    if plan.kind == "item" then
      if st == ST_CMD_B then
        local want = cmdRowB(actor, CMD_ITEM_B)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_B + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_ITEM_B then
        local want = bagIdxOfB(plan.ids)
        if want == nil then return "b" end
        local cur = H.readByte(ITEMSCR_B + actor) + H.readByte(ITEMROW_B + actor)
        if cur < want then return "down" end
        if cur > want then return "up" end
        return "a"
      elseif st == ST_TGT_B then
        plan.tgtSpin = (plan.tgtSpin or 0) + 1
        if plan.tgtSpin > 240 then return "a" end
        bespokeCharTC.observe()
        return bespokeCharTC.steer(plan.target, mf)
      end
      return "b"
    end
    if plan.kind == "magic" then
      if st == ST_CMD_B then
        if plan.boost and not plan.boosted then
          local bp = H.readByte(BP_B + actor * 2)
          local want = (bp >= 2) and math.min(bp, 3) or 0
          plan.boostLeft = plan.boostLeft or want
          if plan.boostLeft > 0 then
            plan.boostLeft = plan.boostLeft - 1
            return "r"
          end
          plan.boosted = true
        end
        local want = cmdRowB(actor, CMD_MAGIC_B)
        if want == nil then return "b" end
        local cur = H.readByte(CMDROW_B + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_MAGIC_B then
        local cell = spellCellB(actor, plan.spell, false)
        if cell == nil then return "b" end
        local wr, wc = cell // 2, cell % 2
        local ar = H.readByte(MSCROLL_B + actor) + H.readByte(MROW_B + actor)
        local col = H.readByte(MCOL_B + actor)
        if ar < wr then return "down" end
        if ar > wr then return "up" end
        if col < wc then return "right" end
        if col > wc then return "left" end
        return "a"
      elseif st == ST_TGT_B then
        return "a"                       -- one monster on stage
      end
      return "b"
    end
    -- fight
    if st == ST_CMD_B then
      if plan.boost and not plan.boosted then
        local bp = H.readByte(BP_B + actor * 2)
        local want = (bp >= BANK) and math.min(bp, 3) or 0
        plan.boostLeft = plan.boostLeft or want
        if plan.boostLeft > 0 then
          plan.boostLeft = plan.boostLeft - 1
          return "r"
        end
        plan.boosted = true
      end
      local want = cmdRowB(actor, CMD_FIGHT_B)
      local cur = H.readByte(CMDROW_B + actor) & 3
      if want == nil then return "a" end
      if cur == want then return "a" end
      return cur < want and "down" or "up"
    elseif st == ST_TGT_B then
      return "a"
    end
    return "b"
  end
  function F.frame()
    phase = (phase + 1) % 8
    if H.readByte(MENU_B) == 0 then
      turnActor, turnPlan = nil, nil
      H.setPad(phase < 4 and { "a" } or {})
      return
    end
    mf = mf + 1
    local actor = H.readByte(ACTOR_B) & 3
    local st = H.readByte(MSTATE_B)
    if st == 0x01 then H.setPad({}); return end
    if (turnPlan == nil or turnActor ~= actor) and st ~= ST_CMD_B then
      H.setPad({})
      return
    end
    if turnPlan == nil or turnActor ~= actor then
      turnActor = actor
      turnPlan = decideTurn(actor)
      H.log(string.format("[%s] f%d slot=%d char=$%02X stage=%s plan=%s%s%s",
        tag, H.frame, actor, H.readByte(BCHID_B + actor * 2),
        tostring(stageSibling()), turnPlan.kind,
        turnPlan.kind == "item" and (" tgt=" .. turnPlan.target) or "",
        turnPlan.boost and " (boost)" or ""))
    end
    if mf % 8 >= 4 then H.setPad({}); return end
    local btn = buttonFor(actor, st)
    if st == ST_TGT_B and btn == "a" and not turnPlan.counted then
      turnPlan.counted = true
      if turnPlan.kind == "magic" then
        iceCasts = iceCasts + 1
        H.log(string.format("[%s] Ice cast #%d confirmed f%d", tag,
          iceCasts, H.frame))
      elseif turnPlan.kind == "fight" and turnPlan.boost then
        bursts = bursts + 1
      end
    end
    H.setPad(btn and { [btn] = true } or {})
  end
  function F.idle()
    turnActor, turnPlan = nil, nil
    H.log(string.format("[%s] tally: Ice x%d, boosted burst Fight x%d",
      tag, iceCasts, bursts))
  end
  return F
end

local function newTapsDriver()
  local ph = 0
  local F = {}
  function F.frame()
    ph = (ph + 1) % 8
    H.setPad(ph < 4 and { "a" } or {})
  end
  function F.idle() end
  return F
end

-- ------------------------------------------------------------------------
local slots = {}                -- filled at battle open: I=ifrit, S=shiva
local F = nil
local lost = nil
local sawBreak, breakFrame, swaps = false, nil, 0
local lastSh, lastFld = {}, {}
local ideath, sdeath = nil, nil

local function newStrategyDriver()
  if STRATEGY == "taps" then return newTapsDriver() end
  if STRATEGY == "gen" then
    return H.newFightDriver("lab-gen", { tactical = true, boost = true,
      bank = 3, items = true, healPercent = 60, cadence = 12 })
  end
  if STRATEGY == "classfix" then
    return H.newFightDriver("lab-classfix", { tactical = true, boost = true,
      bank = BANK, items = true, healer = HEALER, healPercent = HEALPCT,
      cadence = 12, nuke = { ICE_SPELL } })
  end
  -- commit: the all-slash loadout (genLoadout) but tactical OFF, so EDGAR and
  -- SABIN Fight their slash weapons (mithrilblade / metalknuckle) instead of
  -- AutoCrossbow (pierce) and Pummel (bludgeon).  All four then chip SHIVA's
  -- slash shields -- four chippers instead of gen's two -- so the party
  -- commits every hit to one sibling (the fight ends when EITHER dies) and
  -- breaks her sooner, then the banked boost bursts her (x8 boost * x2 broken
  -- = x16) inside the break window.  No dedicated healer (it would remove a
  -- chipper); healing stays opportunistic.
  if STRATEGY == "commit" then
    return H.newFightDriver("lab-commit", { tactical = false, boost = true,
      bank = BANK, items = true, healPercent = HEALPCT, cadence = 12 })
  end
  if STRATEGY == "bespoke" then
    return newBespokePlan("lab-bespoke", slots)
  end
  error("unknown STRATEGY " .. STRATEGY, 0)
end

local function fightTelemetry()
  for _, mm in ipairs({ { slots.I, "IFR" }, { slots.S, "SHV" } }) do
    local m, nm = mm[1], mm[2]
    local s, f = mshields(m), onfield(m)
    if lastSh[m] ~= nil and s ~= lastSh[m] then
      H.log(string.format("[labx] %s shields %d -> %d at f%d (hp=%d tk=%d fld=%d)",
        nm, lastSh[m], s, H.frame, mhp(m), mticks(m), f))
    end
    if lastFld[m] ~= nil and f ~= lastFld[m] then
      swaps = swaps + 1
      H.log(string.format("[labx] %s %s the stage at f%d (hp=%d sh=%d tk=%d; "
        .. "swap edge #%d)", nm, f == 1 and "TAKES" or "LEAVES", H.frame,
        mhp(m), mshields(m), mticks(m), swaps))
    end
    lastSh[m], lastFld[m] = s, f
    if not sawBreak and s == 0 and mticks(m) ~= 0 then
      sawBreak, breakFrame = true, H.frame
      H.log(string.format("[labx] first BREAK: %s at f%d (hp=%d tk=%d fld=%d)",
        nm, H.frame, mhp(m), mticks(m), f))
    end
  end
  if not ideath and mhp(slots.I) == 0 then
    ideath = H.frame
    H.log(string.format("[labx] IFRIT hp hit 0 at f%d (tk=%d)", ideath,
      mticks(slots.I)))
  end
  if not sdeath and mhp(slots.S) == 0 then
    sdeath = H.frame
    H.log(string.format("[labx] SHIVA hp hit 0 at f%d (tk=%d)", sdeath,
      mticks(slots.S)))
  end
end

local function partyLevels()
  local out = {}
  for _, c in ipairs({ LOCKE, EDGAR, SABIN, CELES }) do
    out[#out + 1] = H.readByte(0x1600 + 37 * c + 0x08)
  end
  return table.concat(out, ",")
end

H.run({ maxFrames = 400000, allowGameOver = true }, {
  -- compose.py embeds savestates by scanning loadState string LITERALS, so
  -- both fixtures are spelled out and FIXTURE (default ifritlab_entry, the
  -- L13-14 route fixture; ifritlab_entry_healthy is the level-arm's L19 bake)
  -- picks at runtime.
  (function()
    local fixtures = {
      ifritlab_entry         = H.loadState("build/states/ifritlab_entry.mss.lua"),
      ifritlab_entry_healthy = H.loadState("build/states/ifritlab_entry_healthy.mss.lua"),
    }
    return assert(fixtures[FIXTURE], "unknown FIXTURE " .. FIXTURE)
  end)(),
  H.waitFrames(90),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting() and not H.battleLoadStarted()
  end, 2400, "lab fixture settled", 5),
  H.call(function()
    H.assertEq(map(), 264, "lab fixture boots at the alcove (map 264)")
    H.assertEq(sw(0x0060), 0, "$0060 CLEAR -- battle 70 not yet won")
    armSeedWatch()
    armLossWatch()
  end),

  -- the strategy's own arms (a real player's pre-fight prep; identical
  -- input across seeds, so the phase spread below survives it)
  (STRATEGY == "gen" or STRATEGY == "commit") and genLoadout() or
    (STRATEGY == "taps" and seq({}) or classLoadout()),
  H.navTo(3, 7, { maxFrames = 9000, playBattles = "flee" }),
  H.call(function()
    H.assertEq(H.fieldX() == 3 and H.fieldY() == 7, true,
      "back at the entry point, armed")
    res.t0 = H.frame
    res.fenix0 = H.invCountOf(FENIX_DOWN)
    res.tonic0 = H.invCountOf(TONIC)
    res.potion0 = H.invCountOf(POTION)
    H.log(string.format(
      "[lab] set-off strategy=%s seed=%d phase=%d level=%s bag f/t/p=%d/%d/%d",
      STRATEGY, SEED, H.readByte(0x021E), partyLevels(),
      res.fenix0, res.tonic0, res.potion0))
  end),

  -- the seed knob
  H.waitFrames(SEED),
  H.call(function()
    H.log(string.format("[lab] stood %d frames; phase now %d at f%d",
      SEED, H.readByte(0x021E), H.frame))
  end),

  -- A into IFRIT -> battle 70
  H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
    H.hold({ "a", "down" }), H.waitFrames(4), H.hold({ "down" }), H.waitFrames(4),
  }, "A into IFRIT -> battle 70"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 70 active", 30),
  H.call(function()
    for m = 5, 0, -1 do
      if mspecies(m) == IFRIT then slots.I = m end
      if mspecies(m) == SHIVA then slots.S = m end
    end
    H.assertEq(slots.I ~= nil, true, "an IFRIT slot resolved")
    H.assertEq(slots.S ~= nil, true, "a SHIVA slot resolved")
    F = newStrategyDriver()
  end),
  H.waitUntil(function() return onfield(slots.I) == 1 end, 3600,
    "ifrit takes the stage", 10),
  H.waitFrames(90),

  -- the fight
  (function()
    local fightF, notBattle, hb = 0, 0, 0
    return H.driveUntil(function()
      if H.gameOverFired > 0 then lost = "gameover"; return true end
      if fightF >= MAXBATT then lost = "fight-timeout"; return true end
      if H.battleLoadStarted() or H.battleActive() then
        notBattle = 0
      else
        notBattle = notBattle + 1
      end
      return notBattle >= CONFIRM_BATTLE_GONE
    end, MAXBATT + 20000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        if H.battleLoadStarted() or H.battleActive() then
          fightF = fightF + 1
          res.bframes = res.bframes + 1
          trackDeaths()
          fightTelemetry()
        end
        hb = hb + 1
        if hb % 600 == 0 then
          H.log(string.format(
            "[lab] f%d ifr %d/sh%d/tk%d/fld%d | shv %d/sh%d/tk%d/fld%d "
            .. "| party %d,%d,%d,%d | bp %d,%d,%d,%d",
            H.frame, mhp(slots.I), mshields(slots.I), mticks(slots.I),
            onfield(slots.I), mhp(slots.S), mshields(slots.S),
            mticks(slots.S), onfield(slots.S),
            H.readWord(0x3BF4), H.readWord(0x3BF6),
            H.readWord(0x3BF8), H.readWord(0x3BFA),
            H.readByte(0x3E9C), H.readByte(0x3E9E),
            H.readByte(0x3EA0), H.readByte(0x3EA2)))
        end
        F.frame()
      end),
    }, "battle 70 (" .. STRATEGY .. ")")
  end)(),
  H.call(function()
    if F and F.idle then F.idle() end
    H.setPad({})
    -- snapshot resources NOW: a loss that reaches the title screen would
    -- revert them (auto-Continue time travel) before the result read
    res.fenix1 = H.invCountOf(FENIX_DOWN)
    res.tonic1 = H.invCountOf(TONIC)
    res.potion1 = H.invCountOf(POTION)
    res.mpL, res.mpE, res.mpS, res.mpC =
      H.charMp(LOCKE), H.charMp(EDGAR), H.charMp(SABIN), H.charMp(CELES)
    local standing = 1
    for _, c in ipairs({ LOCKE, EDGAR, SABIN, CELES }) do
      local hp, mx = H.charHp(c), H.charMaxHp(c)
      if not (hp > 0 and (H.charStatus1(c) & 0xC6) == 0 and hp > (mx >> 3)) then
        standing = 0
      end
    end
    res.standing1 = standing
    H.log(string.format("[lab] battle module gone at f%d (lost=%s)",
      H.frame, tostring(lost)))
  end),

  -- the win tail: page the recognition scene until $0060 (or the loss
  -- shows itself)
  (function()
    local giveUp, ph = 0, 0
    return H.driveUntil(function()
      if H.gameOverFired > 0 then lost = lost or "gameover"; return true end
      giveUp = giveUp + 1
      return sw(0x0060) == 1 or giveUp >= 3000
    end, 3200, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        ph = (ph + 1) % 8
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the _cc7937 tail flips $0060 (or the loss shows itself)")
  end)(),

  H.call(function()
    H.setPad({})
    local won = H.gameOverFired == 0 and lost == nil and sw(0x0060) == 1
    local reason = won and "win" or (lost or "verify-failed")
    local be = #res.seeds > 0 and string.format("$%02X", res.seeds[#res.seeds])
      or "none"
    local engphase = #res.phases > 0 and res.phases[#res.phases] or -1
    H.log(string.format(
      "[labx] break=%d breakframe=%s swaps=%d ifrhp=%d shvhp=%d "
      .. "ifrdown=%s shvdown=%s",
      sawBreak and 1 or 0, breakFrame and tostring(breakFrame) or "-", swaps,
      mhp(slots.I or 0), mhp(slots.S or 1),
      ideath and tostring(ideath) or "-", sdeath and tostring(sdeath) or "-"))
    H.log(string.format(
      "[result] lab=b70 strategy=%s seed=%d won=%d frames=%d bframes=%d "
      .. "deaths=%d fenix=%d tonic=%d potion=%d mp=%d,%d,%d,%d standing=%d "
      .. "attempts=1 be=%s phase=%d nseeds=%d level=%s reason=%s",
      STRATEGY, SEED, won and 1 or 0, H.frame - res.t0, res.bframes,
      res.deaths,
      res.fenix0 - (res.fenix1 or res.fenix0),
      res.tonic0 - (res.tonic1 or res.tonic0),
      res.potion0 - (res.potion1 or res.potion0),
      res.mpL or -1, res.mpE or -1, res.mpS or -1, res.mpC or -1,
      res.standing1 or 0, be, engphase, #res.seeds, partyLevels(), reason))
  end),
})
