-- @suite savestate=train_b68_entry
-- battle_shadowpin_immune.lua -- a boss immune to Slow and Stop takes neither from Shadow's throws (#546,
-- docs/design/kit-shadow-pin.md section 1: vanilla's immunities stand).
--
--   tools/tests/run.sh tools/tests/battle_shadowpin_immune.lua
--
-- The Ghost Train ($0106) blocks Slow and Stop (MonsterProp +22, blocked status 3 = $14; vanilla's
-- InitStatusVars masks what Ot6Pin queues with the body's allowed statuses, $3330).  The fixture is
-- train_b68_entry, the corridor before the smokestack switch (gen_sabin_train's capture: SABIN, CYAN and SHADOW,
-- the bag holding Shuriken).  The suite walks to the switch and pulls it, as battle_suplextrain does, and in
-- battle 68 SHADOW throws Shuriken at the train through the real menu until two have landed (H.kitBattle: a throw
-- the battle takes from him is thrown again, as many as the bag holds, at most four; the others Fight and care).
-- Asserted, for both throws: Ot6Pin saw SHADOW's Throw land on the train, and the train holds neither Slow nor
-- Stop after it (the second throw finds it free, so it is a hobble refused again, not a pin); the train's
-- allowed statuses lack both; and its shield line's mark cell (two before the anchor) never shows a mark.
-- Reads and presses only.
local H = dofile("tools/tests/lib/ot6.lua")

local GHOSTTRAIN, SHURIKEN, SHADOW = 0x0106, 0x41, 3
local SLOW, STOP = 0x04, 0x10
local DAGGER, KNIFE = 0x21D8, 0x2174
local SHADOWL = 0x7EECF1
local PIN, FLUSH = H.sym("Ot6Pin"), H.sym("Ot6ShowFlush")

local watching, gSlot, gAllowed = false, nil, nil
local throws, marks = {}, 0
emu.addMemoryCallback(function()
  if not watching then return end
  local s = emu.getState()
  local x, y = s["cpu.x"] & 0xFF, s["cpu.y"] & 0xFF
  if H.readByte(0xB5) ~= 0x08 or x >= 8 or y ~= 8 + 2 * gSlot then return end
  throws[#throws + 1] = { f = H.frame, pre = H.readByte(0x3EF8 + y), allowed = H.readByte(0x3330 + y) }
  H.log(string.format("[immune] f%d a throw lands on the train: status3 $%02X, allowed $%02X", H.frame,
    throws[#throws].pre, throws[#throws].allowed))
end, emu.callbackType.exec, PIN, PIN)
emu.addMemoryCallback(function()
  if not watching then return end
  for _, t in ipairs(throws) do
    if t.post == nil and t.f < H.frame then
      t.post = H.readByte(0x3EF8 + 8 + 2 * gSlot)
      H.log(string.format("[immune] f%d after the throw of f%d: the train's status3 $%02X", H.frame, t.f, t.post))
    end
  end
end, emu.callbackType.exec, FLUSH, FLUSH)
emu.addEventCallback(function()
  if not watching then return end
  local cur = H.readWord(SHADOWL + gSlot * 14)
  if cur ~= 0 and (cur & 0x1F) >= 2 then
    local w = emu.readWord((cur - 2) * 2, emu.memType.snesVideoRam)
    if w == DAGGER or w == KNIFE then
      if marks == 0 then H.log(string.format("[immune] f%d the train's mark cell shows $%04X", H.frame, w)) end
      marks = marks + 1
    end
  end
end, emu.eventType.endFrame)

-- SHADOW's throws: one an entry, as many as the bag's Shuriken (at most MAX_THROWS), so a throw the battle takes
-- from him is thrown again.  The step ends once two have landed on the train and the second's result is read
-- (the v0.51 landing's draw: the train's Evil Toot Muddled him with his first throw queued, SABIN's care hit felled
-- him, and that throw never landed; with two entries the second was the only one, "2 entr(ies) played of 2
-- planned" and one "a throw lands on the train", build/attempts/wt/v051-land/)
local MAX_THROWS = 4
local plan = {}
local function twoLanded() return #throws >= 2 and throws[2].post ~= nil end
H.run({ maxFrames = 80000 }, {
  H.loadState("build/states/train_b68_entry.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(0x1850 + SHADOW) & 7 ~= 0, true, "SHADOW is in the party (gen_sabin_train's capture)")
    H.assertEq(H.invCountOf(SHURIKEN) >= 2, true, "the bag holds two Shuriken")
    for _ = 1, math.min(H.invCountOf(SHURIKEN), MAX_THROWS) do
      plan[#plan + 1] = { who = SHADOW, cmd = 0x08, row = SHURIKEN, boost = 0, slotFn = function() return gSlot end }
    end
    H.log(string.format("[immune] %d Shuriken in the bag: %d throw(s) planned, until two land", H.invCountOf(SHURIKEN),
      #plan))
  end),
  H.navTo(32, 7, { maxFrames = 8000, playBattles = "tactical" }),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad(ph < 4 and { "up", "a" } or { "up" })
      end),
    }, "the smokestack switch -> battle 68")
  end)(),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function()
    for s = 0, 5 do if H.readWord(0x57C0 + s * 2) == GHOSTTRAIN then return true end end
    return false
  end, 1200, "the Ghost Train in the formation", 5),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
  H.call(function()
    for s = 0, 5 do if H.readWord(0x57C0 + s * 2) == GHOSTTRAIN then gSlot = s end end
    local allowed = H.readByte(0x3330 + 8 + 2 * gSlot)
    H.log(string.format("[immune] the train in slot %d, allowed status3 $%02X", gSlot, allowed))
    gAllowed = allowed
    watching = true
  end),
  -- The others Fight the train and their care answers any member's lost control (cureAllies), not Defend: the
  -- train's Evil Toot can open the battle by Muddling SABIN and SHADOW and Berserking CYAN, and on the v0.50
  -- line's capture the Defending party wiped before SHADOW's first window ("05:350/0020 03:282/0020 02:349/0010"
  -- at f1271, a wipe at f5386: build/attempts/wt/v050-line-deaths/suites/).
  H.kitBattle(plan, { maxFrames = 30000, untilPlanDone = true, others = "fight", cureAllies = true,
    giveUp = twoLanded }),
  H.driveUntil(twoLanded, 3000,
    { { tick = function() H.setPad({}); return "frame" end, reset = function() end } }, "the second throw lands"),
  H.call(function()
    watching = false
    H.assertEq(#throws >= 2, true, "two throws landed on the train")
    for i = 1, 2 do
      H.assertEq(throws[i].post & (SLOW | STOP), 0, string.format("throw %d: the train holds neither Slow nor Stop", i))
    end
    H.assertEq(throws[2].pre & SLOW, 0, "the second throw found the train free: not hobbled, so never pinned")
    H.assertEq(marks, 0, "the train's mark cell never shows a mark")
    -- (after the property, so the mutant that lifts the immunity fails on the throws, not here)
    H.assertEq(gAllowed & (SLOW | STOP), 0, "the train blocks Slow and Stop (MonsterProp +22, vanilla's mask)")
    H.log("[immune] PASS: the immune train takes neither the hobble nor the pin")
  end),
})
