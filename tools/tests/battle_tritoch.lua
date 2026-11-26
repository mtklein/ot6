-- @suite savestate=tritoch_entry slow
-- battle_tritoch.lua -- Tritoch under the boss contract (docs/design/bosses-wor.md block 8, wt/v052-tg-wor1): Ice 3 is
-- its telegraph, and a break cancels it.
--
-- Its script (ai_script.asm AIScript::_324): the first turn of its rotation of three says "Frost climbs the cliff!"
-- (battle dialogue $A5), glows and Rasps (the line rides that turn); Ice 3 (attack $0A, command $02) comes on the
-- second (vanilla rolled Ice 3, Ice 3 or Rasp there, and Rasp, Rasp or Ice 3 on the first); the third picks Rasp or
-- Cold Dust (vanilla's Rasp, Cold Dust or Ice 3: Ice 3 comes only announced).  Under the contract (Ot6FuseTbl's row $0144) a break while it is lit cancels it: the
-- script forgets its `wait`, and the rotation starts again from its first turn, the line with it.  Tritoch has no HP
-- phase: its rotation is the same at every HP.  Its counters (Rasp for fire, Cold Dust on a skill's user) are
-- vanilla's; a Fight draws nothing, so the party's Fights here draw no counter.
--
-- Boots tritoch_entry (gen_wor_tritoch: Tritoch's battle, event battle 119, as it comes up).  From a snapshot at the
-- battle's open:
--   landed    (M.fuseLanded, lib/ot6.lua) nothing staged and nothing held: the party Defends; the line comes on its
--             rotation's first turn and Ice 3 on its next, and lands: a member's HP falls.
--   then the three cases from the same snapshot (M.fuseCases, where the cases and the DECLARED staging are written
--   out: the gauge, the row's classes for the breaking Fight, the party's HP held; Tritoch's HP is not held):
--   unbroken  the party Defends; the line shows on the rotation's first turn; the lit-fuse mark stands; Ice 3 is
--             dispatched on its next turn, a glow between; the mark goes; the line reads "Frost climbs the cliff!"
--             where the relocated dialogue table points.
--   broken    an aimed Fight confirmed once the mark is up breaks it: the cancel fires, the mark goes, the script
--             waits nowhere, no Ice 3 on its first turns back, and the line returns on its first turn back (the
--             rotation's first turn again); Ice 3 follows.
--   outside   a break with no fuse lit: nothing is cancelled and the cells stand, and the fuse then lights and fires.
--   and in every case: Ice 3 comes only announced -- every Ice 3 Tritoch dispatches has its line since the Ice 3 before
--   it (or since the case's open); and the script names Ice 3 once (the fuse's).
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; tritoch_no_row (its row's species $0144 -> $0145: no row) at "the
-- lit-fuse mark stands"; tritoch_ice_back (the third turn's pick Rasp, Cold Dust, Ice 3 again) at "Tritoch's turn
-- script names Ice 3 once" and, played, at "Ice 3 comes only announced".  A mechanism test, not play (the landed case writes nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge and the row's classes, and holds the party's HP, through
-- them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/tritoch_entry.mss.lua"

local TRITOCH, ICE3, LINE = 0x144, 0x0A, 0xA5

local S = {}
-- every Tritoch dispatch of the line or of Ice 3: { f, ice }, over the suite
local seen, unannounced = {}, 0
-- the game's damage writes after each Ice 3 dispatch (_writedamage, the first after it): { f, miss = $3A5A's
-- character bits (a target the hit missed) }
local writes, pendingIce = {}, false
local function watchIce()
  emu.addMemoryCallback(function()
    if not pendingIce then return end
    pendingIce = false
    writes[#writes + 1] = { f = H.frame, miss = H.readByte(0x3A5A) & 0x0F }
    H.log(string.format("[tritoch] f%d the hit's damage is written: Miss bits $%02X; damage %d %d %d %d", H.frame,
      H.readByte(0x3A5A) & 0x0F, H.readWord(0x33D0), H.readWord(0x33D2), H.readWord(0x33D4), H.readWord(0x33D6)))
  end, emu.callbackType.exec, H.sym("_writedamage"), H.sym("_writedamage"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x < 8 or x > 18 or H.readWord(0x57C0 + (x - 8)) ~= TRITOCH then return end
    local cmd, arg = H.readByte(0xB5), H.readByte(0xB6)
    if cmd == 0x21 and arg == LINE then seen[#seen + 1] = { f = H.frame, ice = false } end
    if cmd == 0x02 and arg == ICE3 then
      local ok = false
      for k = #seen, 1, -1 do
        if seen[k].ice then break end
        ok = true
        break
      end
      seen[#seen + 1] = { f = H.frame, ice = true }
      writes, pendingIce = {}, true
      if not ok then unannounced = unannounced + 1 end
      H.log(string.format("[tritoch] f%d Ice 3 dispatched: %s", H.frame, ok and "its line came since the Ice 3 before"
        or "UNANNOUNCED (no line since the Ice 3 before)"))
    end
  end, emu.callbackType.exec, H.sym("_dispatcher"), H.sym("_dispatcher"))
end
-- The cap: the landed case is about 4,000 frames; three cases of about 8,000 each follow; 60,000 is about 2x.
H.run({ maxFrames = 60000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "Tritoch's battle is up", 2),
  H.call(function()
    local at = H.aiAttacks(TRITOCH, ICE3)
    H.log(string.format("[tritoch] its turn script names Ice 3 at %d place(s)", #at))
    H.assertEq(#at, 1, "Tritoch's turn script names Ice 3 once: the fuse's move (not its rotation's third turn, nor its "
      .. "first, where the line is)")
    watchIce()
  end),
  H.fuseSnap(S),
  H.fuseLanded({
    tag = "tritoch", species = TRITOCH, line = LINE, move = { cmd = 0x02, atk = ICE3 }, turns = 1,
    landed = function(W, l, m)
      -- (wt/v052-tg-wor2's replay: Ice 3 went to TERRA alone and her HP, full, did not move -- "Ice 3 on targets $02;
      -- HP fell: " and red here, build/attempts/wt/v052-tg-wor2/final/suites/battle_tritoch-replay1-red.log; she
      -- neither absorbs nor nulls ice, $3BCC/$3BCD 00, build/attempts/wt/v052-tg-wor2/final/suites/probe_trit.log: the
      -- spell missed her.  So the hit is judged as the game deals it, read where the game writes it
      -- (_writedamage, the first after the dispatch: the target's damage $33D0 and its Miss bit in $3A5A): a target whose
      -- HP fell, or one the game dealt a Miss, took the move; a target that did neither fails as before)
      local fell, missed = {}, {}
      for i = 0, 3 do
        if H.readByte(0x3ED8 + 2 * i) ~= 0xFF and m.tchars & (1 << i) ~= 0 then
          local now = H.readWord(0x3BF4 + 2 * i)
          if now < m.hp[i] then fell[#fell + 1] = string.format("seat %d %d -> %d", i, m.hp[i], now)
          elseif writes[1] ~= nil and writes[1].miss & (1 << i) ~= 0 then
            missed[#missed + 1] = string.format("seat %d (the game wrote its Miss at f%d)", i, writes[1].f)
          end
        end
      end
      H.log(string.format("[tritoch] landed: Ice 3 on targets $%02X; HP fell: %s; the game's Miss: %s", m.tchars,
        table.concat(fell, ", "), table.concat(missed, ", ")))
      H.assertEq(#fell + #missed >= 1, true, "tritoch landed: Ice 3 landed (a target's HP fell within 420 frames, or the "
        .. "game dealt it a Miss)")
    end,
  }),
  H.fuseRestore(S, "tritoch"),
  -- (each case starts with no Ice 3 pending: a case cut short between a dispatch and its damage write must not hand
  -- the next case a stale read; the review round's)
  H.call(function() writes, pendingIce = {}, false end),
  H.fuseCases({
    tag = "tritoch", species = TRITOCH, write = WRITE,
    line = LINE, move = { cmd = 0x02, atk = ICE3 }, turns = 1, glows = 1,
    lineText = "Frost climbs the cliff!{wait}",
    arm = "idle", aim = true,
    onOpen = function() writes, pendingIce = {}, false end,
    -- no fuse lit, and the window just opened: its Ice 3 has just been dispatched (the rotation's second turn), so
    -- two of its turns stand before the next line (any moment with no line lit is before one, but a moment late in
    -- that window drew the next line before the breaking hit on all three tries of the review round's first dev run,
    -- build/attempts/wt/v052-tg-wor1/r2/dev_trit1.log)
    partway = function(W)
      if W.cells() == nil or W.litBit() then return false end
      local last = nil
      for _, c in ipairs(W.cmds) do if (c.cmd == 0x02 and c.arg == ICE3) or (c.cmd == 0x21 and c.arg == LINE) then last = c end end
      return last ~= nil and last.cmd == 0x02 and H.frame - last.f < 240
    end,
    earned = function(C, W)
      H.assertEq(C.brk.post.blk, 0xFF, "tritoch: the rotation is forgotten after the cancel ($3240 = $FF)")
      local l2 = C.lines[2]
      H.log(string.format("[tritoch] the second line on its turn %d; it recovered after turn %d", l2.turn, C.rec.turn))
      H.assertEq(l2.turn, C.rec.turn + 1, "tritoch: the line returns on its first turn back (the rotation's first "
        .. "turn again)")
    end,
  }),
  H.call(function()
    local n = 0
    for _, x in ipairs(seen) do if x.ice then n = n + 1 end end
    H.log(string.format("[tritoch] Ice 3 dispatched %d time(s) over the suite, %d unannounced", n,
      unannounced))
    H.assertEq(unannounced, 0, "Ice 3 comes only announced (every Ice 3 has its line since the one before)")
  end),
  H.logStep("[tritoch] PASS: the announce on the rotation's first turn, Ice 3 on its second, the cancel and the "
    .. "rotation again"),
})
