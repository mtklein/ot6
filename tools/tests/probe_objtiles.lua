-- probe_objtiles: find OBJ tiles that are blank in VRAM and never
-- referenced by any OAM entry across battle frames (incl. an attack
-- animation). OBJ CHR base word $2000 (OBSEL $61), 4bpp, tiles 0-511.
-- A 16x16 sprite at tile T uses T,T+1,T+16,T+17; 32x32 uses a 4x4 block.
-- Candidates need a 6-wide x 2-tall free block for three arrow glyphs.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local referenced = {}
local n1, n2, iters

local function sampleOAM()
  for e = 0, 127 do
    local b2 = H.readByte(0x0300 + e*4 + 2)
    local b3 = H.readByte(0x0300 + e*4 + 3)
    local t = b2 | ((b3 & 1) << 8)
    -- conservative 32x32 footprint plus a column of margin
    for r = 0, 3 do
      for c = 0, 4 do
        referenced[(t + r*16 + c) % 512] = true
      end
    end
  end
end

local function report(tag)
  local vr = emu.memType.snesVideoRam
  local blank = {}
  for t = 0, 511 do
    local z = true
    for i = 0, 15 do
      if emu.readWord((0x2000 + t*16 + i) * 2, vr) ~= 0 then z = false; break end
    end
    blank[t] = z
  end
  -- find 6x2 blocks: T..T+5 and T+16..T+21 all blank and unreferenced
  local blocks = {}
  for t = 0, 511 - 21 do
    if t % 16 <= 10 then
      local ok = true
      for c = 0, 5 do
        local a, b = t + c, t + 16 + c
        if not blank[a] or referenced[a] or not blank[b] or referenced[b] then
          ok = false; break
        end
      end
      if ok then blocks[#blocks + 1] = t end
    end
  end
  local parts = {}
  for i = 1, math.min(#blocks, 24) do parts[#parts + 1] = string.format("%d", blocks[i]) end
  H.log(tag .. " free 6x2 blocks at tiles: " .. table.concat(parts, " "))
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
  -- sample oam during idle, then keep sampling through a full action
  H.waitUntil(function()
    sampleOAM(); n1 = (n1 or 0) + 1; return n1 >= 50
  end, 300, "idle oam sampled", 2),
  H.driveUntil(function()
    sampleOAM()
    iters = (iters or 0) + 1
    return iters >= 110          -- ~4400 frames of menus + actions
  end, 6000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() sampleOAM(); H.setPad({}) end),
    H.waitFrames(26),
  }, "action window sampled"),
  H.waitUntil(function()
    sampleOAM(); n2 = (n2 or 0) + 1; return n2 >= 80
  end, 400, "post-action sampled", 2),
  H.call(function() report("battle1") end),
})
