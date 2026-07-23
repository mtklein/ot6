-- @suite
-- battle_bushidoloadout.lua -- issue #8 Layer B: the per-save, field-configurable
-- Bushido loadout, asserted BATTLE-SIDE (the load-bearing correctness).
--
-- Storage lives at $1e1d (mode) + $1e1e..$1e21 (the four boost slots, tech
-- INDICES 0..7), unused space inside the checksummed working-save block.  The
-- read hook branches at the TOP of Ot6BushidoTech: mode 0 (all existing saves)
-- runs the vanilla moving window untouched; mode nonzero returns the stored
-- tech for THIS boost -- but only if it is still learned ($1cf7 bit set),
-- otherwise it falls back to the auto window for that slot.
--
-- What is asserted:
--   1. AUTO (mode 0) is byte-for-byte the Layer A window -- ceiling 4 packs
--      {1,2,3,4} into wItemList, exactly as battle_bushido asserts.
--   2. MANUAL enumerates the STORED techs, in the stored ORDER: a loadout of
--      {7,0,3,5} makes Ot6BushidoWindow pack $5c,$55,$58,$5a.
--   3. VALIDATION FALLBACK: a stored-but-unlearned slot ($1cf7 bit clear) falls
--      back to the auto tech for that boost rather than offering an uncastable
--      tech.
--   4. CONFIRM fires the STORED slot: confirming row r banks boost r ($3e9d=r)
--      and latches the stored tech for boost r into the action queue ($2bb0).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN, LEARNED, ITEMLIST = 0x2020, 0x1CF7, 0x4005
local LOADOUT = 0x1E1D                 -- [mode][slot0][slot1][slot2][slot3]
local ST_TOOLS, ST_BUSHIDO = 0x30, 0x37
local CMD_SWDTECH = 0x07

local PARTY = { 0, 1, 2 }
local GUARDS = { 2, 3 }
local function TM(s)  return 0x3E88 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end
local function ST3(e) return 0x3EF8 + e end

local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function inSub()   return H.readByte(MSTATE) == ST_TOOLS end
local function inNumer() return H.readByte(MSTATE) == ST_BUSHIDO end

local actor
local ceiling = 4
local learnedBits = 0xFF               -- $1cf7 mask (which techs are learned)
local mode = 0                         -- $1e1d
local slots = { 0, 0, 0, 0 }           -- $1e1e..$1e21
local bpbank = 5
local sawNumeral = false

local function pinCyan()
  H.writeWord(KNOWN, 0xFF00 | ceiling)
  H.writeByte(LEARNED, learnedBits)
  H.writeByte(LOADOUT, mode)
  for i = 1, 4 do H.writeByte(LOADOUT + i, slots[i]) end
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x02)                 -- CHAR::CYAN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    H.writeByte(0x202E + s * 12, CMD_SWDTECH)
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
    H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
    H.writeWord(0x3BF4 + s * 2, 999)
    H.writeWord(0x3C08 + s * 2, 99)
    H.writeWord(0x3C30 + s * 2, 99)
  end
  if actor then H.writeByte(0x3E9C + actor * 2, bpbank) end
end

local function pinGuards()
  for _, s in ipairs(GUARDS) do
    H.writeByte(TM(s), 0)
    H.writeByte(WKC(s), 0x01)
    local st3 = ST3(8 + s * 2)
    H.writeByte(st3, H.readByte(st3) | 0x10)
    H.writeWord(MHP(s), 0xF000)
  end
end
local function pin() pinCyan(); pinGuards() end

