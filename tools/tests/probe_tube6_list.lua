-- probe_tube6_list.lua -- what is actually IN the in-battle spell list at
-- $208e, record by record.
--
-- battle_esperstats.lua and battle_subjob.lua both read that list as "79
-- 4-byte records, id at +0" and treat a non-$ff id as a known spell id.  That
-- works for the signatures those files chose, but it cannot be right in
-- general: ValidateSpellList writes 54 SPELL records followed by 24 LORE
-- records, and a lore is stored with $8b subtracted (battle_main.asm:14345-51,
-- `cmp #$8b / sbc #$8b`), so a lore lands in the same 0..23 numeric range as a
-- low spell id.  A raw sweep therefore cannot distinguish spell $07 (Bolt 2)
-- from lore $92.
--
-- This matters for the tube-six build: "Maduin does not grant Bolt 2" is one
-- of the three broken-row fixes, and a first run of
-- battle_esperstats_tube6.lua saw id $07 present with NO esper equipped.  This
-- probe dumps every non-empty record with its slot number so the spell/lore
-- boundary can be read off directly instead of guessed at, in two states: no
-- esper, and Maduin (esper 6) equipped.
--
-- Not a suite member -- it is an instrument, run by hand.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local LIST0  = 0x208e
local ESPER0 = 0x161e
local MADUIN = 0x06

local function dump(tag)
  H.log(string.format("---- %s : $208e records (slot: id enable target mp) ----", tag))
  local shown = 0
  for n = 0, 78 do
    local id = H.readByte(LIST0 + n * 4)
    if id ~= 0xff then
      H.log(string.format("  slot %2d : id $%02x  +1 $%02x  +2 $%02x  +3 $%02x",
        n, id, H.readByte(LIST0 + n * 4 + 1),
        H.readByte(LIST0 + n * 4 + 2), H.readByte(LIST0 + n * 4 + 3)))
      shown = shown + 1
    end
  end
  H.log(string.format("---- %s : %d non-empty records ----", tag, shown))
  -- $3034 is the master "some character knows this" table ValidateSpellList
  -- builds before compacting (battle_main.asm:14320); $3084 maps spell -> slot.
  local m = {}
  for i = 0, 0x4d do
    local v = H.readByte(0x3034 + i)
    if v ~= 0xff then m[#m + 1] = string.format("%02x:%02x", i, v) end
  end
  H.log(string.format("[%s] $3034 non-ff: %s", tag, table.concat(m, " ")))
end

local function driveIn(tag, esper)
  local steps = { H.loadState(STATE), H.waitFrames(10) }
  steps[#steps + 1] = H.call(function()
    if esper then H.writeByte(ESPER0, esper) end
    H.log(string.format("[%s] char 0 esper = $%02x", tag, H.readByte(ESPER0)))
  end)
  steps[#steps + 1] = H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load (" .. tag .. ")")
  steps[#steps + 1] = H.waitUntil(function() return H.battleActive() end, 900,
    "battle active (" .. tag .. ")", 30)
  steps[#steps + 1] = H.waitFrames(120)
  steps[#steps + 1] = H.call(function() dump(tag) end)
  return steps
end

local all = { H.waitFrames(20) }
local function add(l) for _, s in ipairs(l) do all[#all + 1] = s end end
add(driveIn("base", nil))
add(driveIn("maduin", MADUIN))
add({ H.call(function() H.log("[probe] list dump complete") end) })

H.run({ maxFrames = 120000 }, all)
