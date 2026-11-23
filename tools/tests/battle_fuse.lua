-- @suite savestate=atma_entry slow
-- battle_fuse.lua -- the fuse machinery itself (#561; ot6_fuse.asm, docs/design/bosses-wor.md section 1): the
-- table against the scripts, the scripts' new home, and the worked example of an authored fuse.
--
-- 1. The block's home.  The AI script pointer table and block load in bank $F1 (ff6-en.cfg), the block directly
--    behind the table, with room: at least $2000 bytes of fill at its end.
-- 2. Ot6FuseTbl against the built scripts, row by row (read from the ROM):
--      a script row's first lit address is a command of its species' own turn script that follows a `wait`, with
--      a `dlg` before it in the same block (the announce) and an attack after its last lit address (the move);
--      its last lit address follows a `wait` too;
--      a switch row's species has a counter that sets that battle switch and speaks a line, and the line is in
--      Ot6FuseLineTbl (so the counter that winds the fuse is no story block);
--      and an announced move always fires (the owner, 2026-11-23: "don't announce anything that won't happen.
--      however, okay to make a roll before that"): from the announce to the move every attack command is
--      one certain attack (its three choices the same), no command or item is rolled, and the block's own
--      conditions hold no roll (if_roll, conditional $0A: they are tested again on the move's turn).  For a switch
--      row the same holds for every block of the turn script that the switch conditions.
--    The rows expected are the four fights of unit A and the worked example; a row for any other species is a
--    change the unit that makes it adds here.
-- 3. The worked example of an authored fuse, played: the CzarDragon's script (AIScript::_311) is the fuse block
--    in vanilla's idiom -- `if_monster_timer 8 / dlg $8D / short_glow / wait / long_glow / attack FLARE_STAR /
--    reset_monster_timer / end_if` -- with its line in the first free battle-dialogue slot, behind an arming block
--    that rolls first (`if_monster_timer 8 / if_monster_switch_clr 0 / if_roll 128 / attack BATTLE /
--    set_monster_switch 0`).  Every roll is read where it is made (Ot6AIRolled: the roll in A, the chance in
--    $3A2E) and the arming must follow exactly the rolls under the chance.  No battle deals the
--    CzarDragon, so the formation is STAGED: from atma_entry the party paces into a random battle on Kefka's
--    Tower's map 331 and the formation the battle loads is written to 561, the CzarDragon alone, at
--    LoadBattleProp's entry.  It has no shield row (no battle deals it), so one is staged too.  Then M.fuseCases
--    (lib/ot6.lua) plays the three cases:
--      unbroken  the line shows once its clock has run; the lit-fuse mark stands before its shield emblem; Flare
--                Star is dispatched on its next turn, a glow each side; the mark goes.
--      broken    an aimed Fight confirmed with the mark up breaks it: the cancel fires, clears the switch and
--                restarts the clock (the monster's timer reads 0), the mark goes, its first turn back is no Flare
--                Star, and the line returns, after another roll under the chance, before the move does.
--      outside   a break before the clock has run: nothing is cancelled, and the fuse lights and fires after.
-- DECLARED SYNTHETIC SETUP (tools/state_write_waivers.txt): the formation word ($11E0) at LoadBattleProp, and
-- M.fuseCases' staging (the row, the gauge, HP held).  A mechanism test, not play.
-- Mutants (tools/build/mutant_rom.py; each run's log in build/attempts/wt/v051-fuse/mutants/, the edits in its
-- *.mutant.txt): fuse_never (Ot6FuseCancel+3=80: no break cancels) is red at "the break during the fuse cancels
-- it"; fuse_no_trigger (Ot6FuseSnuff+5=60: the cancel skips the row's clears) at "monster switch 0 is clear after
-- the cancel"; fuse_always (Ot6FuseCancel+12=EAEA: a break cancels whether or not the fuse is lit) at "a break
-- outside the fuse cancels nothing"; fuse_no_mark (Ot6MarkWordTbl+6=EE01: the mark's word is the fill word) at
-- "the lit-fuse mark stands before the shield emblem"; fuse_story (Ot6FuseLineTbl=FF: no announce is listed) at
-- "its counter's line ... is in Ot6FuseLineTbl"; roll_always (Ot6AICondRoll+6=3860EA: every roll continues) at
-- "a roll under the chance came between the cancel and the second line".
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/atma_entry.mss.lua"

local CZAR, CZAR_FORMATION, MAP = 0x137, 561, 331
local function map() return H.mapId() & 0x1ff end
local function rb(a) return H.readRomByte(a & 0x3FFFFF) end
local function rw(a) return rb(a) | (rb(a + 1) << 8) end

-- ---- 1 and 2: the ROM's data ------------------------------------------------------------------------------------
local SIZE = { [0] = 4, 2, 4, 3, 4, 4, 4, 2, 3, 4, 4, 3, 4, 1, 1, 1 }   -- AICmdSizeTbl (battle_main.asm)
local function opSize(b) return b >= 0xF0 and SIZE[b - 0xF0] or 1 end
local WANT = { [0x117] = "AtmaWeapon", [0x17D] = "Atma", [0x12A] = "Kefka", [0x150] = "the Gold Dragon",
  [0x137] = "the CzarDragon (the worked example)" }

-- every command of the block at x from `from` (nil: its start) to `to` (nil: its end) that picks among three is one
-- certain pick, and none of the block's conditions is a roll: returns the offences as text
local function rolls(AI, x, from, to)
  local bad = {}
  while rb(AI + x) ~= 0xFE and rb(AI + x) ~= 0xFF do
    local b = rb(AI + x)
    if b == 0xFC and rb(AI + x + 1) == 0x0A then bad[#bad + 1] = string.format("if_roll at $%04X", x) end
    local inside = (from == nil or x >= from) and (to == nil or x <= to)
    if (b == 0xF0 or b == 0xF4) and inside
       and not (rb(AI + x + 1) == rb(AI + x + 2) and rb(AI + x + 2) == rb(AI + x + 3)) then
      bad[#bad + 1] = string.format("a rolled pick at $%04X (%02X %02X %02X)", x, rb(AI + x + 1), rb(AI + x + 2),
        rb(AI + x + 3))
    end
    if b == 0xF6 and inside and rb(AI + x + 2) ~= rb(AI + x + 3) then
      bad[#bad + 1] = string.format("a rolled item at $%04X", x)
    end
    x = x + opSize(b)
  end
  return table.concat(bad, "; ")
end

local function staticChecks()
  local AI, PTRS, TBL, LINES = H.sym("AIScript"), H.sym("AIScriptPtrs"), H.sym("Ot6FuseTbl"), H.sym("Ot6FuseLineTbl")
  H.assertEq(string.format("%02X", AI >> 16), "F1", "the AI script block loads in bank $F1")
  H.assertEq(AI - PTRS, 0x300, "the block directly behind its pointer table (384 pointers)")
  -- the block's end: the last script's end_retal, then fill
  local last = 0
  for sp = 0, 383 do last = math.max(last, rw(PTRS + 2 * sp)) end
  local free, a = 0, AI + 0x5FFF
  while rb(a) == 0xFF and a > AI + last do free = free + 1; a = a - 1 end
  H.log(string.format("[fuse] the block: the highest script pointer is $%04X; %d bytes ($%X) of fill at its end",
    last, free, free))
  H.assertEq(free >= 0x2000 and last < 0x8000, true, "the block has room for the later units' scripts (at least "
    .. "$2000 bytes of fill) and every pointer is below $8000 (the no-counter-script test)")
  local lines = {}
  do
    local i = 0
    while rb(LINES + i) ~= 0xFF do lines[rb(LINES + i)] = true; i = i + 1 end
  end
  local seen, rows = {}, 0
  local r = TBL
  while rw(r) ~= 0xFFFF do
    local sp, lo, len, mkeep, bkeep, flags = rw(r), rw(r + 2), rb(r + 4), rb(r + 5), rb(r + 6), rb(r + 7)
    rows = rows + 1
    seen[sp] = (seen[sp] or 0) + 1
    H.assertEq(WANT[sp] ~= nil, true, string.format("row %d's species $%03X is one of the fuses built (unit A's "
      .. "four fights and the worked example)", rows, sp))
    -- the species' two scripts: its turns' to the first $FF, its counter's to the next
    local start = rw(PTRS + 2 * sp)
    local cmds, blockOf, block = {}, {}, start
    local x = start
    while rb(AI + x) ~= 0xFF do
      cmds[x] = true
      blockOf[x] = block
      local b = rb(AI + x)
      x = x + opSize(b)
      if b == 0xFE then block = x end
    end
    local mainEnd = x
    if flags & 0x80 == 0 then
      local hi = lo + len - 1
      H.assertEq(start <= lo and hi < mainEnd and cmds[lo] == true and cmds[hi] == true, true, string.format(
        "%s: the lit addresses script+$%04X..+$%04X are commands of its own turn script", WANT[sp], lo - start,
        hi - start))
      H.assertEq(string.format("%02X %02X", rb(AI + lo - 1), rb(AI + hi - 1)), "FD FD", string.format("%s: its "
        .. "first and last lit addresses each follow a `wait`", WANT[sp]))
      H.assertEq(blockOf[lo], blockOf[hi], WANT[sp] .. ": both in one block")
      local line, move, lineAt, moveAt = nil, nil, nil, nil
      x = blockOf[lo]
      while rb(AI + x) ~= 0xFE and rb(AI + x) ~= 0xFF do
        local b = rb(AI + x)
        if b == 0xF3 and x < lo then line = rw(AI + x + 1); lineAt = x end
        if x >= hi and move == nil and (b < 0xF0 or (b == 0xF0 and rb(AI + x + 1) ~= 0xFE)) then
          move, moveAt = b < 0xF0 and b or rb(AI + x + 1), x
        end
        x = x + opSize(b)
      end
      H.assertEq(line ~= nil and move ~= nil, true, string.format("%s: the block announces (a dlg before the fuse) "
        .. "and fires (an attack after it)", WANT[sp]))
      H.assertEq(rolls(AI, blockOf[lo], lineAt, moveAt), "", string.format("%s: nothing rolls from the announce "
        .. "to the move, and the block's conditions hold no roll (an announced move always fires)", WANT[sp]))
      H.log(string.format("[fuse] row %d: %s ($%03X), lit at script+$%04X for %d byte(s), announce dlg $%02X, move "
        .. "attack $%02X; a break keeps monster bits $%02X, battle switches $%02X, flags $%02X", rows, WANT[sp], sp,
        lo - start, len, line, move, mkeep, bkeep, flags))
    else
      -- a switch row: the counter sets the switch and speaks a listed line
      local sets, says = false, nil
      x = mainEnd + 1
      while rb(AI + x) ~= 0xFF do
        local b = rb(AI + x)
        if b == 0xF9 and rb(AI + x + 1) == 0x01 and rb(AI + x + 2) == 0x00 and (1 << rb(AI + x + 3)) == len then
          sets = true
        end
        if b == 0xF3 then says = rw(AI + x + 1) end
        x = x + opSize(b)
      end
      H.assertEq(sets, true, string.format("%s: its counter sets the battle switch the row is lit by (mask $%02X)",
        WANT[sp], len))
      H.assertEq(says ~= nil and lines[says] == true, true, string.format("%s: its counter's line (dlg $%02X) is in "
        .. "Ot6FuseLineTbl, so the block that winds the fuse is no story block", WANT[sp], says or 0))
      H.assertEq(bkeep & len, 0, WANT[sp] .. ": a break clears the switch the row is lit by")
      -- the turn script's blocks the switch conditions (if_battle_switch_set 0, bit): certain throughout
      local bad, nblocks = {}, 0
      x = start
      local bstart, conditioned = start, false
      while true do
        local b = rb(AI + x)
        if b == 0xFC and rb(AI + x + 1) == 0x14 and rb(AI + x + 2) == 0x00 and (1 << rb(AI + x + 3)) == len then
          conditioned = true
        end
        if b == 0xFE or b == 0xFF then
          if conditioned then
            nblocks = nblocks + 1
            local r1 = rolls(AI, bstart, nil)
            if r1 ~= "" then bad[#bad + 1] = r1 end
          end
          if b == 0xFF then break end
          bstart, conditioned = x + 1, false
        end
        x = x + opSize(b)
      end
      H.assertEq(nblocks >= 1 and table.concat(bad, "; "), "", string.format("%s: the %d block(s) of its turns "
        .. "that the switch conditions roll nothing (an announced move always fires)", WANT[sp], nblocks))
      H.log(string.format("[fuse] row %d: %s ($%03X), lit by battle switch mask $%02X, announce dlg $%02X (its "
        .. "counter's); a break keeps monster bits $%02X, battle switches $%02X, flags $%02X", rows, WANT[sp], sp,
        len, says, mkeep, bkeep, flags))
    end
    r = r + 8
  end
  for sp, name in pairs(WANT) do
    H.assertEq(seen[sp] ~= nil, true, name .. " has a row in Ot6FuseTbl")
  end
  H.assertEq(seen[0x12A], 2, "Kefka has two rows (the line under 7,680 HP and the line under 32,640)")
  H.log(string.format("[fuse] PASS static: %d rows", rows))
end

local staged = false
-- every roll of the arming block, as it is made: { f, r, n, armed (monster switch 0 read set before the next roll) }
local rollsSeen, gen = {}, 0
H.run({ maxFrames = 400000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in Kefka's Tower"),
  H.call(function()
    H.assertEq(map(), MAP, "atma_entry stands on map 331")
    staticChecks()
    -- the declared staging: the formation the next battle loads
    local lb = H.sym("LoadBattleProp")
    emu.addMemoryCallback(function()
      if staged then return end
      staged = true
      H.log(string.format("[fuse] f%d the battle's formation $%03X -> %d (the CzarDragon alone), staged at "
        .. "LoadBattleProp", H.frame, H.readWord(0x11E0) & 0x7FFF, CZAR_FORMATION))
      H.writeWord(0x11E0, CZAR_FORMATION)
    end, emu.callbackType.exec, lb, lb)
    local ro = H.sym("Ot6AIRolled")
    emu.addMemoryCallback(function()
      rollsSeen[#rollsSeen + 1] = { f = H.frame, r = emu.getState()["cpu.a"] & 0xFF, n = H.readByte(0x3A2E),
        gen = gen, armed = false }
    end, emu.callbackType.exec, ro, ro)
    -- the arming block rolls only while monster switch 0 is clear (its own condition), so the switch read set
    -- before the next roll is this roll's doing
    emu.addEventCallback(function()
      local r = rollsSeen[#rollsSeen]
      if r ~= nil and r.gen == gen and H.readByte(0x3DAC + 8) & 0x01 ~= 0 then r.armed = true end
    end, emu.eventType.endFrame)
  end),
  H.paceToEncounter("fuse", 0),
  H.call(function()
    H.assertEq(staged, true, "the formation was staged at LoadBattleProp")
    H.assertEq(H.readWord(0x57C0), CZAR, "the battle loaded the CzarDragon in slot 0")
  end),
  H.fuseCases({
    tag = "czar", species = CZAR, write = WRITE,
    line = 0x8D, move = { cmd = 0x0C, atk = 0xC6 }, turns = 1, glows = 2,
    arm = "idle",
    bossHp = 60000,
    row = { max = 3, classes = 0x0F },
    -- at once: its clock (if_monster_timer 8: 256 frames) has not run
    partway = function(W) return true end,
    onOpen = function() gen = gen + 1 end,
    earned = function(C, W)
      local pre, post = C.brk.pre, C.brk.post
      H.assertEq(pre.mvar & 0x01, 1, "czar: monster switch 0 stood at the break (the roll had armed the fuse)")
      H.assertEq(post.mvar & 0x01, 0, "czar: monster switch 0 is clear after the cancel (the roll is to be won "
        .. "again)")
      H.assertEq(pre.timer >= 16 and post.timer <= 1, true, string.format("czar: the clock was restarted by the "
        .. "cancel (the monster's timer read %d at the break and %d after it)", pre.timer, post.timer))
      -- and a roll under the chance came between the cancel and the second line
      local won = 0
      for _, r in ipairs(rollsSeen) do
        if r.gen == gen and r.f > C.brk.f and r.f < C.lines[2].f and r.r < r.n then won = won + 1 end
      end
      H.assertEq(won >= 1, true, "czar: a roll under the chance came between the cancel and the second line")
    end,
  }),
  H.call(function()
    -- the roll: the arming follows exactly the rolls under the chance
    local t, under, over = {}, 0, 0
    for _, r in ipairs(rollsSeen) do
      t[#t + 1] = string.format("%d/%d%s", r.r, r.n, r.armed and "*" or "")
      if r.r < r.n then under = under + 1 else over = over + 1 end
      H.assertEq(r.armed, r.r < r.n, string.format("the roll at f%d (%d against a chance of %d in 256) %s the fuse",
        r.f, r.r, r.n, r.r < r.n and "arms" or "does not arm"))
    end
    H.log(string.format("[fuse] the rolls (roll/chance, * armed): %s -- %d under the chance, %d not", table.concat(t, " "),
      under, over))
    H.assertEq(#rollsSeen >= 3, true, "the arming block rolled in every case (three or more rolls seen)")
  end),
  H.logStep("[fuse] PASS: the table, the block's home and the worked example"),
})
