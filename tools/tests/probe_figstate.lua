-- probe_figstate.lua -- inspect the figaro_doorstep fixture: gil,
-- inventory, roster/levels, and the switch states the castle chain
-- reads ($0004/$0005/$0006/$01F0/$01F8, NPC switches $0308/$0311/
-- $0313/$0315).  Read-only reconnaissance for gen_edgar.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/figaro_doorstep.mss.lua"

local function sw(id)                       -- event switch -> bit
  local byte = H.readByte(0x1e80 + math.floor(id / 8))
  return (byte >> (id % 8)) & 1
end

H.run({ maxFrames = 2000 }, {
  H.loadState(DOOR),
  H.waitFrames(20),
  H.call(function()
    H.log(string.format("map=%d pos=(%d,%d)", H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
    local gil = H.readByte(0x1860) + H.readByte(0x1861) * 256 + H.readByte(0x1862) * 65536
    H.log(string.format("gil = %d", gil))
    -- roster: char blocks $1600+37n, party byte $1850+n
    for c = 0, 5 do
      local base = 0x1600 + 37 * c
      local pb = H.readByte(0x1850 + c)
      H.log(string.format("char %d: actor=%02X level=%d hp=%d/%d party=%d flags=%02X",
        c, H.readByte(base), H.readByte(base + 8),
        H.readWord(base + 9), H.readWord(base + 11) & 0x3fff, pb & 7, pb))
    end
    -- inventory: first 24 slots
    local inv = {}
    for i = 0, 23 do
      local id = H.readByte(0x1869 + i)
      local n = H.readByte(0x1969 + i)
      if id ~= 0xFF then inv[#inv + 1] = string.format("%02X x%d", id, n) end
    end
    H.log("inventory: " .. table.concat(inv, ", "))
    -- switches the chain reads
    for _, s in ipairs({ 0x0004, 0x0005, 0x0006, 0x01F0, 0x01F1, 0x01F8,
                         0x01B2, 0x0049, 0x004A, 0x00A4, 0x0048 }) do
      H.log(string.format("switch $%04X = %d", s, sw(s)))
    end
    -- npc-visible switches $03xx live at $1EE0
    for _, s in ipairs({ 0x0308, 0x0309, 0x030B, 0x030D, 0x030E, 0x030F,
                         0x0311, 0x0313, 0x0315, 0x0316, 0x031C, 0x0312 }) do
      local id = s - 0x0300
      local b = H.readByte(0x1ee0 + math.floor(id / 8))
      H.log(string.format("npc switch $%04X = %d", s, (b >> (id % 8)) & 1))
    end
    H.screenshot("figstate")
  end),
})
