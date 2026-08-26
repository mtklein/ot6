-- probe_fc_fight1.lua -- one instrumented FC pool fight: why do pips not
-- chip?  Boots fc_land, walks until a battle, fights it with the traced
-- tactical driver, logs shields per action.
local H = dofile("tools/tests/lib/ot6.lua")
local F = H.newFightDriver("fc1", { tactical = true, boost = true,
  items = true, healPercent = 50, trace = true })
local seen = false
H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/fc_land.mss.lua"),
  H.waitFrames(120),
  -- pace back and forth to draw an encounter
  (function()
    local t = 0
    return H.driveUntil(function()
      return H.battleActive() or H.battleLoadStarted()
    end, 20000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        local ph = t % 240
        H.setPad(ph < 110 and { right = true } or (ph >= 120 and ph < 230) and { left = true } or {})
      end),
    }, "encounter drawn")
  end)(),
  (function()
    local t = 0
    return H.driveUntil(function()
      if H.battleActive() then seen = true end
      return seen and not H.battleActive() and not H.battleLoadStarted()
    end, 20000, {
      H.call(function()
        t = t + 1
        if t == 60 then
          local f = H.formationWords()
          H.log(string.format("fight: species=%s",
            table.concat({ f[1] or "?", f[2] or "?", f[3] or "?" }, ",")))
        end
        F.frame()
      end),
    }, "the fight ends")
  end)(),
  H.call(function()
    local hp = {}
    for _, c in ipairs(H.partyMembers()) do hp[#hp+1] = H.charHp(c) end
    H.log("post-fight party hp: " .. table.concat(hp, "/"))
  end),
  H.logStep(function() return "done" end),
})
