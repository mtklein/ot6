-- @suite
-- battle_mpcost.lua -- v0.4 "every ability costs MP": the OT6_MP_COSTS A/B.
--
-- ONE self-detecting instrument, run on BOTH builds (this is the whole A/B the
-- task asks for -- the same technique the fix_checksum rewrite used, lifted
-- from bytes to behavior):
--   * on the shipped, flag-OFF ROM (build/ot6.sfc, the suite's default) the
--     cost table is ABSENT from bank F0 -- none of the machinery is assembled,
--     the ROM is byte-identical to the pre-feature baseline (94cc426...) -- so
--     the test asserts the verb is FREE (vanilla behavior). This is the
--     negative control: the identical Bushido tech charges nothing.
--   * on the flag-ON variant (build/ot6-mpcosts.sfc, built by `make -C ff6
--     ff6-en-mp`, handed here via OT6_ROM) the table is present with kits.md's
--     numbers, and the test asserts the CHARGE and the insufficient-mp REFUSAL.
--
-- The mechanism under test: vanilla's GetMPCost prices only magic/lore/summon/
-- x-magic; Blitz/Bushido/Tools fall through it at 0, so the universal charge
-- at CalcAttackEffect ($3a4c subtract, insufficient-mp fizzle) never fires for
-- them. Ot6AbilityCost (ot6.asm) swaps that 0 for the kit price keyed by the
-- id already in $3a7b. Charge AND refusal are both already universal -- only
-- the menu grey-out/display is magic-specific, which is the menu-bank work
-- this flag waits on (docs/design/mp-economy.md).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN = 0x2020
local ST_BUSHIDO = 0x37

local PARTY = { 0, 1, 2 }
local GUARDS = { 2, 3 }                  -- monster slots -> entity 8+slot*2
local OT6_SLASH = 0x01
local FLURRY = 3                          -- tech index; attack id $55+3 = $58
local FLURRY_COST = 4                     -- Ot6AbilityCostTbl: $58 -> 4
local GUARD_HP = 0xF000                   -- pinned high so a hit never kills

local function CURMP(s) return 0x3C08 + s * 2 end
local function MAXMP(s) return 0x3C30 + s * 2 end
local function CURHP(s) return 0x3BF4 + s * 2 end
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function TM(s)  return 0x3E88 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end
local function ST3(e) return 0x3EF8 + e end
local function mp(s)  return H.readWord(CURMP(s)) end
local function level() return H.readByte(0x7B82) // 32 end
local function inWindow() return H.readByte(MSTATE) == ST_BUSHIDO end
local function guardHp()
  local t = 0
  for _, s in ipairs(GUARDS) do t = t + H.readWord(MHP(s)) end
  return t
end

local mode                               -- "on" (charges) | "off" (free)
-- Both scenarios use a natural FIRST turn from the opening ATB wave: all three
-- slots fill together, so after the charge actor acts the refusal actor's menu
-- is already queued (no ATB refill needed -- this fixture does not refill a
-- spent actor promptly, which is why we never reuse one). No parking: an
-- un-driven character just waits at its menu, it never auto-acts, so leaving
-- the others un-driven is enough isolation. `active` is the slot being pinned.
local active, chargeSlot, refuseSlot
local ceiling = FLURRY                    -- techs known-1: clamp the 2-bp band to Flurry
local pinPend = 2                         -- 2 bp -> Flurry band
local casterMp = 50                       -- re-pinned each frame until a latch
local pinCaster = true
local spells = {}                         -- attack ids seen at $3410 (cleared per scenario)

local function pinCyan()
  H.writeWord(KNOWN, ceiling)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x02)                 -- CHAR::CYAN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek (fixture is Magitek)
    H.writeByte(0x202E + s * 12, 0x07)                -- Bushido, alone
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)  -- SWDTECH ok
    H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
    H.writeWord(CURHP(s), 999)                         -- nobody dies on the bench
  end
  if active then
    H.writeByte(0x3E9C + active * 2, 5)                -- full bp bank
    H.writeByte(0x3E9D + active * 2, pinPend)          -- pending boost
    if pinCaster then
      H.writeWord(MAXMP(active), 99)
      H.writeWord(CURMP(active), casterMp)             -- the scenario's MP
    end
  end
end

local function pinGuards()
  for _, s in ipairs(GUARDS) do
    H.writeByte(WKE(s), 0)                -- class chips only (no element x2)
    H.writeByte(WKC(s), OT6_SLASH)        -- slashing-weak -> bushido chips
    H.writeByte(TM(s), 0)                 -- never broken
    local st3 = ST3(8 + s * 2)
    H.writeByte(st3, H.readByte(st3) | 0x10)   -- stopped: nothing contests
    H.writeWord(MHP(s), GUARD_HP)         -- survives, so damage is measurable
    H.writeByte(SH(s), 8)
  end
end

local function pin() pinCyan(); pinGuards() end

