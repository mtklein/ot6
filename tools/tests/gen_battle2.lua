-- gen_battle2: win fight 1, walk to fight 2 (mixed formation), mint a
-- doorstep2 state and audit clean 16x16 sprite anchors THERE.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local function auditAnchors(tag)
  local vr = emu.memType.snesVideoRam
  local blank = {}
  for t = 0, 0x1FF do
    local base
    if t < 0x100 then base = (0x2000 + t * 16) * 2
    else base = (0x3000 + (t - 0x100) * 16) * 2 end
    local z = true
    for b = 0, 63 do
      if emu.read(base + b, vr) ~= 0 then z = false break end
    end
    blank[t] = z
  end
  local so = emu.memType.snesSpriteRam
  local ref = {}
  for i = 0, 127 do
    local t = emu.read(i*4+2, so)
    local a = emu.read(i*4+3, so)
    local full = t + ((a & 1) * 256)
    ref[full] = true; ref[full+1] = true; ref[full+16] = true; ref[full+17] = true
  end
  local out = {}
  for t = 0, 0x1EE do
    local ok = (t % 16) < 15
    for _, q in ipairs({t, t+1, t+16, t+17}) do
      if not blank[q] or ref[q] then ok = false end
    end
    if ok then out[#out+1] = string.format("%03X", t) end
  end
  H.log(tag .. " clean anchors: " .. table.concat(out, " "))
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle 1 load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 1 active", 30),
  H.waitFrames(150),
  H.call(function()
    H.writeWord(0x3C00, 1)   -- guards at 1 hp: first beam ends it
    H.writeWord(0x3C02, 1)
  end),
  -- win fight 1: mash A (beams) until no monsters alive, then mash through victory
  H.driveUntil(function()
    local dead = H.readWord(0x3C00) == 0 and H.readWord(0x3C02) == 0
    return dead or not H.battleLoadStarted()   -- or victory already tore down
  end, 24000, {
    H.pressButtons({ "a" }, 6), H.waitFrames(30),
    H.pressButtons({ "a" }, 6), H.waitFrames(30),
    H.pressButtons({ "a" }, 6), H.waitFrames(600),
  }, "fight 1 won"),
  H.driveUntil(function()
    return not H.battleLoadStarted()
  end, 9000, { H.pressButtons({ "a" }, 6), H.waitFrames(24) }, "back to field"),
  H.waitFrames(60),
  H.saveState("battle2_doorstep.mss"),
  H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle 2 load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 2 active", 30),
  H.waitFrames(180),
  H.call(function()
    H.screenshot("fight2")
    local ids = H.monsterIds()
    H.log(string.format("fight2 monster ids: %04X %04X %04X %04X %04X %04X",
      ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]))
    auditAnchors("fight2")
  end),
})
