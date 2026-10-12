-- @suite
-- battle_swdtechclass.lua -- Cyan's SwdTech chip classes as built (#379):
-- Retort and Empowerer classless, Quadra Slice wind, the rest slashing
-- (the battle_breakgate shape: pure ROM bytes, no savestate).
--
-- kits.md "Cyan" carries the plan's chip column: Dispatch, Slash, Quadra
-- Slam, Stunner and Cleave slash; Retort is a counter stance and Empowerer a
-- drain, so neither chips ("—"); Quadra Slice is wind x4.  The ROM carries a
-- skill's class in Ot6SkillClassTbl (ot6_class.asm: (id, class) pairs,
-- $ff-ended; an absent id is classless and its element is its probe) and its
-- element in its MagicProp record (+$01; Quadra Slice's is battle_main.asm's
-- override 7).  Read from the built ROM through the two symbols:
--   1. each SwdTech's class entry is the plan's (absent for Retort,
--      Empowerer and Quadra Slice);
--   2. each SwdTech's record element is the plan's: wind ($10) for Quadra
--      Slice, none for the other seven.
-- Old-ROM red (main's ROM: all eight slashing, Quadra Slice elementless):
-- build/attempts/wt/v028-kits/.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, WIND = 0x01, 0x10
local MAGIC_REC = 14
local TECHS = {
  { 0x55, "Dispatch",     SLASH, 0 },
  { 0x56, "Retort",       nil,   0 },
  { 0x57, "Slash",        SLASH, 0 },
  { 0x58, "Quadra Slam",  SLASH, 0 },
  { 0x59, "Empowerer",    nil,   0 },
  { 0x5A, "Stunner",      SLASH, 0 },
  { 0x5B, "Quadra Slice", nil,   WIND },
  { 0x5C, "Cleave",       SLASH, 0 },
}

H.run({ maxFrames = 600 }, {
  H.waitFrames(30),
  H.call(function()
    local tbl = H.sym("Ot6SkillClassTbl") & 0x3FFFFF
    local prop = H.sym("MagicProp") & 0x3FFFFF
    local class = {}
    for x = 0, 126, 2 do
      local id = H.readRomByte(tbl + x)
      if id == 0xFF then break end
      class[id] = H.readRomByte(tbl + x + 1)
    end
    local fails = {}
    for _, t in ipairs(TECHS) do
      local id, name, wantClass, wantElem = t[1], t[2], t[3], t[4]
      local got = class[id]
      local elem = H.readRomByte(prop + id * MAGIC_REC + 1)
      H.log(string.format("[swdtech] $%02X %-12s class %s (want %s), element %02X (want %02X)", id, name,
        got and string.format("%02X", got) or "none", wantClass and string.format("%02X", wantClass) or "none",
        elem, wantElem))
      if got ~= wantClass then fails[#fails + 1] = name .. "'s class" end
      if elem ~= wantElem then fails[#fails + 1] = name .. "'s element" end
    end
    for _, f in ipairs(fails) do H.log("[swdtech] FAIL " .. f) end
    H.assertEq(#fails, 0, "every SwdTech chips on the plan's axis (kits.md's chip column)")
    H.log("[swdtech] PASS")
  end),
})
