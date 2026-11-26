-- @suite savestate=icedragon_entry slow
-- battle_icedragon.lua -- the Ice Dragon under the boss contract (docs/design/bosses-wor.md block 7, wt/v052-tg-wor2):
-- Absolute 0 is its telegraph, and a break cancels it.
--
-- Its script (ai_script.asm AIScript::_329): the first beat of its rotation of three attacks as vanilla's did (Battle,
-- N. Cross or N. Cross), then says "The air goes still!" (battle dialogue $A7) and glows: the line rides that turn.
-- Absolute 0 (attack $BB, command $0C) comes on the second beat (vanilla rolled Battle, Absolute 0 or Absolute 0
-- there), and only there: the third picks Battle, Surge or N. Cross (vanilla's Battle, Surge or Absolute 0), so
-- Absolute 0 comes only announced.  Under the contract (Ot6FuseTbl's row $0149) a break while it is lit cancels it: the
-- script forgets its `wait`, and the rotation starts again from its first beat, the line with it.  It has no HP
-- phase.  Its counters (a Battle for every hit, Surge at its death) are vanilla's; the dying Surge is unchanged (the
-- dying-attack rule is a later unit's).
--
-- Boots icedragon_entry (gen_wor_icedragon: the Ice Dragon's battle, event battle 132, as it comes up).  From a
-- snapshot at the battle's open:
--   landed    (M.fuseLanded, lib/ot6.lua) nothing staged and nothing held: the party Defends; the line comes on its
--             rotation's first beat and Absolute 0 on its next, and lands: a member's HP falls.  The effect is logged
--             member by member (whether the move was queued on the seat, the HP before and after).
--   then the three cases from the same snapshot (M.fuseCases, where the cases and the DECLARED staging are written
--   out: the gauge, the row's classes for the breaking Fight, the party's HP held; its HP is not held):
--   unbroken  the party Defends; the line shows on the rotation's first beat; the lit-fuse mark stands; Absolute 0 is
--             dispatched on its next turn, a glow between; the mark goes; the line reads "The air goes still!"
--             where the relocated dialogue table points.
--   broken    an aimed Fight confirmed once the mark is up breaks it: the cancel fires, the mark goes, the script
--             waits nowhere, no Absolute 0 on its first turns back, and the line returns on its first turn back (the
--             rotation's first beat again); Absolute 0 follows.
--   outside   a break with no fuse lit: nothing is cancelled and the cells stand, and the fuse then lights and fires.
--   and in every case: Absolute 0 comes only announced -- every Absolute 0 it dispatches has its line since the
--   Absolute 0 before it (or since the case's open); and the script names Absolute 0 once (the fuse's).
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor2/mutants/): see the report there.  A mechanism
-- test, not play (the landed case writes nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge and the row's classes, and holds the party's HP, through
-- them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/icedragon_entry.mss.lua"

local ICEDRAGON, ABS0, LINE = 0x149, 0xBB, 0xA7

local S = {}
-- every dispatch of the line or of Absolute 0: { f, move }, over the suite
local seen, unannounced = {}, 0
local function watchMove()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x < 8 or x > 18 or H.readWord(0x57C0 + (x - 8)) ~= ICEDRAGON then return end
    local cmd, arg = H.readByte(0xB5), H.readByte(0xB6)
    if cmd == 0x21 and arg == LINE then seen[#seen + 1] = { f = H.frame, move = false } end
    if cmd == 0x0C and arg == ABS0 then
      local ok = #seen > 0 and not seen[#seen].move
      seen[#seen + 1] = { f = H.frame, move = true }
      if not ok then unannounced = unannounced + 1 end
      H.log(string.format("[icedragon] f%d Absolute 0 dispatched: %s", H.frame, ok
        and "its line came since the Absolute 0 before" or "UNANNOUNCED (no line since the Absolute 0 before)"))
    end
  end, emu.callbackType.exec, H.sym("_dispatcher"), H.sym("_dispatcher"))
end
-- the move's effect on each member, from the dispatch record (targets, HP then) and HP now
local function effect(tag, m)
  local t, fell = {}, 0
  for i = 0, 3 do
    local id = H.readByte(0x3ED8 + 2 * i)
    if id ~= 0xFF then
      local now, mx = H.readWord(0x3BF4 + 2 * i), H.readWord(0x3C1C + 2 * i)
      local hit = m.tchars & (1 << i) ~= 0
      if hit and now < m.hp[i] then fell = fell + 1 end
      t[#t + 1] = string.format("seat %d char $%02X %s: %d -> %d of %d (%d%% of max), status $%02X/$%02X", i, id,
        hit and "a target" or "NOT a target", m.hp[i], now, mx, mx > 0 and (m.hp[i] - now) * 100 // mx or 0,
        H.readByte(0x3EE4 + 2 * i), H.readByte(0x3EF8 + 2 * i))
    end
  end
  H.log(string.format("[%s] effect: the move ($%02X/$%02X, targets $%02X) on the party: %s", tag, m.cmd, m.arg,
    m.tchars, table.concat(t, "; ")))
  return fell
end

-- The cap: the landed case is about 4,000 frames; three cases of about 9,000 each follow; 70,000 is about 2x.
H.run({ maxFrames = 70000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "the Ice Dragon's battle is up", 2),
  H.call(function()
    local at = H.aiAttacks(ICEDRAGON, ABS0)
    H.log(string.format("[icedragon] its turn script names Absolute 0 at %d place(s)", #at))
    H.assertEq(#at, 1, "the Ice Dragon's turn script names Absolute 0 once: the fuse's move (not its rotation's third "
      .. "beat)")
    watchMove()
  end),
  H.fuseSnap(S),
  H.fuseLanded({
    tag = "icedragon", species = ICEDRAGON, line = LINE, move = { cmd = 0x0C, atk = ABS0 }, turns = 1,
    landed = function(W, l, m)
      local fell = effect("icedragon", m)
      H.assertEq(fell >= 1, true, "icedragon landed: Absolute 0 landed (a target's HP fell within 420 frames)")
    end,
  }),
  H.fuseRestore(S, "icedragon"),
  H.fuseCases({
    tag = "icedragon", species = ICEDRAGON, write = WRITE,
    line = LINE, move = { cmd = 0x0C, atk = ABS0 }, turns = 1, glows = 1,
    lineText = "The air goes still!{wait}",
    arm = "idle", aim = true, plainBreaker = true,
    -- no fuse lit, and the window just opened: its Absolute 0 has just been dispatched (the rotation's second beat),
    -- so two of its turns stand before the next line (Tritoch's reading, battle_tritoch)
    partway = function(W)
      if W.cells() == nil or W.litBit() then return false end
      local last = nil
      for _, c in ipairs(W.cmds) do
        if (c.cmd == 0x0C and c.arg == ABS0) or (c.cmd == 0x21 and c.arg == LINE) then last = c end
      end
      return last ~= nil and last.cmd == 0x0C and H.frame - last.f < 240
    end,
    earned = function(C, W)
      H.assertEq(C.brk.post.blk, 0xFF, "icedragon: the rotation is forgotten after the cancel ($3240 = $FF)")
      local l2 = C.lines[2]
      H.log(string.format("[icedragon] the second line on its turn %d; it recovered after turn %d", l2.turn,
        C.rec.turn))
      H.assertEq(l2.turn, C.rec.turn + 1, "icedragon: the line returns on its first turn back (the rotation's first "
        .. "beat again)")
    end,
  }),
  H.call(function()
    local n = 0
    for _, x in ipairs(seen) do if x.move then n = n + 1 end end
    H.log(string.format("[icedragon] Absolute 0 dispatched %d time(s) over the suite, %d unannounced", n, unannounced))
    H.assertEq(n >= 3 and unannounced, 0, "Absolute 0 comes only announced (every Absolute 0 has its line since the "
      .. "one before; three or more seen)")
  end),
  H.logStep("[icedragon] PASS: the announce on the rotation's first beat, Absolute 0 on its second, the cancel and the "
    .. "rotation again"),
})