local function openSub(tag)
  return H.driveUntil(inSub, 900, {
    H.call(function()
      pin()
      if inNumer() then sawNumeral = true end
      H.setPad({ "a" })
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, tag or "the swdtech submenu opens (tools shell $30)")
end
local function closeSub()
  return H.driveUntil(function() return not inSub() end, 400, {
    H.call(function() pin(); H.setPad({ "b" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }, "the submenu closes back to the command window")
end

-- assert the packed window rows against an expected id list (nil id => $ff pad)
local function assertRows(want, tag)
  for r = 0, 3 do
    local id = H.readByte(ITEMLIST + r * 6)
    if want[r + 1] then
      H.assertEq(id, want[r + 1], string.format("%s: row %d id $%02x", tag, r, want[r + 1]))
    else
      H.assertEq(id, 0xFF, string.format("%s: row %d empty", tag, r))
    end
  end
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pin), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("cyan installed in slot %d", actor))
  end),

  -- 1. AUTO baseline (mode 0) -- ceiling 4 packs {1,2,3,4}, Layer A unchanged --
  H.call(function() ceiling, mode = 4, 0 end),
  openSub("auto: swdtech opens the tools-shell submenu"),
  H.waitFrames(6),
  H.call(function()
    H.assertEq(inSub(), true, "AUTO opened the tools-shell submenu")
    H.assertEq(sawNumeral, false, "the vanilla numeral gauge never opened")
    assertRows({ 0x56, 0x57, 0x58, 0x59 }, "auto ceiling 4")  -- $55+{1,2,3,4}
    H.log("AUTO (mode 0) window = {1,2,3,4} -- byte-for-byte Layer A")
  end),

  -- 2. MANUAL enumeration -- stored order {7,0,3,5} -> $5c,$55,$58,$5a --------
  closeSub(),
  H.call(function()
    ceiling, learnedBits = 7, 0xFF          -- all eight learned, 4 rows
    mode, slots = 1, { 7, 0, 3, 5 }
  end),
  openSub("manual: reopen with a stored loadout"),
  H.waitFrames(6),
  H.call(function()
    assertRows({ 0x5c, 0x55, 0x58, 0x5a }, "manual {7,0,3,5}")
    H.log("MANUAL enumerates the STORED techs in the STORED order")
  end),

  -- 3. VALIDATION FALLBACK -- slot0 = tech 2, but $1cf7 bit 2 is CLEAR ---------
  closeSub(),
  H.call(function()
    -- learned = everything except tech 2 (0b1111_1011); ceiling stays 7 so the
    -- auto fallback for boost 0 is base(4)+0 = tech 4 = id $59.
    ceiling, learnedBits = 7, 0xFB
    mode, slots = 1, { 2, 0, 3, 5 }
  end),
  openSub("manual: reopen with an unlearned stored slot0"),
  H.waitFrames(6),
  H.call(function()
    local row0 = H.readByte(ITEMLIST + 0 * 6)
    H.assertEq(row0, 0x59,
      "unlearned stored slot0 (tech 2) fell back to the auto window tech ($59)")
    assertRows({ 0x59, 0x55, 0x58, 0x5a }, "manual w/ fallback")
    H.log("VALIDATION: an unlearned stored slot falls back to auto; learned slots stand")
  end),

  -- 4. CONFIRM fires the STORED slot ------------------------------------------
  closeSub(),
  H.call(function()
    ceiling, learnedBits = 7, 0xFF
    mode, slots = 1, { 7, 0, 3, 5 }
    bpbank = 5
  end),
  openSub("manual: reopen to confirm a row"),
  H.waitFrames(4),
  H.call(function()
    local slot = actor
    H.writeByte(0x895F + slot, 0)      -- scroll
    H.writeByte(0x8963 + slot, 0)      -- column 0
    H.writeByte(0x8967 + slot, 2)      -- row 2 (boost 2 -> stored tech 3, nonzero)
    -- Ot6BushidoConfirm reads y = (w7e7b80 & 3) * 8 BEFORE it inc's $7b80, so
    -- snapshot that queue index now to read the tech it latches.
    _G.__preY = (H.readByte(0x7B80) & 0x03) * 8
    H.screenshot("bushido_loadout_manual")
  end),
  H.waitFrames(2),
  H.pressButtons({ "a" }, 4), H.waitFrames(10),
  H.call(function()
    H.assertEq(pend(actor), 2, "confirming row 2 banked boost 2 ($3e9d = 2)")
    -- $2bb0,y holds the latched tech INDEX (FixPlayerAttack adds +$55 later)
    local latched = H.readByte(0x2BB0 + _G.__preY)
    H.assertEq(latched, slots[3],
      "confirm latched the STORED tech for boost 2 (index " .. slots[3] .. ", not auto's 5)")
    H.log(string.format("CONFIRM: row 2 -> boost 2, latched stored tech index %d", latched))
    H.log("PASSED: loadout read hook enumerates/validates/confirms the stored slots")
  end),
})
