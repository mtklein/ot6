-- @manual
-- probe_nikeah_town2.lua -- why gen_sabin_trench's Nikeah stop read no path
-- from the town's south entrance (169 (14,61)) to the counter on the
-- library-fighter dive (#176; potion-route sabin_done attempt 1: "nav: no
-- path (14,61)->(24,40)" for 20 retries after a 400-frame settle).  Boots
-- the _scratch_nikeah169 state that attempt emitted on arrival and reports,
-- every 100 frames, the party tile and z, the four step checks out of it,
-- and bfs to the counter's talk tile (24,41).
local H = dofile("tools/tests/lib/ot6.lua")

local function report(tag)
  local x, y = H.fieldX(), H.fieldY()
  local steps = {}
  for _, d in ipairs({ "up", "down", "left", "right" }) do
    steps[#steps + 1] = d .. "=" .. tostring(H.canStep(x, y, d))
  end
  local q = H.bfsPath(24, 41)
  local nearest
  for r = 1, 12 do
    local p = H.bfsPath(x, y - r)
    if not p then nearest = r; break end
  end
  H.log(string.format("[probe] %s f%d (%d,%d) z=%d ctl=%s %s bfs(24,41)=%s first-unreachable-north=+%s",
    tag, H.frame, x, y, H.readByte(0x00b2) & 3, tostring(H.hasControl()),
    table.concat(steps, " "), q and #q or "none", tostring(nearest)))
end

local steps = { H.loadState("build/states/_scratch_nikeah169.mss.lua") }
for i = 0, 10 do
  steps[#steps + 1] = H.call(function() report("+" .. (i * 100)) end)
  steps[#steps + 1] = H.waitFrames(100)
end
-- then one held step north and ask again
steps[#steps + 1] = H.navTo(14, 60, { maxFrames = 600 })
steps[#steps + 1] = H.waitFrames(30)
steps[#steps + 1] = H.call(function() report("after one step north") end)
H.run({ maxFrames = 6000 }, steps)
