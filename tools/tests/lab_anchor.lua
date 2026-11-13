-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- lab_anchor.lua -- does Air Anchor deal damage, and does a boost multiply it?  (#469 review; a one-off lab)
-- OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-dino-v1 tools/tests/run.sh tools/tests/lab_anchor.lua <log>
-- EDGAR throws Air Anchor at 0 BP, then at 1 BP, in one battle (H.kitBattle); everyone else Defends.  Logged: the
-- damage Ot6BoostDmg meets ($11B0 at its entry) and leaves (at its rtl), and the target's HP before and after.
local H = dofile("tools/tests/lib/ot6.lua")
local EDGAR, ANCHOR = 4, 0xA9
local BD, BD_EXIT = H.sym("Ot6BoostDmg"), H.sym("Ot6FoldCmdTbl") - 1
local cur
local function hpAll()
  local t = {}
  for m = 0, 5 do t[m] = H.readWord(0x3BFC + m * 2) end
  return t
end
H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-dino-v1"),
  H.call(function()
    emu.addMemoryCallback(function()
      if H.readByte(0x3A7C) ~= 0x09 or H.readByte(0x3A7D) ~= ANCHOR then return end
      local x = emu.getState()["cpu.x"] & 0xFF
      if x >= 8 then return end
      cur = { pend = H.readByte(0x3E9D + x), base = H.readWord(0x11B0), hp = hpAll() }
    end, emu.callbackType.exec, BD, BD)
    emu.addMemoryCallback(function()
      if cur == nil or cur.out then return end
      cur.out = H.readWord(0x11B0)
      H.log(string.format("[anchor] Air Anchor at %d BP: Ot6BoostDmg met base %d and left %d", cur.pend, cur.base,
        cur.out))
      cur = nil
    end, emu.callbackType.exec, BD_EXIT, BD_EXIT)
  end),
  (function()
    local P = H.newPacer({ tag = "anchor pace" })
    local sx, sy
    return H.seqStep({
      H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldSettled() end,
        1500, "the world map settled", 5),
      H.call(function() sx, sy = P.findStart(8) end),
      H.worldNavTo(function() return sx end, function() return sy end,
        { maxFrames = 4000, playBattles = "mustflee", care = false }),
      H.call(function() P.plan() end),
      H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
        H.call(function() H.setPad(P.pad()) end),
      }, "a random encounter"),
    })
  end)(),
  H.call(function()
    local h = hpAll()
    H.log(string.format("[anchor] battle $%03X, HP %d %d %d %d %d %d", H.readWord(0x11E0), h[0], h[1], h[2], h[3],
      h[4], h[5]))
  end),
  H.kitBattle({
    { who = EDGAR, cmd = 0x09, row = ANCHOR, boost = 0 },
    { who = EDGAR, cmd = 0x09, row = ANCHOR, boost = 1 },
  }, { maxFrames = 60000, untilPlanDone = true }),
  H.call(function()
    local h = hpAll()
    H.log(string.format("[anchor] after: HP %d %d %d %d %d %d", h[0], h[1], h[2], h[3], h[4], h[5]))
  end),
})
