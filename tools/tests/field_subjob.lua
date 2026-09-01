-- @suite savestate=n024_entry
-- field_subjob.lua -- an equipped esper grants its spells in the field Magic
-- list, not only in battle.
--
-- The n024_entry fixture owns KIRIN and has EDGAR at field-menu position 0.
-- He does not innately know Cure.  Both arms use real menu input:
--   A. without an esper, Cure is absent from Edgar's rendered field list;
--   B. equip Kirin through Skills -> Espers, then Cure is present and
--      castable, while Edgar's permanent learned byte remains untouched.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/n024_entry.mss.lua"

local EDGAR, KIRIN, CURE = 4, 17, 0x2D
local EBASE = 0x1600 + 37 * EDGAR
local LEARNED = 0x1A6E + 54 * EDGAR + CURE
local ZM, CUR = 0x26, 0x4B
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_MAGIC = 0x05, 0x06, 0x0A, 0x1A
local MAGIC_LIST, MAGIC_COLOUR = 0x9D89, 0x9E09

local function st() return H.readByte(ZM) end

local function openEdgarMagic(tag)
  return H.seqStep({
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, tag .. ": main menu"),
    H.waitFrames(20),
    H.driveUntil(function()
      return st() == ST_MAIN and H.readByte(CUR) == 1
    end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
      tag .. ": cursor on Skills"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300,
      tag .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function()
      return st() == ST_CHAR and H.readByte(CUR) == 0
    end, 600, { H.pressButtons({ "up" }, 2), H.waitFrames(10) },
      tag .. ": cursor on Edgar"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_SKILLS end, 300,
      tag .. ": skills submenu", 5),
    H.waitFrames(10),
    H.driveUntil(function()
      return st() == ST_SKILLS and H.readByte(CUR) == 1
    end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(8) },
      tag .. ": cursor on Magic"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_MAGIC end, 500,
      tag .. ": magic list", 5),
    H.waitFrames(120),
  })
end

local function magicIndexOf(spell)
  for i = 0, 0x35 do
    if H.readByte(MAGIC_LIST + i) == spell then return i end
  end
  return nil
end

H.run({ maxFrames = 30000 }, {
  -- A: the same character and list without a stone are the negative control.
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "field control A", 5),
  H.call(function()
    -- The fighting lineage's n024_entry arrives with stones worn (a
    -- played save should); the negative control needs Edgar bare, and
    -- the WHOLE party freed -- pass B hands Kirin to Edgar through the
    -- real menu, and the one-owner rule refuses a stone someone else
    -- wears (LOCKE arrives wearing Kirin here).  The grant reads the
    -- worn byte live, so clearing it IS the never-wore-it state.
    -- Declared in state_write_waivers.txt.
    for _, c in ipairs(H.partyMembers()) do
      local base = 0x1600 + 37 * c
      local worn = H.readByte(base + 0x1E)
      if worn ~= 0xFF then
        H.writeByte(base + 0x1E, 0xFF)
        H.log(string.format("char %d wore stone $%02X -> bared for the control",
          c, worn))
      end
    end
    H.assertEq(H.readByte(EBASE + 0x1E), 0xFF, "A: Edgar has no esper")
    H.assertEq(H.readByte(LEARNED) ~= 0xFF, true,
      "A: Edgar has not permanently learned Cure")
    H.assertEq(H.knowsSpell(EDGAR, CURE), false,
      "A: field planner does not invent Cure without a grant")
  end),
  openEdgarMagic("A no esper"),
  H.call(function()
    H.assertEq(magicIndexOf(CURE), nil,
      "A: Cure is absent from Edgar's rendered field Magic list")
  end),

  -- B: equip through the real UI, then reopen that same list.
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "field control B", 5),
  H.call(function()
    -- The reload restores the fixture's worn stones, so free them again:
    -- LOCKE arrives wearing Kirin, and the one-owner rule greys a stone
    -- someone else wears -- the menu drive below would complete its
    -- steps while the refused equip leaves Edgar's record bare.
    for _, c in ipairs(H.partyMembers()) do
      local base = 0x1600 + 37 * c
      local worn = H.readByte(base + 0x1E)
      if worn ~= 0xFF then
        H.writeByte(base + 0x1E, 0xFF)
        H.log(string.format("char %d wore stone $%02X -> freed for pass B",
          c, worn))
      end
    end
  end),
  H.equipEsper(0, KIRIN, { tag = "B equip Kirin on Edgar" }),
  H.call(function()
    H.assertEq(H.readByte(EBASE + 0x1E), KIRIN,
      "B: the real menu equipped Kirin on Edgar")
    H.assertEq(H.readByte(LEARNED) ~= 0xFF, true,
      "B: equipping Kirin did not teach Cure permanently")
    H.assertEq(H.knowsSpell(EDGAR, CURE), true,
      "B: field planner sees Kirin's live Cure grant")
  end),
  openEdgarMagic("B Kirin"),
  H.call(function()
    local i = magicIndexOf(CURE)
    H.assertEq(i ~= nil, true,
      "B: Kirin's Cure is present in Edgar's rendered field Magic list")
    H.assertEq(H.readByte(MAGIC_COLOUR + i), 0x20,
      "B: granted Cure is selectable, not a grey display-only row")
    H.screenshot("field_subjob_kirin_cure")
  end),
  H.logStep(function() return "field_subjob complete" end),
})
