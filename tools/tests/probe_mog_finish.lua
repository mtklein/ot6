-- probe_mog_finish.lua -- FINISH IT: wob_chase23C banks the party at
-- (38,2) on map 21 -- the TOP pocket, one step from the 22-crossing
-- (the $023C scene leaves the party there; the top->south link is a
-- one-way ledge drop, which is why every southbound chart read the top
-- as unreachable).  Cross to 22, climb to the cliff (23), fire the
-- standoff and ledge triggers, take MOG (#133 item 3).
local H = dofile("tools/tests/lib/ot6.lua")
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function mogIn()
  return (H.readByte(0x1850 + 10) & 0x07) ~= 0 or sw(0x2FA) == 1
end
local function stage(x, y, pred, tag)
  local aPhase, calm = 0, 0
  return {
    H.navTo(x, y, { maxFrames = 9000, playBattles = "flee", arrive = pred }),
    H.driveUntil(function()
      if not pred() then calm = 0; return false end
      return calm >= 60
    end, 8000, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then
          calm = 0
          H.setPad(aPhase < 4 and { "a" } or {})
        else
          if pred() and H.hasControl() then calm = calm + 1 end
          H.setPad({})
        end
      end),
    }, tag),
  }
end
local function edgeRow(cands, dir, destMap, tag)
  local tile = nil
  return {
    H.call(function()
      for _, c in ipairs(cands) do
        if H.bfsPath(c[1], c[2]) or (H.fieldX()==c[1] and H.fieldY()==c[2]) then
          tile = c
          H.log(string.format("[%s] approach (%d,%d)", tag, c[1], c[2]))
          return
        end
      end
      error(tag .. ": no approach")
    end),
    H.navTo(function() return tile[1] end, function() return tile[2] end,
      { maxFrames = 9000, playBattles = "flee",
        arrive = function() return mapIs(destMap) end }),
    H.driveUntil(function() return mapIs(destMap) end, 1500,
      { H.call(function() H.setPad({ [dir] = true }) end) }, tag),
    H.waitFrames(60),
    H.call(function()
      H.log(string.format("[%s] now map %d (%d,%d)", tag,
        H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
    end),
  }
end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
H.run({ maxFrames = 60000 }, flatten({
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    H.log(string.format("boot map=%d (%d,%d) 23C=%d", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY(), sw(0x23C)))
  end),
  -- THE BRIDGE IS A BATTLE: map 21's post-battle reload respawns the
  -- party at (38,2) -- the top pocket (measured: probe_right_turn idled
  -- into an encounter and came back at (38,2)).  Pace until an encounter
  -- fires, fight it out, and let the reload carry us up.
  (function()
    local battN, sawBattle, t = 0, false, 0
    local tactical = H.newFightDriver("mogbridge", { tactical = true,
      boost = true, items = true, healPercent = 55 })
    return H.driveUntil(function()
      return H.fieldY() <= 6 and H.hasControl()
    end, 20000, {
      H.call(function()
        t = t + 1
        battN = H.battleLoadStarted() and battN + 1 or 0
        if battN == 0 then tactical.idle() end
        if battN >= 3 then sawBattle = true; tactical.frame(); return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        -- pace a two-tile shuffle to roll the encounter counter
        H.setPad(t % 60 < 30 and { left = true } or { right = true })
      end),
    }, "the battle-reload bridge to the top pocket")
  end)(),
  H.call(function()
    H.log(string.format("after bridge: map=%d (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
  end),
  edgeRow({{35,2},{36,2},{34,2},{37,2},{35,3},{36,3},{35,4},{36,4}}, "up", 22, "21 -> 22"),
  edgeRow({{19,2},{18,2},{20,2},{21,2},{19,3},{18,3},{20,3}}, "up", 23, "22 -> 23"),
  H.call(function()
    H.screenshot("cliffs")
  end),
  stage(22, 20, function() return sw(0x23D) == 1 end, "the standoff [$023D]"),
  stage(8, 18, function() return sw(0x23F) == 1 end, "the ledge [$023F]"),
  H.navTo(9, 17, { maxFrames = 6000, playBattles = "flee" }),
  (function()
    local t, talked = 0, false
    return H.driveUntil(function() return mogIn() end, 9000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then talked = true end
        if talked then
          H.setPad(t % 24 < 3 and { "a" } or {})
        else
          H.setPad(t % 30 < 3 and { up = true, a = true } or { up = true })
        end
      end),
    }, "MOG joins")
  end)(),
  H.call(function()
    H.log("MOG RECRUITED")
    H.screenshot("mog_joined")
  end),
  H.saveState("wob_mog_done.mss"),
  H.logStep(function() return "done" end),
}))
