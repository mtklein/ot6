-- probe_cells: which small-font cells are unreferenced by the BG3-based
-- tilemaps (menu page $7800-$7fff + field map from $897b) in this state?
-- Candidates for new OT6 glyph homes; $d0/$d1 are documented-free controls.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local candidates = { 0x68, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x74, 0x78,
                     0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0xd2, 0xd3,
                     0xd0, 0xd1 }   -- last two: known-free controls

local function scan(tag)
  local vr = emu.memType.snesVideoRam
  local counts = {}
  for _, c in ipairs(candidates) do counts[c] = 0 end
  local function region(base, words)
    for i = 0, words - 1 do
      local w = emu.readWord((base + i) * 2, vr)
      local t = w % 256
      if counts[t] then counts[t] = counts[t] + 1 end
    end
  end
  region(0x7800, 0x800)                       -- menu map, both pages
  local reg = H.readByte(0x897b)
  local fbase = (reg - (reg % 4)) * 256       -- bg3 field map base (words)
  region(fbase, 0x400)
  local parts = {}
  for _, c in ipairs(candidates) do
    if counts[c] > 0 then
      parts[#parts + 1] = string.format("%02x=%d", c, counts[c])
    end
  end
  H.log(tag .. " referenced: " .. (next(parts) and table.concat(parts, " ") or "(none)"))
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.call(function() scan("menu-open idle") end),
  -- drive one action so attack-effect art has a chance to touch maps
  H.driveUntil(function() return H.readByte(0x7bca) == 0 end, 4000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "action fired"),
  H.waitFrames(120),
  H.call(function() scan("post-action") end),
})
