-- @suite
-- battle_bushidoloadout.lua -- issue #8 Layer B: the per-save, field-configurable
-- Bushido loadout, asserted on the battle side.
--
-- Storage is a 16-bit little-endian word at $1e1d..$1e1e, unused space inside
-- the checksummed working-save block.  The four boost slots pack into 12 bits,
-- 3 bits each: slot0 = bits 0-2, slot1 = bits 3-5, slot2 = bits 6-8, slot3 =
-- bits 9-11 (top 4 bits unused = 0).  The read hook branches at the top of
-- Ot6BushidoTech: word 0 (every existing save, and the all-slot-0 degenerate
-- case) runs the vanilla moving window untouched; a nonzero word returns the
-- stored tech for that boost, but only if it is still learned ($1cf7 bit set),
-- otherwise it falls back to the auto window for that slot.
--
-- issue #38 refloored Bushido at 1 BP.  The stored format did not move: same
-- word, same four 3-bit fields, same AUTO sentinel, so every tracked SRAM
-- checkpoint (persistent_layout ot6-codex-o8-v1) still decodes.  Word slot 0
-- is now dead: menu row i and window row i both address word slot i+1, and no
-- code reads slot 0 back.  A loadout {-,7,0,3} therefore packs as
-- 7<<3 | 0<<6 | 3<<9 = $0638 and enumerates $5c,$55,$58 into rows 0/1/2, with
-- row 3 of the grid permanently $ff.  This test carries slot 0 as a written-
-- but-ignored field in order to check that it is ignored.
--
-- What is asserted:
--   1. AUTO (word 0) is byte-for-byte the Layer A window: ceiling 4 packs
--      {2,3,4} into wItemList, as battle_bushido asserts.
--   2. MANUAL enumerates the stored techs in the stored order: a loadout whose
--      slots 1/2/3 are {7,0,3} makes Ot6BushidoWindow pack $5c,$55,$58.
--   3. validation fallback: a stored-but-unlearned slot ($1cf7 bit clear) falls
--      back to the auto tech for that boost rather than offering an uncastable
--      tech.
--   4. confirm fires the stored slot: confirming row i banks boost i+1
--      ($3e9d=i+1) and latches the stored tech for word slot i+1 ($2bb0).
--   5. sentinel: the all-slot-0 word ($0000) is AUTO, not a manual {0,0,0,0};
--      the degenerate config is indistinguishable from auto by design.
--   6. slot 0 is ignored (#38): a word whose dead slot 0 holds a very
--      different tech still enumerates from slots 1..3 only.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN, LEARNED, ITEMLIST = 0x2020, 0x1CF7, 0x4005
local LOADOUT = 0x1E1D                 -- packed word (lo, hi): 3 bits per slot
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
-- word slots 0..3.  slots[1] is the dead slot 0 (#38); slots[2..4] are the
-- 1x/2x/3x tiers the menu and the battle window read.
local slots = { 0, 0, 0, 0 }
local bpbank = 5
local sawNumeral = false

-- pack the four 3-bit slot fields into the 16-bit loadout word.  {0,0,0,0} -> 0
-- (AUTO/sentinel); any nonzero result is MANUAL.
local function packWord()
  return slots[1] | (slots[2] << 3) | (slots[3] << 6) | (slots[4] << 9)
end

local function pinCyan()
  H.writeWord(KNOWN, 0xFF00 | ceiling)
  H.writeByte(LEARNED, learnedBits)
  local w = packWord()
  H.writeByte(LOADOUT, w & 0xFF)         -- word low
  H.writeByte(LOADOUT + 1, (w >> 8) & 0xFF)  -- word high
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

  -- 1. AUTO baseline (word 0): ceiling 4 packs {2,3,4}, Layer A unchanged -----
  H.call(function() ceiling, slots = 4, { 0, 0, 0, 0 } end),
  openSub("auto: swdtech opens the tools-shell submenu"),
  H.waitFrames(6),
  H.call(function()
    H.assertEq(inSub(), true, "AUTO opened the tools-shell submenu")
    H.assertEq(sawNumeral, false, "the vanilla numeral gauge never opened")
    assertRows({ 0x57, 0x58, 0x59 }, "auto ceiling 4")  -- $55+{2,3,4}
    H.log("AUTO (word 0) window = {2,3,4} at 1x/2x/3x -- byte-for-byte Layer A")
  end),

  -- 1b. sentinel: an all-slot-0 loadout packs to word $0000, which the hook
  -- must read as AUTO, not as a manual {0,0,0,0} (which would enumerate three
  -- copies of tech 0 = $55).  Ceiling 7 discriminates: auto gives {5,6,7} =
  -- $5a,$5b,$5c, whereas a mis-decoded manual would give $55,$55,$55. ---------
  closeSub(),
  H.call(function()
    ceiling, learnedBits = 7, 0xFF
    slots = { 0, 0, 0, 0 }                   -- packs $0000, the AUTO sentinel
  end),
  openSub("sentinel: reopen with the all-slot-0 word"),
  H.waitFrames(6),
  H.call(function()
    assertRows({ 0x5a, 0x5b, 0x5c }, "all-slot-0 word decodes to AUTO")
    H.log("SENTINEL: word $0000 (all slots tech 0) reads as AUTO, not manual {0,0,0,0}")
  end),

  -- 2. MANUAL enumeration: stored slots 1..3 {7,0,3} -> $5c,$55,$58 ----------
  closeSub(),
  H.call(function()
    ceiling, learnedBits = 7, 0xFF          -- all eight learned, 3 rows
    slots = { 0, 7, 0, 3 }                   -- packs $0638 (nonzero => MANUAL)
  end),
  openSub("manual: reopen with a stored loadout"),
  H.waitFrames(6),
  H.call(function()
    assertRows({ 0x5c, 0x55, 0x58 }, "manual slots1-3 {7,0,3}")
    H.log("MANUAL enumerates the STORED techs in the STORED order")
  end),

  -- 2b. #38: the dead slot 0 is never read.  Same three live slots, but slot 0
  -- now holds tech 5; if anything still decoded it, a row would move. --------
  closeSub(),
  H.call(function()
    ceiling, learnedBits = 7, 0xFF
    slots = { 5, 7, 0, 3 }                   -- slot 0 = 5: written, ignored
  end),
  openSub("manual: reopen with a junk value in the retired slot 0"),
  H.waitFrames(6),
  H.call(function()
    assertRows({ 0x5c, 0x55, 0x58 }, "slot 0 ignored")
    H.log("SLOT 0 RETIRED: a nonzero dead slot 0 changes nothing (#38)")
  end),

  -- 3. validation fallback: slot1 = tech 2, but $1cf7 bit 2 is clear ---------
  closeSub(),
  H.call(function()
    -- learned = everything except tech 2 (0b1111_1011); ceiling stays 7 so the
    -- auto fallback for boost 1 is base(5)+0 = tech 5 = id $5a.
    ceiling, learnedBits = 7, 0xFB
    slots = { 0, 2, 0, 3 }                   -- packs $0610 (nonzero => MANUAL)
  end),
  openSub("manual: reopen with an unlearned stored slot1"),
  H.waitFrames(6),
  H.call(function()
    local row0 = H.readByte(ITEMLIST + 0 * 6)
    H.assertEq(row0, 0x5a,
      "unlearned stored slot1 (tech 2) fell back to the auto window tech ($5a)")
    assertRows({ 0x5a, 0x55, 0x58 }, "manual w/ fallback")
    H.log("VALIDATION: an unlearned stored slot falls back to auto; learned slots stand")
  end),

  -- 4. confirm fires the stored slot ------------------------------------------
  closeSub(),
  H.call(function()
    ceiling, learnedBits = 7, 0xFF
    slots = { 0, 7, 0, 3 }
    bpbank = 5
  end),
  openSub("manual: reopen to confirm a row"),
  H.waitFrames(4),
  H.call(function()
    local slot = actor
    H.writeByte(0x895F + slot, 0)      -- scroll
    H.writeByte(0x8963 + slot, 0)      -- column 0
    H.writeByte(0x8967 + slot, 2)      -- row 2 (boost 3 -> word slot 3 = tech 3)
    -- Ot6BushidoConfirm reads y = (w7e7b80 & 3) * 8 before it inc's $7b80, so
    -- snapshot that queue index now to read the tech it latches.
    _G.__preY = (H.readByte(0x7B80) & 0x03) * 8
    H.screenshot("bushido_loadout_manual")
  end),
  H.waitFrames(2),
  H.pressButtons({ "a" }, 4), H.waitFrames(10),
  H.call(function()
    H.assertEq(pend(actor), 3, "confirming row 2 banked boost 3 ($3e9d = 3)")
    -- $2bb0,y holds the latched tech index (FixPlayerAttack adds +$55 later)
    local latched = H.readByte(0x2BB0 + _G.__preY)
    H.assertEq(latched, slots[4],
      "confirm latched the STORED tech for boost 3 (index " .. slots[4] .. ", not auto's 7)")
    H.log(string.format("CONFIRM: row 2 -> boost 3, latched stored tech index %d", latched))
    H.log("PASSED: loadout read hook enumerates/validates/confirms the stored slots")
  end),
})
