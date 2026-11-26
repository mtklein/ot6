-- @suite savestate=reddragon_entry slow
-- battle_reddragon.lua -- the Red Dragon under the boss contract (docs/design/bosses-wor.md block 14,
-- wt/v052-tg-wor2): its clock's Flare Star is announced, a break cancels it, and the break buys a fresh clock.
--
-- Its script (ai_script.asm AIScript::_339): on the turn its clock reaches 40 counts a roll of one in three (if_roll
-- 85, on the arming block, as the CzarDragon's worked example) arms monster switch 1 with that turn's Fire 2 or Fire
-- Ball; its next turn, the fuse block, says "Its scales turn white!" (battle dialogue $A8) and glows; the turn after
-- restarts the clock and casts Flare Star (attack $C6, command $0C).  Unarmed, the clock's burst is vanilla's at once,
-- S. Cross or L.4 Flare: Flare Star comes only announced.  Under the contract (Ot6FuseTbl's row $0153,
-- OT6_FUSE_SETB0) a break while it is lit cancels it (switch 1 cleared, the `wait` forgotten) and sets battle switch
-- 0; the clock runs through the break, so its first turn back restarts it (the script's first block, with that turn's
-- Fire 2 or Fire Ball) and clears battle switch 0: the next Flare Star needs a whole fresh clock.
--
-- Boots reddragon_entry (gen_wor_locke: the Red Dragon's battle, event battle 138, as it comes up).  From a snapshot
-- at the battle's open:
--   landed    (M.fuseLanded, lib/ot6.lua) nothing staged and nothing held: the party Defends; its clock runs, the line
--             comes and Flare Star on its next turn, and lands: a member's HP falls.  The effect is logged member by
--             member.
--   then the three cases from the same snapshot (M.fuseCases, where the cases and the DECLARED staging are written
--   out: the gauge, the row's classes for the breaking Fight, the party's HP held; its HP is not held):
--   unbroken  the party Defends; the line shows; the lit-fuse mark stands; Flare Star is dispatched on its next turn,
--             a glow between; the mark goes; the line reads "Its scales turn white!" where the dialogue table points.
--   broken    an aimed Fight confirmed once the mark is up breaks it: the cancel fires, monster switch 1 reads clear
--             and battle switch 0 set, the mark goes, no Flare Star on its first turns back; its first turn back
--             restarts its clock (the timer it reads at its second turn back is below the one at its first) and
--             clears battle switch 0; and the line returns only a whole clock later (1,200 frames or more after its
--             first turn back), after another roll under the chance; Flare Star follows.
--   outside   early in a clock (its timer under 20 counts), a break with no fuse lit: nothing is cancelled and the
--             cells stand, and the fuse then lights and fires.
--   and in every case: Flare Star comes only announced (every Flare Star has its line since the one before); the script
--   names Flare Star once (the fuse's); every roll of its arming block arms exactly when it is under the chance (a roll
--   whose turn a break purged excepted, and logged).
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor2/mutants/): see the report there.  A mechanism
-- test, not play (the landed case writes nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge and the row's classes, and holds the party's HP, through
-- them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/reddragon_entry.mss.lua"

local RED, FLARESTAR, LINE = 0x153, 0xC6, 0xA8

local function slotOf()
  for s = 0, 5 do
    if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == RED then return s end
  end
  return nil
end
local function ent() local s = slotOf(); return s and 8 + 2 * s end

local seen, unannounced = {}, 0
local rollsSeen, gen = {}, 0
local brks = {}
-- each of its turns as its script is read: { f, timer (raw $3DC0), bsw }
local turns = {}
local function watchAll()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x < 8 or x > 18 or H.readWord(0x57C0 + (x - 8)) ~= RED then return end
    local cmd, arg = H.readByte(0xB5), H.readByte(0xB6)
    if cmd == 0x21 and arg == LINE then seen[#seen + 1] = { f = H.frame, move = false } end
    if cmd == 0x0C and arg == FLARESTAR then
      local ok = #seen > 0 and not seen[#seen].move
      seen[#seen + 1] = { f = H.frame, move = true }
      if not ok then unannounced = unannounced + 1 end
      H.log(string.format("[red] f%d Flare Star dispatched: %s", H.frame, ok and "its line came since the Flare Star "
        .. "before" or "UNANNOUNCED (no line since the Flare Star before)"))
    end
  end, emu.callbackType.exec, H.sym("_dispatcher"), H.sym("_dispatcher"))
  local ro = H.sym("Ot6AIRolled")
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    if y ~= ent() then return end
    rollsSeen[#rollsSeen + 1] = { f = H.frame, r = emu.getState()["cpu.a"] & 0xFF, n = H.readByte(0x3A2E), gen = gen,
      armed = false }
  end, emu.callbackType.exec, ro, ro)
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x ~= ent() then return end
    turns[#turns + 1] = { f = H.frame, timer = H.readWord(0x3DC0 + x), bsw = H.readByte(0x3EB0), gen = gen }
  end, emu.callbackType.exec, H.sym("ExecMonsterAction"), H.sym("ExecMonsterAction"))
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    if y == ent() then brks[#brks + 1] = { f = H.frame, gen = gen } end
  end, emu.callbackType.exec, H.sym("Ot6HitBroke"), H.sym("Ot6HitBroke"))
  emu.addEventCallback(function()
    local e = ent()
    if e == nil then return end
    local r = rollsSeen[#rollsSeen]
    if r ~= nil and r.gen == gen and H.readByte(0x3DAC + e) & 0x02 ~= 0 then r.armed = true end
  end, emu.eventType.endFrame)
end
local function effect(m)
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
  H.log(string.format("[red] effect: the move ($%02X/$%02X, targets $%02X) on the party: %s", m.cmd, m.arg, m.tchars,
    table.concat(t, "; ")))
  return fell
end

local S = {}
-- The cap: the landed case is up to ~6,000 frames (a clock is ~1,300 and one in three arms); three cases of ~12,000
-- each follow (the broken case waits out a whole fresh clock); 100,000 is about 2x.
H.run({ maxFrames = 100000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "the Red Dragon's battle is up", 2),
  H.call(function()
    local at = H.aiAttacks(RED, FLARESTAR)
    H.log(string.format("[red] its turn script names Flare Star at %d place(s)", #at))
    H.assertEq(#at, 1, "the Red Dragon's turn script names Flare Star once: the fuse's move (not its clock's burst)")
    watchAll()
  end),
  H.fuseSnap(S),
  H.call(function() gen = gen + 1 end),
  H.fuseLanded({
    tag = "red", species = RED, line = LINE, move = { cmd = 0x0C, atk = FLARESTAR }, turns = 1,
    landed = function(W, l, m)
      H.log(string.format("[red] landed: the line at f%d, Flare Star at f%d", l.f, m.f))
      local fell = effect(m)
      H.assertEq(fell >= 1, true, "red landed: Flare Star landed (a target's HP fell within 420 frames)")
    end,
  }),
  H.fuseRestore(S, "red"),
  H.fuseCases({
    tag = "red", species = RED, write = WRITE,
    line = LINE, move = { cmd = 0x0C, atk = FLARESTAR }, turns = 1, glows = 1,
    lineText = "Its scales turn white!{wait}",
    arm = "idle", aim = true, plainBreaker = true,
    onOpen = function() gen = gen + 1 end,
    -- no fuse lit or armed, early in a clock (under 20 counts: the line is at least a turn and 20 counts away)
    partway = function(W)
      local c = W.cells()
      return c ~= nil and not W.litBit() and (c.mvar & 0x02) == 0 and c.timer < 40
    end,
    earned = function(C, W)
      local pre, post = C.brk.pre, C.brk.post
      H.assertEq(pre.mvar & 0x02, 0x02, "red: monster switch 1 stood at the break (the roll had armed the fuse)")
      H.assertEq(post.mvar & 0x02, 0, "red: monster switch 1 is clear after the cancel (the roll is to be won again)")
      H.assertEq(post.bsw & 0x01, 0x01, "red: battle switch 0 is set after the cancel (its first turn back restarts "
        .. "the clock)")
      H.assertEq(post.blk, 0xFF, "red: the script waits nowhere after the cancel ($3240 = $FF)")
      -- its turns back, as their scripts were read
      local back = {}
      for _, t in ipairs(turns) do if t.gen == gen and t.f > C.rec.f then back[#back + 1] = t end end
      H.assertEq(#back >= 2, true, "red: two of its turns back were read before the second line")
      H.log(string.format("[red] its first turn back at f%d: timer %d, battle switches $%02X; its second at f%d: timer "
        .. "%d, battle switches $%02X; the second line at f%d", back[1].f, back[1].timer, back[1].bsw, back[2].f,
        back[2].timer, back[2].bsw, C.lines[2].f))
      H.assertEq(back[1].bsw & 0x01, 0x01, "red: battle switch 0 still stood as its first turn back was read")
      H.assertEq(back[2].timer < back[1].timer, true, string.format("red: its first turn back restarted its clock (the "
        .. "timer read %d at its first turn back and %d at its second)", back[1].timer, back[2].timer))
      H.assertEq(back[2].bsw & 0x01, 0, "red: battle switch 0 is clear by its second turn back (the restart's clear)")
      H.assertEq(C.lines[2].f - back[1].f >= 1200, true, string.format("red: the line returns only a whole clock "
        .. "after its first turn back (%d frames; a clock is 40 counts, about 1,280)", C.lines[2].f - back[1].f))
      local won = 0
      for _, r in ipairs(rollsSeen) do
        if r.gen == gen and r.f > C.brk.f and r.f < C.lines[2].f and r.r < r.n then won = won + 1 end
      end
      H.assertEq(won >= 1, true, "red: a roll under the chance came between the cancel and the second line")
    end,
  }),
  H.call(function()
    local t, under, purged = {}, 0, 0
    for _, r in ipairs(rollsSeen) do
      t[#t + 1] = string.format("%d/%d%s", r.r, r.n, r.armed and "*" or "")
      if r.r < r.n then under = under + 1 end
      local cut = false
      for _, b in ipairs(brks) do if b.gen == r.gen and b.f >= r.f and b.f <= r.f + 300 then cut = true end end
      if cut and r.r < r.n and not r.armed then
        purged = purged + 1
        H.log(string.format("[red] the roll at f%d was under the chance, and a break purged its turn: not armed", r.f))
      else
        H.assertEq(r.armed, r.r < r.n, string.format("red: the roll at f%d (%d against a chance of %d in 256) %s the "
          .. "fuse", r.f, r.r, r.n, r.r < r.n and "arms" or "does not arm"))
      end
    end
    H.log(string.format("[red] the arming rolls (roll/chance, * armed): %s -- %d under the chance of %d (%d purged)",
      table.concat(t, " "), under, #rollsSeen, purged))
    local off = 0
    for _, r in ipairs(rollsSeen) do if r.n ~= 85 then off = off + 1 end end
    H.assertEq(#rollsSeen >= 1 and off, 0, "red: its arming block rolled, and every roll's chance is 85 in 256 (a third "
      .. "of the clocks, vanilla's share of Flare Star)")
    local n = 0
    for _, x in ipairs(seen) do if x.move then n = n + 1 end end
    H.log(string.format("[red] Flare Star dispatched %d time(s) over the suite, %d unannounced", n, unannounced))
    H.assertEq(n >= 3 and unannounced, 0, "Flare Star comes only announced (every Flare Star has its line since the "
      .. "one before; three or more seen)")
  end),
  H.logStep("[red] PASS: the clock's announce, Flare Star on its next turn, the cancel and a whole fresh clock"),
})
