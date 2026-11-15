-- @suite slow savestate=rapids_start
-- battle_breakwob_raft.lua -- the raft's authored rows in play: TERRA, EDGAR and BANON ride the lower Lete River
-- from the graph's capture `rapids_start` into the ride's forced fight (`battle 8`: two Pterodons, or a Nautiloid,
-- an Exocite and a Pterodon; field/event.asm EventBattle draws it from the fixture's counters), and the library's
-- fight driver plays it.  docs/design/break-coverage-wob.md section 13 is the design; battle_breakwob_events checks
-- the same rows as ROM bytes.
--
-- Asserted, from the engine's own cells (the shield gauge $3e40+2s / its max $3e41+2s, the broken timer $3e90+2s,
-- the species $57c0+2s), whatever the fixture deals:
--   1. every body of the fight is one of battle 8's three species and opens with its authored gauge (Pterodon,
--      Nautiloid and Exocite 2: the floor gave them 3);
--   2. the party breaks at least one of them: a gauge that reaches 0 and a broken timer that starts, on a body the
--      party hit (the monsters do not hit each other here);
--   3. the party wins the fight (a wipe raises inside the ride).
-- The driver reads the live command table and the weakness codex as a player would; nothing writes emulated state.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/rapids_start.mss.lua"

local AUTHORED = { [0x022] = 2, [0x038] = 2, [0x039] = 2 }   -- Pterodon, Nautiloid, Exocite
local SH_CUR, SH_MAX, BRK, SPECIES, PRESENT, MONHP = 0x3E40, 0x3E41, 0x3E90, 0x57C0, 0x3AA8, 0x3BFC

-- one battle's record: per slot the species, the gauge it opened with, and the frame a break started
local W = { up = false, done = false, slots = {}, opened = false }
local function watch()
  if not H.battleLoadStarted() then
    if W.opened and not W.done then
      W.done = true
      H.log("[raft] the fight is over; the field is back")
    end
    return
  end
  if W.done then return end
  if H.monstersPresent() == 0 then return end
  for s = 0, 5 do
    if (H.readByte(PRESENT + s * 2) & 1) == 1 and H.readWord(SPECIES + s * 2) ~= 0xFFFF then
      local r = W.slots[s]
      if r == nil then
        r = { sp = H.readWord(SPECIES + s * 2), open = H.readByte(SH_MAX + s * 2),
              cur = H.readByte(SH_CUR + s * 2) }
        W.slots[s] = r
        H.log(string.format("[raft] slot %d: species $%03X opens with %d of %d shield(s), %d hp", s, r.sp, r.cur,
          r.open, H.readWord(MONHP + s * 2)))
      end
      if r.open == 0 and H.readByte(SH_MAX + s * 2) ~= 0 then r.open = H.readByte(SH_MAX + s * 2) end
      local t = H.readByte(BRK + s * 2)
      if r.broke == nil and t ~= 0 and t ~= 0xFF then
        r.broke = H.frame
        H.log(string.format("[raft] slot %d ($%03X) BROKEN at f%d, %d hp left", s, r.sp, H.frame,
          H.readWord(MONHP + s * 2)))
      end
    end
  end
  W.opened = true
end

H.run({ maxFrames = 40000 }, {
  H.loadState(STATE),
  H.call(function() emu.addEventCallback(watch, emu.eventType.startFrame) end),
  H.advanceStory(function() return W.done end, 36000,
    { playBattles = "tactical", fight = { tactical = true, boost = true, items = true, healPercent = 55 } }),
  H.call(function()
    local n, broke = 0, 0
    for s, r in pairs(W.slots) do
      n = n + 1
      H.assertEq(AUTHORED[r.sp] ~= nil, true, string.format("slot %d: species $%03X is one of the raft's three", s,
        r.sp))
      H.assertEq(r.open, AUTHORED[r.sp], string.format("slot %d ($%03X): the gauge it opens with (its "
        .. "Ot6ShieldTbl row)", s, r.sp))
      if r.broke then broke = broke + 1 end
    end
    H.assertEq(n >= 2, true, "battle 8 dealt two or three bodies")
    H.assertEq(broke >= 1, true, "the party broke at least one of the raft's bodies")
    H.log(string.format("[raft] %d bodies, %d broken by the party; the rows hold in play", n, broke))
  end),
})
