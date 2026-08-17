-- probe_mrf262_chests.lua -- #84: stand-tile reachability for map 262's five
-- visible chests, from gen_mrf_263's two footholds: the mrf_chute boot
-- (10,45) and the post-conveyor landing (~(20,45), ridden via {11,45}).
local H = dofile("tools/tests/lib/ot6.lua")
local CHESTS = {
  { "Tincture",     83, 17, 27 },
  { "X-Potion",     84,  7, 44 },
  { "Remedy",       85, 25, 52 },
  { "Gold Shld",    86, 14, 53 },
  { "ThunderBlade", 87, 25, 44 },
}
local function census(tag)
  return H.call(function()
    H.log(string.format("[262 %s] at (%d,%d) map=%d", tag, H.fieldX(),
      H.fieldY(), H.mapId() & 0x1ff))
    for _, c in ipairs(CHESTS) do
      local what, bit, cx, cy = c[1], c[2], c[3], c[4]
      local cand = { { cx, cy + 1, "up" }, { cx - 1, cy, "right" },
                     { cx + 1, cy, "left" }, { cx, cy - 1, "down" } }
      for _, s in ipairs(cand) do
        local p = H.bfsPath(s[1], s[2])
        H.log(string.format("[stand %s] %s b%d stand (%d,%d) face %-5s: %s",
          tag, what, bit, s[1], s[2], s[3], p and (#p .. " steps") or "NO PATH"))
      end
    end
  end)
end
H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/mrf_chute.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl", 5),
  census("boot(10,45)"),
  -- ride the {11,45} conveyor exactly as gen_mrf_263 does: one step right,
  -- ungated scripted ride to {20,45}
  H.call(function() H.setPad({ right = true }) end),
  H.waitUntil(function()
    return H.fieldX() >= 20 and H.hasControl() and H.tileAligned()
  end, 2000, "the conveyor landed", 10),
  H.call(function() H.setPad({}) end),
  H.waitFrames(30),
  census("post-conveyor"),
})
