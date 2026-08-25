-- probe_fc_atma5.lua -- #132 segment 3, the AtmaWeapon fight itself.
-- Boots fc_atma_door.mss (party at (60,17), Atma's NPC at (60,15),
-- banked by probe_fc_atma4).  The talk only fires on the clean gesture
-- -- tap up to face, release, tap A while stationary -- never on held
-- direction + A (probe_fc_atma4 measured both).  The post-win event
-- _cada30 clears switch $035F ($1EE0 region, byte $1EEB bit 7), which
-- makes an end condition no random encounter can fake.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local FA = H.newFightDriver("atma", { tactical = true, boost = true, bank = 3,
  items = true, healPercent = 60, magic = { [0x07] = { spell = 2 } } })
local function atmaDown() return (H.readByte(0x1EEB) & 0x80) == 0 end
H.run({ maxFrames = 100000 }, {
  H.loadState("build/states/fc_atma_door.mss.lua"),
  H.waitFrames(60),
  (function()
    local t = 0
    return H.driveUntil(function()
      t = t + 1
      return atmaDown() or t >= 80000
    end, 80500, {
      H.call(function()
        if H.battleActive() or H.battleLoadStarted() then FA.frame() return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}) return end
        if not H.hasControl() then H.setPad({}) return end
        if t % 1800 == 0 then
          H.log(string.format("  door t=%d (%d,%d)", t, H.fieldX(), H.fieldY()))
        end
        local c = t % 48
        if c < 4 then H.setPad({ up = true })
        elseif c >= 24 and c < 28 then H.setPad({ a = true })
        else H.setPad({}) end
      end),
    }, "AtmaWeapon falls ($035F clears)")
  end)(),
  H.call(function()
    H.assertEq(atmaDown(), true, "$035F cleared -- AtmaWeapon defeated")
  end),
  -- absorb the aftermath (fade_in, Shadow branch, control return)
  (function()
    local t, calm = 0, 0
    return H.driveUntil(function()
      t = t + 1
      if not H.hasControl() or H.dialogWaiting() then calm = 0
      else calm = calm + 1 end
      return t >= 4800 or calm >= 240
    end, 5000, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "aftermath absorbed")
  end)(),
  H.call(function()
    local hp = {}
    for _, c in ipairs(H.partyMembers()) do hp[#hp+1] = H.charHp(c) end
    H.log(string.format("post-Atma: map=%d (%d,%d) hp=%s shadow-avail=%d",
      H.mapId() & 0x3ff, H.fieldX(), H.fieldY(), table.concat(hp, "/"),
      (H.readByte(0x1EDE) >> 3) & 1))
    H.screenshot("atma_down")
    H.assertEq(mapIs(394), true, "still on 394 (no Game Over)")
  end),
  H.saveState("fc_atma_down.mss"),
  H.logStep(function() return "done" end),
})