-- open the swdtech window, settle the boost band onto the wanted tech, latch
-- it, run it to $3410. clears the spell log first so each scenario waits for
-- ITS OWN execution. techIdx picks the tech (0=Fang no-boost, 3=Flurry@2bp).
local function latchTech(tag, techIdx, pend, ceil)
  local attackId = 0x55 + techIdx
  return H.repeatN(1, {
    H.call(function() spells = {}; pinPend, ceiling = pend, ceil; pin() end),
    H.driveUntil(inWindow, 1500, {
      H.call(function() pin(); H.setPad({ "a" }) end),
      H.waitFrames(2),
      H.call(function() H.setPad({}) end),
      H.waitFrames(14),
    }, tag .. ": swdtech window opens"),
    H.driveUntil(function() return inWindow() and level() == techIdx end, 600, {
      H.call(pin), H.waitFrames(2),
    }, tag .. ": boost band settles on the tech"),
    H.driveUntil(function() return not inWindow() end, 900, {
      H.call(function() pin(); H.setPad({ "a" }) end),
      H.waitFrames(2),
      H.call(function() H.setPad({}) end),
      H.waitFrames(14),
    }, tag .. ": window closes on a latch"),
    H.call(function() pinCaster = false end),          -- charge now observable
    H.driveUntil(function()
      for _, v in ipairs(spells) do if v == attackId then return true end end
      return false
    end, 12000, {
      H.call(function()
        pin()
        if H.readByte(MENU) ~= 0 and not inWindow() then H.setPad({ "a" }) end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(16),
    }, tag .. ": the tech reaches $3410"),
    H.waitFrames(90),                     -- let the charge + damage settle
  })
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.call(function()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
    pin()                                 -- install Cyan / clear magitek early
  end),

  -- ------------------------------------------------ 1. detect build + table --
  H.call(function()
    -- snesPrgRom is indexed by ROM FILE offset (HiROM: SNES $F0xxxx = file
    -- $30xxxx), the convention glyphCanary scans on.
    local sig = { 0x5d, 0x02, 0x5e, 0x05, 0x5f, 0x07 }   -- Pummel/AuraBolt/Suplex
    local base
    for a = 0x300000, 0x30FFF0 do
      local ok = true
      for i, b in ipairs(sig) do
        if H.readRomByte(a + i - 1) ~= b then ok = false break end
      end
      if ok then base = a break end
    end
    if not base then
      mode = "off"
      H.log("OFF build: Ot6AbilityCostTbl absent from bank F0 (dormant)")
      return
    end
    mode = "on"
    local cost, a = {}, base
    while H.readRomByte(a) ~= 0xFF and a < base + 0x200 do
      cost[H.readRomByte(a)] = H.readRomByte(a + 1)
      a = a + 2
    end
    local want = {                        -- kits.md's authored numbers
      [0x5d] = 2,  [0x64] = 30,           -- Blitz:   Pummel, Bum Rush
      [0x55] = 1,  [0x58] = 4, [0x5c] = 8, -- Bushido: Fang, Flurry, Oblivion
      [0xaa] = 4,  [0xa8] = 16, [0xa6] = 18, -- Tools:  AutoCrossbow, Drill, Chain Saw
    }
    for id, c in pairs(want) do
      H.assertEq(cost[id], c, string.format("cost table: id $%02x costs %d", id, c))
    end
    H.log("ON build: cost table verified for Blitz + Bushido + Tools")
  end),

  -- ------------------------------------ 2. CHARGE (ON) / FREE (OFF, control) --
  -- The charge actor is whoever comes up first in the opening wave.
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pin), H.waitFrames(1),
  }, "the opening wave's first menu"),
  H.call(function()
    chargeSlot = H.readByte(ACTOR)
    active, casterMp, pinCaster = chargeSlot, 50, true
    pin()
    H.log("charge actor = slot " .. chargeSlot)
  end),
  latchTech("affordable", FLURRY, 2, FLURRY),   -- Flurry: 2 bp, ceiling clamps to it
  H.call(function()
    local left, dmg = mp(chargeSlot), (GUARD_HP * #GUARDS) - guardHp()
    H.log(string.format("affordable flurry: MP 50 -> %d, guard damage %d", left, dmg))
    H.assertEq(dmg > 0, true, "the tech landed its hit (both builds)")
    if mode == "on" then
      H.assertEq(left, 50 - FLURRY_COST, "ON: flurry charged exactly its table cost (4)")
    else
      H.assertEq(left, 50, "OFF: flurry is free -- vanilla behavior, the negative control")
    end
    H.screenshot("mpcost_" .. mode .. "_affordable")
  end),

  -- ------------------------------------------------- 3. REFUSAL (ON only) --
  -- The insufficient-mp path is vanilla's own; on the OFF build the tech is
  -- free so there is nothing to refuse -- run this half only under the flag.
  -- The refusal actor is the NEXT of the opening wave (a different, still-full
  -- slot); Fang (tech 0, cost 1, no boost), MP 0 < 1 fizzles.
  H.cond(function() return mode == "on" end, {
    H.driveUntil(function()
      return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= chargeSlot
             and not inWindow()
    end, 8000, { H.call(pin), H.waitFrames(2) }, "a second actor comes up"),
    H.call(function()
      refuseSlot = H.readByte(ACTOR)
      active, casterMp, pinCaster = refuseSlot, 0, true
      pin()
      H.log("refuse actor = slot " .. refuseSlot)
    end),
    latchTech("unaffordable", 0, 0, 7),
    H.call(function()
      local left, dmg = mp(refuseSlot), (GUARD_HP * #GUARDS) - guardHp()
      H.log(string.format("unaffordable fang: MP stayed %d, guard damage %d", left, dmg))
      H.assertEq(left, 0, "ON: too little MP is REFUSED -- MP not driven negative")
      H.assertEq(dmg, 0, "ON: and the refused tech dealt no damage (fizzled)")
      H.screenshot("mpcost_on_refused")
    end),
  }, {}),

  H.logStep(function() return "mpcost A/B complete in " .. mode .. " mode" end),
})
