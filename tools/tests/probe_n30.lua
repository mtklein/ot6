-- probe_n30.lua -- census inside map 30 (Narshe interiors) from
-- kefka_won's {60,37}: which town doors can BFS reach, and is the front
-- door's blocker NPC still on duty post-battle?
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local TARGETS = {
  { 55, 35, "front door" }, { 55, 36, "front door S" }, { 54, 35, "front W" },
  { 56, 35, "front E" }, { 55, 34, "front N" },
  { 80, 36, "door 20(32,18)" }, { 79, 36, "its W" }, { 80, 35, "its N" },
  { 110, 26, "door 20(18,24)" }, { 79, 18, "door 20(52,39)" },
  { 67, 26, "corridor exit" },
}

H.run({ maxFrames = 20000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/kefka_won.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[census30] from (%d,%d)", H.fieldX(), H.fieldY()))
    for _, t in ipairs(TARGETS) do
      local p = H.bfsPath(t[1], t[2])
      local ob = H.readByte(0x7E2000 + (t[2] & 0xFF) * 256 + (t[1] & 0xFF))
      H.log(string.format("  (%d,%d) %-16s %s  obj=%s", t[1], t[2], t[3],
        p and ("ok " .. #p) or "no", (ob & 0x80) == 0 and "OCCUPIED" or "free"))
    end
  end),

  -- through the front door and census the town side
  H.navTo(55, 35, { arrive = function() return (H.mapId() & 0x1ff) == 20 end,
                    maxFrames = 6000 }),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned()
       and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 1200, "streets bright", 5),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[census20] from (%d,%d)", H.fieldX(), H.fieldY()))
    for _, t in ipairs({ { 38, 61, "south gate" }, { 38, 62, "exit row" },
        { 41, 36, "door 28" }, { 22, 44, "door 41b" }, { 33, 54, "door 104" },
        { 52, 37, "door 30a" }, { 32, 30, "door 24" }, { 29, 25, "door 27" },
        { 18, 22, "door 30b" }, { 32, 16, "door 30c" }, { 41, 22, "door 26" },
        { 43, 11, "door 25a" }, { 46, 10, "door 25b" }, { 49, 12, "door 30d" },
        { 15, 56, "door 41a" }, { 10, 36, "door 48" }, { 26, 8, "door 50" },
        { 48, 13, "S of us" }, { 50, 15, "SE of us" }, { 44, 15, "W of us" },
      }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("  (%d,%d) %-12s %s", t[1], t[2], t[3],
        p and ("ok " .. #p) or "no"))
    end
  end),
})
