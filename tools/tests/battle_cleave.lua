-- @suite savestate=gau_joined slow
-- battle_cleave.lua -- Cyan learns Cleave at the Phantom Train farewell, and
-- his SwdTech window holds it on the 3-BP row from then on (#379).
--
-- Cleave is SwdTech tech 8 (attack $5c), Cyan's divine (kits.md "Divines":
-- its one gate is a full 3-BP boost).  Vanilla taught it at level 70; OT6
-- teaches it by story, as his wife and son board the Phantom Train (event
-- command $9e, give_bushido_tech, in the farewell script; BushidoLevelTbl's
-- eighth entry is 255, a level nobody reaches).  The techs between still come
-- by level, so from the farewell on he knows a run of techs 0..n by level and
-- Cleave beside it, and the window is his top two of the run on the 1- and
-- 2-BP rows and Cleave on the 3-BP row (Ot6BushidoPick).
--
-- Boots gau_joined -- the play past the farewell, on the Veldt with SABIN,
-- CYAN and GAU -- and reads, never writes:
--   1. the save: CYAN's learned set $1CF7 has Cleave (bit 7) at a level the
--      level table would not teach it (BushidoLevelTbl's own entry, read
--      from the ROM), and its other bits are exactly the run that table
--      gives his level;
--   2. the window, in the first Veldt battle the walk draws, opened through
--      the real menu on his first turn (H.kitBattle's peek): row 2 (3 BP) is
--      Cleave ($5c) at its price, rows 0 and 1 are his top two techs of the
--      run (blank where the run has only one), and row 3 is empty.
-- Old-ROM red (main's ROM and fixtures, where Cleave is still L70's):
-- build/attempts/wt/v028-kits/px13-lab/old/battle_cleave.out.  Mutant (Ot6BushidoPick
-- blind to Cleave): build/attempts/wt/v028-kits/px13-lab/mut/pick/battle_cleave.out.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local CYAN, CMD_SWDTECH, CLEAVE = 0x02, 0x07, 0x5C
local LEARNED, ITEMLIST = 0x1CF7, 0x4005
local TECH0 = 0x55                     -- Dispatch, the first tech's attack id
local LEVELTBL = H.sym("BushidoLevelTbl") & 0x3FFFFF

local function charLevel(id) return H.readByte(0x1600 + id * 37 + 8) end
local function popcount(v)
  local n = 0
  while v > 0 do n = n + (v & 1); v = v >> 1 end
  return n
end

local rows = nil
local learned, level = nil, nil

local function walkIntoEncounter(what)
  local flip = false
  return {
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 6000, what .. ": world control on the Veldt"),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({}) return end
        if not H.worldHasControl() then H.setPad({}) return end
        if not H.worldAligned() then return end
        flip = not flip
        H.setPad({ [flip and "left" or "right"] = true })
      end),
    }, what .. ": a Veldt encounter fires"),
    H.call(function() H.setPad({}) end),
  }
end

local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    learned, level = H.readByte(LEARNED), charLevel(CYAN)
    local cleaveLevel = H.readRomByte(LEVELTBL + 7)
    local byLevel = 0
    for i = 0, 6 do
      if H.readRomByte(LEVELTBL + i) <= level then byLevel = byLevel | (1 << i) end
    end
    H.log(string.format("[cleave] CYAN L%d, $1CF7=%02X; BushidoLevelTbl's Cleave entry %d; the run by level %02X",
      level, learned, cleaveLevel, byLevel))
    H.assertEq(learned & 0x80 ~= 0, true,
      "CYAN knows Cleave after the Phantom Train farewell (#379)")
    H.assertEq(level < cleaveLevel, true, string.format(
      "...at level %d, which the level table does not teach it at (%d): the farewell did", level, cleaveLevel))
    H.assertEq(learned & 0x7F, byLevel, string.format(
      "his other techs are the run the level table gives level %d (%02X)", level, byLevel))
  end),
}
for _, st in ipairs(walkIntoEncounter("the first Veldt battle")) do steps[#steps + 1] = st end
steps[#steps + 1] = H.kitBattle({ { who = CYAN, cmd = CMD_SWDTECH, boost = 1, peek = true } }, {
  untilPlanDone = true, idle = "defend",
  onList = function()
    rows = {}
    for r = 0, 3 do rows[r] = { id = H.readByte(ITEMLIST + r * 6), mp = H.readByte(ITEMLIST + r * 6 + 1) } end
  end })
steps[#steps + 1] = H.call(function()
  H.assertEq(rows ~= nil, true, "CYAN's SwdTech window was opened and read")
  local run = popcount(learned & 0x7F)
  local ceil = math.max(0, run - 1)
  local base = math.max(0, ceil - 1)
  local want0, want1 = TECH0 + base, TECH0 + math.min(base + 1, ceil)
  if want1 == want0 then want1 = 0xFF end
  H.log(string.format("[cleave] window rows: %02X(%d MP) %02X(%d MP) %02X(%d MP) %02X; want %02X %02X %02X",
    rows[0].id, rows[0].mp, rows[1].id, rows[1].mp, rows[2].id, rows[2].mp, rows[3].id, want0, want1, CLEAVE))
  H.assertEq(rows[2].id, CLEAVE, "row 2 (3 BP) is Cleave ($5c), learned at the farewell")
  H.assertEq(rows[2].mp, H.abilityCost(CLEAVE), "Cleave's row is drawn at its price")
  H.assertEq(rows[0].id, want0, "row 0 (1 BP) is the second best of the run he knows")
  H.assertEq(rows[1].id, want1, "row 1 (2 BP) is the best of the run he knows (blank if it is one tech)")
  H.assertEq(rows[3].id, 0xFF, "row 3 is empty")
  H.log("[cleave] PASS: Cleave learned at the farewell, on the 3-BP row beside his top two")
end)

H.run({ maxFrames = 120000 }, steps)
