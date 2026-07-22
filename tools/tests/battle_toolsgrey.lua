-- @suite
-- battle_toolsgrey.lua -- v0.5 MP costs: the Tools window greys what Edgar
-- can't afford, the twin of battle_blitzgrey on the REAL tools window.
--
-- Same mechanism as Blitz (see battle_blitzgrey's header): Ot6AbilityGrey
-- (ot6.asm) compares each row's MP cost to the active caster's current MP
-- ($3c08,slot*2) and returns magic's $04/$00, which Ot6ToolRowDecorate OR's into
-- the column's $21 font byte -> $25 grey.  The tools decorator additionally lays
-- each column out [font][cost][name] so the one font command colors the price
-- and the name together; the just-landed price display had put the cost tile
-- ahead of the font, out of greying's reach.
--
-- Edgar is INSTALLED into the opening guard fight the way battle_toolslist pins
-- him: eight tools written into the battle item buffer ($2686, 5-byte records)
-- with the tool bit $40, and every party slot set to CHAR::EDGAR with an
-- all-Tools command list.  The twist: current MP ($3C08) is pinned LOW.
--
-- Tool prices (Ot6AbilityCostTbl) with MP pinned to 8:
--   AutoCrossbow $aa  4    affordable      Debilitator $a7 10   unaffordable
--   Flash        $a5  6    affordable      Air Anchor  $a9 14   unaffordable
--   NoiseBlaster $a3  6    affordable      Drill       $a8 16   unaffordable
--   BioBlaster   $a4  8    affordable      Chain Saw   $a6 18   unaffordable
--
-- What is asserted (attribute = the odd byte of a name tile's tilemap word,
-- $21 white / $25 grey):
--   1. AFFORDABLE STAYS WHITE.  Flash and AutoCrossbow render at $21.
--   2. UNAFFORDABLE GREYS.  Drill and Debilitator render at $25.
--   3. THE GREY IS THE DISABLED BIT.  grey - white == $04.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TOOLS = 0x30
local CMD_TOOLS = 0x09
local CMDTBL, CURMP = 0x202E, 0x3C08
local WHITE, GREY = 0x21, 0x25
local PARTY = { 0, 1, 2 }

-- id / cost / name, the eight tools in buffer order (battle_toolslist's set).
local TOOLS = {
  { 0xA3, 6,  "NoiseBlaster" },
  { 0xA4, 8,  "BioBlaster"   },
  { 0xA5, 6,  "Flash"        },
  { 0xA6, 18, "ChainSaw"     },
  { 0xA7, 10, "Debilitator"  },
  { 0xA8, 16, "Drill"        },
  { 0xA9, 14, "AirAnchor"    },
  { 0xAA, 4,  "AutoCrossbow" },
}
local MP_LOW = 8

local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
-- witnesses: two affordable (white) and two unaffordable (grey), all spaceless.
local NM = {
  Flash        = glyphs("Flash"),         -- cost 6  affordable
  AutoCrossbow = glyphs("AutoCrossbow"),  -- cost 4  affordable
  Debilitator  = glyphs("Debilitator"),   -- cost 10 unaffordable
  Drill        = glyphs("Drill"),          -- cost 16 unaffordable
}

local function pinEdgar()
  for i, t in ipairs(TOOLS) do
    local b = 0x2686 + (i - 1) * 5
    H.writeByte(b + 0, t[1])
    H.writeByte(b + 1, 0x40)               -- tool usage bit
    H.writeByte(b + 2, 0x00)
    H.writeByte(b + 3, 1)                   -- qty
  end
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x04)                 -- CHAR::EDGAR
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    for i = 0, 3 do H.writeByte(CMDTBL + s * 12 + i * 3, i == 0 and CMD_TOOLS or 0xFF) end
    H.writeWord(0x3BF4 + s * 2, 999)                  -- nobody dies mid-bench
    H.writeWord(CURMP + s * 2, MP_LOW)                -- current MP: the grey knob
    H.writeWord(0x3C30 + s * 2, 99)                   -- max MP stays high
  end
end

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end

local function attrOf(seq)
  local w = findName(seq)
  if not w then return nil end
  return emu.read(w * 2 + 1, emu.memType.snesVideoRam)
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),

  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinEdgar), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    H.log(string.format("edgar installed in slot %d, MP pinned to %d",
      H.readByte(ACTOR), MP_LOW))
  end),

  -- open the tools window (state $30).
  H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 900, {
    H.call(function() pinEdgar(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the tools list opens (state $30)"),
  H.waitFrames(8),                     -- let every row finish drawing
  H.call(function() H.screenshot("tools_grey_display") end),

  H.call(function()
    local aFl, aAc = attrOf(NM.Flash), attrOf(NM.AutoCrossbow)
    local aDr, aDe = attrOf(NM.Drill), attrOf(NM.Debilitator)
    local fmt = function(a) return a and string.format("$%02x", a) or "nil" end
    H.log(string.format("attr white? Flash=%s AutoCrossbow=%s | grey? Drill=%s Debilitator=%s",
      fmt(aFl), fmt(aAc), fmt(aDr), fmt(aDe)))
    H.assertEq(aFl, WHITE, "Flash (cost 6, MP 8) renders white -- affordable")
    H.assertEq(aAc, WHITE, "AutoCrossbow (cost 4, MP 8) renders white -- affordable")
    H.assertEq(aDr, GREY, "Drill (cost 16, MP 8) renders grey -- unaffordable")
    H.assertEq(aDe, GREY, "Debilitator (cost 10, MP 8) renders grey -- unaffordable")
    H.assertEq(aDr - aFl, 0x04, "grey - white == $04, magic's own disabled-bit delta")
    H.log("PASSED: the tools window greys every tool Edgar can't afford, only those")
  end),
})
