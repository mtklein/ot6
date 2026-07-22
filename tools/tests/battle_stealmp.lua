-- @suite
-- battle_stealmp.lua -- v0.5 "every ability costs MP": Steal (cmd $05) joins the
-- cost gate. The SAME self-detecting A/B as battle_mpcost.lua, aimed at the one
-- costed verb that test does NOT drive -- Locke's Steal -- proving the flat-cost
-- path added to Ot6AbilityCost (cmd $05 -> 2 MP, keyed on the command, NOT an
-- id-table row) charges and refuses through the universal machinery, and stays
-- free on the OFF baseline.
--
--   * ON  (build/ot6.sfc, the suite default): a Steal is QUEUED at cost 2
--     (Ot6AbilityCost's flat path), DEDUCTS 2 MP when it executes, and a caster
--     with 1 MP (< 2) is REFUSED -- the universal insufficient-mp fizzle
--     (CalcAttackEffect) skips the steal effect, so no item is taken and MP is
--     not driven negative.
--   * OFF (ff6/rom/ff6-en-nomp.sfc, handed in via OT6_ROM): Ot6AbilityCost is
--     not assembled, so cmd $05 keeps vanilla's 0 -- the identical Steal is
--     FREE (0 MP deducted). The refusal half has nothing to refuse and is
--     skipped. This is the negative control.
--
-- WHY A GUARANTEED (3-BP) STEAL. pend=3 makes the steal roll-free -- a certain
-- success that draws no RNG (battle_steal.lua) -- and DOES NOT change the MP
-- cost ("boost never raises MP cost", mp-economy.md; Ot6AbilityCost never reads
-- boost). So a granted item is a clean "the steal EXECUTED" signal, and a
-- MISSING item under populated slots is a clean "the steal was REFUSED" signal
-- -- no seed pinning needed. The doorstep is the Magitek opening, whose
-- target-select confines Steal to the party group; the charge is on the ATTACKER
-- (TargetEffect_52 is target-type-agnostic), so a party-entity target measures
-- the caster's MP fine -- the same soundness battle_steal.lua leans on.
--
-- THE COST IS READ AT THE SOURCE. Steal is an InitTarget_00 command, so unlike
-- Bushido it writes no attack id to $3410; instead a write watch on the mp-cost
-- queue ($3620,y, stored in CreateAction one instruction before $3a7a is
-- reread) filtered to command $05 captures EXACTLY what Ot6AbilityCost returned
-- for this Steal -- 2 on ON, 0 on OFF -- and the MP delta then confirms the
-- charge actually landed. That store fires for both the affordable and the
-- refused steal (the refusal is downstream, at execution), so it is also the
-- uniform "the action was created" signal both scenarios wait on.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR = 0x7BCA, 0x62CA
local PARTY = { 0, 1, 2 }
local MSLOTS = { 0, 1, 2, 3, 4, 5 }
local LOCKE = 0x01
local RARE, COMMON = 0xE0, 0xE1          -- distinct sentinel item ids
local NONE = 0xFF
local STEAL_COST = 2                     -- mp-economy.md: Steal "flat small | 2"

local function ENT_C(s) return s * 2 end
local function ENT_M(s) return 8 + s * 2 end
local function CURMP(s) return 0x3C08 + s * 2 end
local function MAXMP(s) return 0x3C30 + s * 2 end
local function stealRare(e)   return 0x3308 + e end
local function stealCommon(e) return 0x3309 + e end

local mode                               -- "on" (charges) | "off" (free)
local actor                              -- the acting slot (found at the first menu)
local queued, qcost, granted, execFrames -- per-steal observation, reset each drive

local function pinEnemies()
  for _, s in ipairs(MSLOTS) do
    H.writeWord(0x3BFC + s * 2, 0xF000)                          -- never dies
    H.writeByte(0x3EF8 + ENT_M(s), H.readByte(0x3EF8 + ENT_M(s)) | 0x10)  -- stopped:
    -- no enemy acts, so nothing touches the actor's HP/MP between drives.
  end
end

local function pinParty()
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, LOCKE)                           -- a real stealer
    H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) & 0xF7)  -- -magitek
    H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) & 0xCF)  -- -muddle/-berserk
    H.writeByte(0x202E + s * 12, 0x05)                           -- Steal, alone
    H.writeByte(0x2031 + s * 12, NONE)
    H.writeByte(0x2034 + s * 12, NONE)
    H.writeByte(0x2037 + s * 12, NONE)
    H.writeByte(0x3B18 + ENT_C(s), 50)                           -- level 50 both sides
    H.writeByte(stealRare(ENT_C(s)), RARE)                       -- BOTH slots populated:
    H.writeByte(stealCommon(ENT_C(s)), COMMON)                   --   an empty grant then
    H.writeWord(0x3BF4 + s * 2, 999)                             --   means REFUSED, never
  end                                                            --   a natural miss
  if actor then
    for _, s in ipairs(PARTY) do                                 -- only the actor acts
      if s ~= actor then
        H.writeByte(0x3EF8 + ENT_C(s), H.readByte(0x3EF8 + ENT_C(s)) | 0x10)
      end
    end
    H.writeByte(0x3E9C + actor * 2, 5)                           -- full bank
    H.writeByte(0x3E9D + actor * 2, 3)                           -- pend 3: guaranteed,
                                                                 --   roll-free, cost-neutral
    H.writeByte(0x3C45 + actor * 2, H.readByte(0x3C45 + actor * 2) & 0xFE)  -- no Sneak Ring
  end
