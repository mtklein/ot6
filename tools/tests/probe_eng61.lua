-- probe_eng61.lua -- exits census from the engine-room platform (6,34).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
H.run({ maxFrames = 9000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/figaro_submerged.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[eng61] map=%d at (%d,%d)",
      H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
    for _, t in ipairs({ {11,32},{10,32},{11,33},{10,33},{9,33},{10,34},
                         {12,32},{11,31},{2,37},{3,37},{2,36},{3,36},
                         {27,31},{9,32},{8,33} }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("  (%d,%d) %s", t[1], t[2],
        p and ("ok " .. #p) or "no"))
    end
  end),
})
