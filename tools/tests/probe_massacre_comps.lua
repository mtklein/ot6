-- probe_massacre_comps.lua -- boot ultros-won-v1, flood 375 at O, and report
-- the compartment id of every warp source/dest, shortcut source/dest, and
-- slide source, to find how comp8/comp22 (the massacre-pocket approach) is
-- reached.  No @suite.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function walkable(x, y)
  local t = H.maptile(x, y)
  return (H.readByte(0x7E7600 + t) & 0x07) ~= 0x07
     and (H.readByte(0x7E7700 + t) & 0x0F) ~= 0
end

local PTS = {
  { 8, 44, "SAVE" }, { 2, 45, "->371" }, { 53, 62, "->371" }, { 53, 61, "land371" },
  { 48, 9, "->372(16,41)" }, { 42, 26, "->372(33,45)" }, { 52, 46, "->372(40,33)" },
  { 45, 41, "->372(51,17)" }, { 16, 8, "->372(40,20)" }, { 16, 9, "land372=POCKET" },
  { 45, 42, "land372(50,16)" }, { 51, 46, "land372(39,33)" }, { 43, 26, "land372(33,44)" },
  { 48, 10, "land372(15,40)" }, { 60, 16, "->373" }, { 59, 16, "land373(16,23)" },
  { 42, 62, "land373(25,15)" }, { 32, 50, "->373(17,9)" }, { 33, 50, "land373(18,9)" },
  { 42, 63, "->373(24,15)" }, { 36, 41, "->374" }, { 36, 42, "land374" },
  { 15, 17, "MASSACRE" }, { 15, 16, "#125save" },
  -- shortcut sources ($0097-gated retile+teleport) and their teleport dests
  { 11, 51, "SC-src->(39,51)" }, { 39, 51, "SC-dst" },
  { 12, 46, "SC-src->(39,46)" }, { 39, 46, "SC-dst" },
  { 17, 49, "SC-src->(44,49)" }, { 44, 49, "SC-dst" },
  -- slide sources (one-way DOWN drops)
  { 47, 53, "SLIDE-src" }, { 39, 54, "SLIDE-src" }, { 36, 53, "SLIDE-src" },
}

H.run({ maxFrames = 200000, allowGameOver = true }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  (function() local cnt = 0
    return H.waitUntil(function()
      local ok = map() == 375 and H.tileAligned() and bright() >= 15
      cnt = ok and cnt + 1 or 0
      return cnt >= 10
    end, 4000, "cold Continue to 375", 10)
  end)(),
  H.waitFrames(60),
  H.call(function()
    local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
    local comp, cid = {}, 0
    local function key(x, y) return y * 256 + x end
    for sy = 0, ym do for sx = 0, xm do
      if walkable(sx, sy) and not comp[key(sx, sy)] then
        cid = cid + 1
        local st = { { sx, sy } }; comp[key(sx, sy)] = cid
        while #st > 0 do
          local n = table.remove(st)
          for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nx, ny = n[1] + d[1], n[2] + d[2]
            if nx >= 0 and nx <= xm and ny >= 0 and ny <= ym
               and walkable(nx, ny) and not comp[key(nx, ny)] then
              comp[key(nx, ny)] = cid; st[#st + 1] = { nx, ny }
            end
          end
        end
      end
    end end
    H.log(string.format("[cmp] %d comps", cid))
    for _, p in ipairs(PTS) do
      H.log(string.format("[cmp] (%2d,%2d) %-18s walk=%s comp=%s", p[1], p[2],
        p[3], tostring(walkable(p[1], p[2])), tostring(comp[key(p[1], p[2])])))
    end
  end),
  H.logStep(function() return "comp dump done" end),
})