end

-- NB: pin() deliberately NEVER writes MP -- the scenario sets it once, so the
-- charge (or its refusal) stays observable instead of being pinned back.
local function pin() pinEnemies(); pinParty() end

-- Drive ONE fresh steal at a given starting MP, observing the queued cost, the
-- MP delta, and whether an item was granted. Settle first (drain any prior
-- action, let the actor's ATB refill), pin MP once, then A (pick Steal) / A
-- (confirm the default target) until the action is QUEUED (the $3620 watch
-- fires), then hold while it executes (grant) or fizzles (a bounded wait, since
-- a refused steal grants nothing to signal on).
local function driveSteal(tag, startMp)
  return H.repeatN(1, {
    H.repeatN(30, { H.call(pin), H.waitFrames(1) }),
    H.call(function()
      queued, qcost, granted, execFrames = false, nil, nil, 0
      H.writeWord(MAXMP(actor), 99)
      H.writeWord(CURMP(actor), startMp)
    end),
    H.driveUntil(function()
      if queued then execFrames = execFrames + 1 end
      return queued and (granted ~= nil or execFrames >= 300)
    end, 12000, {
      H.call(function()
        pin()
        if not queued and H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
      end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(3),
      H.call(function()
        if not queued and H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
      end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(14),
    }, tag),
  })
end

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),

  -- ------------------------------------------------ 1. detect the build --
  H.call(function()
    -- The Blitz cost-table signature (Pummel/AuraBolt/Suplex) present in bank
    -- F0 IFF OT6_MP_COSTS was on -- the same probe battle_mpcost.lua uses.
    local sig = { 0x5d, 0x02, 0x5e, 0x05, 0x5f, 0x07 }
    local base
    for a = 0x300000, 0x30FFF0 do
      local ok = true
      for i, b in ipairs(sig) do
        if H.readRomByte(a + i - 1) ~= b then ok = false break end
      end
      if ok then base = a break end
    end
    mode = base and "on" or "off"
    if mode == "on" then
      H.log("ON build: cost table present -- Steal must charge " .. STEAL_COST .. " MP")
    else
      H.log("OFF build: cost table absent -- Steal must be FREE (the control)")
    end
  end),

  -- install Locke-with-Steal BEFORE any menu draws, then latch the acting slot.
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pin), H.waitFrames(1),
  }, "menu opens (Locke installed)"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("actor slot %d id=$%02x cmd0=$%02x", actor,
      H.readByte(0x3ED8 + actor * 2), H.readByte(0x202E + actor * 12)))
    -- mp-cost queue store (CreateAction), filtered to command $05: the exact
    -- cost Ot6AbilityCost handed back for this Steal. First $05 store per drive
    -- (queued latches, so a later cleanup clear can't overwrite it).
    emu.addMemoryCallback(function(_, v)
      if not queued and H.readByte(0x3A7A) == 0x05 then qcost = v; queued = true end
    end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
    -- obtained-item store ($32f4,attacker): a non-$ff item = the steal EXECUTED.
    emu.addMemoryCallback(function(_, v)
      if v ~= NONE then granted = v end
    end, emu.callbackType.write, 0x7E32F4, 0x7E32F4 + 18)
    pin()
  end),

  -- ---------------------------------- 2. CHARGE (ON) / FREE (OFF, control) --
  driveSteal("affordable steal (MP 50)", 50),
  H.call(function()
    local left = H.readWord(CURMP(actor))
    H.log(string.format("affordable steal: queued cost %s, MP 50 -> %d, granted %s",
      tostring(qcost), left, tostring(granted)))
    H.assertEq(granted ~= nil, true, "the steal executed and took an item (both builds)")
    if mode == "on" then
      H.assertEq(qcost, STEAL_COST, "ON: Ot6AbilityCost priced cmd $05 at 2 (flat path)")
      H.assertEq(left, 50 - STEAL_COST, "ON: the steal deducted exactly 2 MP")
    else
      H.assertEq(qcost, 0, "OFF: cmd $05 keeps vanilla's 0 (Ot6AbilityCost absent)")
      H.assertEq(left, 50, "OFF: the steal is FREE -- vanilla behavior, the control")
    end
    H.screenshot("stealmp_" .. mode .. "_affordable")
  end),

  -- ------------------------------------------------- 3. REFUSAL (ON only) --
  -- 1 MP < 2: CalcAttackEffect's universal insufficient-mp branch fizzles the
  -- action before the steal effect runs, so nothing is taken and MP is not
  -- driven negative. The OFF build charges 0, so there is nothing to refuse --
  -- run this half only under the flag (battle_mpcost.lua does the same).
  H.cond(function() return mode == "on" end, {
    driveSteal("unaffordable steal (MP 1)", 1),
    H.call(function()
      local left = H.readWord(CURMP(actor))
      H.log(string.format("unaffordable steal: queued cost %s, MP stayed %d, granted %s",
        tostring(qcost), left, tostring(granted)))
      H.assertEq(qcost, STEAL_COST, "ON: the gate still priced cmd $05 at 2")
      H.assertEq(granted, nil, "ON: too little MP is REFUSED -- no item taken (fizzled)")
      H.assertEq(left, 1, "ON: MP not driven negative -- the 1 MP is untouched")
      H.screenshot("stealmp_on_refused")
    end),
  }, {}),

  H.logStep(function() return "steal mpcost A/B complete in " .. mode .. " mode" end),
})
