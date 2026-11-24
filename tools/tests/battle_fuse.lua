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
--      row the same holds for every block of the turn script that the switch conditions;
--      in the turn that fires, every command that touches a trigger (a variable, a switch, reset_monster_timer)
--      comes BEFORE the move (the idiom, ot6_fuse.asm: a break after the move would purge a clear queued behind it
--      with no cancel, and the boss announce again with nothing earned);
--      and what the checks above cannot judge is pinned to a reading by hand (HAND below, one entry a row): the
--      conditions of every block before the fuse block (one whose conditions hold on the move's turn takes that
--      turn) and the fuse block's own (tested again on the move's turn: an HP line a heal crosses back would drop
--      an announced move).  A row whose blocks differ from the reading fails until its unit reads them again.
--    The rows expected are the four fights of unit A, the worked example, and the authored telegraphs (WANT; each
--    unit appends its own block: World of Balance bosses 1-5, wt/v051-tg-wob1; 7-10, wt/v051-tg-wob2); a row
--    for any other species is a change the unit that makes it adds here.  A call for backup (restore_monsters,
--    $F5 op 0) counts as a move: Telstar's waves (wt/v051-tg-wob2).
-- 3. The worked example of an authored fuse, played: the CzarDragon's script (AIScript::_311) is the fuse block
--    in vanilla's idiom -- `if_monster_switch_set 0 / dlg $8D / short_glow / wait / clr_monster_switch 0 /
--    reset_monster_timer / long_glow / attack FLARE_STAR / end_if` -- with its line in the first free
--    battle-dialogue slot, behind an arming block
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
--      via Filch LOCKE's Filch (Steal's list, row $57) confirmed with the mark up takes the last shield: the break
--                comes through Ot6TakeShields, entered with 8-bit index registers as Filch and OT6's Break call it
--                (battle_atmaweapon plays the Break spell; no member of this party knows it), and cancels the fuse;
--                the mark goes.
--      outside   a break before the clock has run: nothing is cancelled, and the fuse lights and fires after.
-- DECLARED SYNTHETIC SETUP (tools/state_write_waivers.txt): the formation word ($11E0) at LoadBattleProp, and
-- M.fuseCases' staging (the row, the gauge, HP held).  A mechanism test, not play.
-- Mutants (tools/build/mutant_rom.py, on the branch's final ROM and the graph's states; each run's log and its edit in
-- build/attempts/wt/v051-fuse/mutants-review/, made by build/lab/mutants/local.sh in the branch's worktree):
-- fuse_never (Ot6FuseCancel+3=80: no break cancels) is red at "the break by Filch during the fuse cancels it" here
-- and at "the break by Break spell during the fuse cancels it" in battle_atmaweapon; fuse_no_trigger
-- (Ot6FuseSnuff+5=60: the cancel skips the row's clears) at "monster switch 0 is clear after the cancel (the roll is
-- to be won again)"; fuse_always (Ot6FuseCancel+12=EAEA: a break cancels whether or not the fuse is lit) at "a break
-- outside the fuse cancels nothing"; fuse_no_mark (Ot6MarkWordTbl+6=EE01: the mark's word is the fill word) at "the
-- lit-fuse mark stands before the shield emblem"; fuse_story (Ot6FuseLineTbl=FF: no announce is listed) at "its
-- counter's line ... is in Ot6FuseLineTbl"; roll_always (Ot6AICondRoll+6=3860EA: every roll continues) at "the roll
-- at f... (... against a chance of 128 in 256) does not arm the fuse"; fuse_old_order
-- (Ot6FuseCzar=FA0B0100F147C6F9022400FB0000: the CzarDragon's fire turn with its clears after the move) at "in the
-- turn that fires, the trigger's clears come before the move".
-- wt/v051-tg-wob1's vargas_hand (Vargas's fuse condition, switch 0 -> 1) is red at "Vargas: the blocks before the
-- fuse block and its own conditions are the ones read by hand" (build/attempts/wt/v051-tg-wob1/merged/mutants-merged/).
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
  [0x137] = "the CzarDragon (the worked example)",
  -- ---- wt/v051-tg-wob1: World of Balance bosses 1-5 (bosses-wob.md) ----
  [0x134] = "the Whelk's head", [0x064] = "the Marshal", [0x103] = "Vargas", [0x12C] = "the Lete River Ultros",
  [0x104] = "TunnelArmr",
  -- ---- end wt/v051-tg-wob1 ----
}
-- ---- wt/v051-tg-wob2: World of Balance bosses 7-10 (bosses-wob.md) ----
WANT[0x044] = "Telstar"
WANT[0x106] = "the GhostTrain"
WANT[0x155] = "Rizopas"
WANT[0x14A] = "Kefka at Narshe"
-- ---- end wt/v051-tg-wob2 ----

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

-- the commands that touch a trigger: a variable ($F8), a switch ($F9), the monster's timer (reset_monster_timer,
-- $FB $00).  In the turn that fires, every one of them comes before the move (ot6_fuse.asm, the idiom): the fuse is
-- unlit once that turn's script is read, and a break between the move and a clear queued behind it purges the
-- clear with the rest of the turn (Ot6BrokenTurn) with no cancel, so the boss would announce again with nothing
-- earned.  Returns the offences from `from` (the move) to the turn's end (a `wait`, `end_if` or `end`).
local function clearsAfter(AI, from)
  local bad, x = {}, from
  while rb(AI + x) ~= 0xFD and rb(AI + x) ~= 0xFE and rb(AI + x) ~= 0xFF do
    local b = rb(AI + x)
    if b == 0xF8 or b == 0xF9 or (b == 0xFB and rb(AI + x + 1) == 0x00) then
      bad[#bad + 1] = string.format("$%02X at script+$%04X after the move", b, x)
    end
    x = x + opSize(b)
  end
  return table.concat(bad, "; ")
end
-- a block's conditions (each `if`: $FC and its three bytes), as text
local function conds(AI, x)
  local t = {}
  while rb(AI + x) == 0xFC do
    t[#t + 1] = string.format("%02X %02X %02X", rb(AI + x + 1), rb(AI + x + 2), rb(AI + x + 3))
    x = x + 4
  end
  return table.concat(t, " / ")
end
-- What the static checks cannot judge, checked by hand per row and pinned here: the conditions of every block of the
-- turn script BEFORE the fuse block (a block whose conditions hold on the move's turn takes that turn instead of the
-- resume: the move is late, or never comes), and the fuse block's own conditions (tested again on the move's turn:
-- one that can flip, an HP line a heal crosses back, drops an announced move).  A row whose blocks differ from what
-- was read by hand fails here until its unit reads them and says why here.  Key: species @ the fuse block's offset
-- in its script.
local HAND = {
  ["117@000C"] = { blocks = "earlier [15 24 07]; own [14 24 00]",
    why = "AtmaWeapon: the earlier block is its opening speech (monster switch 7 clear), which sets switch 7 once and "
      .. "nothing clears it (the row keeps bit 7); its own condition is switch 0, cleared only by the move's turn or "
      .. "the cancel" },
  ["17D@0000"] = { blocks = "earlier none; own [14 24 00]",
    why = "Atma: the fuse block is the script's first; switch 0, cleared only by the move's turn or the cancel" },
  ["12A@000B"] = { blocks = "earlier [15 24 00]; own [06 36 3C / 15 00 01]",
    why = "Kefka, the line under 7,680 HP: the earlier block is the battle event once (monster switch 0, never "
      .. "cleared); its own HP line flips back only if he is healed above 7,680 between the line and Goner, which "
      .. "nothing in his fight does unless the party heals him (not guarded: vanilla's own); battle switch 1 is "
      .. "set by the 32,640 line's block only" },
  ["12A@002B"] = { blocks = "earlier [15 24 00] [06 36 3C / 15 00 01]; own [06 36 FF]",
    why = "Kefka, the line under 32,640 HP: the earlier blocks are the battle event (once) and the 7,680 line, "
      .. "which battle switch 1 shuts while this fuse is lit (this block sets it); its own HP line flips back only "
      .. "if the party heals him above 32,640 between the line and Goner (not guarded: vanilla's own)" },
  ["150@0000"] = { blocks = "earlier none; own [14 00 00 / 0D 03 02]",
    why = "the Gold Dragon: the fire block is the script's first; battle switch 0 and its turn count (battle "
      .. "variable 3), which only its own next block adds to, cleared only by the fire block or the cancel" },
  ["137@0012"] = { blocks = "earlier [0B 08 00 / 15 24 00 / 0A 80 00]; own [14 24 00]",
    why = "the CzarDragon: the earlier block is the arming block, shut while switch 0 is set (if_monster_switch_clr "
      .. "0); its own condition is switch 0, cleared only by the move's turn or the cancel" },
  -- ---- wt/v051-tg-wob1: World of Balance bosses 1-5 (bosses-wob.md).  Each fuse block is its script's first, so no
  -- block comes before it; its one condition is a monster switch that only an ordinary turn of its own script sets
  -- and only the move's turn or the cancel clears (no counter of these five touches it).
  ["134@0000"] = { blocks = "earlier none; own [14 00 01]",
    why = "the Whelk's head: the fuse block is the script's first; battle switch 1, the shell's call, set only by "
      .. "the shell's call block (_256), which stands behind battle switches 0 and 1 clear, so it cannot be set "
      .. "again while lit; cleared by the move's turn or the cancel.  The head leaves the field only by its own "
      .. "move: the shell's script no longer draws it in (SHELL_GUARD below checks it), and its show block acts "
      .. "only on a head that is gone" },
  ["064@0011"] = { blocks = "earlier [13 01 01 / 15 24 01]; own [14 24 00]",
    why = "the Marshal: the earlier block is vanilla's alone block (one monster left), which now also drops an "
      .. "armed fuse; switch 1, set by the announce, shuts it from the announce to the move, and only the move's "
      .. "turn or the cancel clears it.  His own condition is switch 0, set by his rotation's second turn, cleared "
      .. "by the move's turn, the cancel, or the alone block before an announce; he has no counter" },
  ["103@0000"] = { blocks = "earlier none; own [14 24 00]",
    why = "Vargas: the fuse block is the script's first, ahead of his SABIN lines and 50-count block; switch 0, set "
      .. "by his rotation's second Battle, cleared by the move's turn or the cancel; his counters set battle "
      .. "switches only" },
  ["12C@0000"] = { blocks = "earlier none; own [14 24 00]",
    why = "the Lete River Ultros: the fuse block is the script's first, ahead of his opening and one-time lines; "
      .. "switch 0, set by his rotation's second turn, cleared by the move's turn or the cancel; his counters "
      .. "touch no switch" },
  ["104@0000"] = { blocks = "earlier none; own [14 24 00]",
    why = "TunnelArmr: the fuse block is the script's first, ahead of the Runic tutorial and the low-HP block; "
      .. "switch 0, set by its rotation's second turn, cleared by the move's turn or the cancel; its counter "
      .. "touches no switch" },
  -- ---- end wt/v051-tg-wob1 ----
  -- ---- wt/v051-tg-wob2: World of Balance bosses 7-10 (bosses-wob.md) ----
  ["044@0000"] = { blocks = "earlier none; own [0B 19 00 / 15 00 02]",
    why = "Telstar's first call (its clock at 25): the script's first block; its clock only climbs (the third "
      .. "call's turn and the cancel reset it), and battle switch 2 is set only by this call's own turn" },
  ["044@0020"] = { blocks = "earlier [0B 19 00 / 15 00 02]; own [0B 50 00 / 15 00 01]",
    why = "Telstar's second call (80): the earlier block is the first call, which has fired by the time this one "
      .. "announces (its clock came due first and its block comes first), so battle switch 2 shuts it; its own "
      .. "clock only climbs and switch 1 is set only by this call's turn" },
  ["044@0040"] = { blocks = "earlier [0B 19 00 / 15 00 02] [0B 50 00 / 15 00 01]; own [0B C8 00 / 15 00 00]",
    why = "Telstar's third call (200): both earlier calls have fired before it can announce (switches 2 and 1 "
      .. "shut them); its own clock only climbs until this call's turn resets it, and switch 0 is set by that "
      .. "turn only" },
  ["106@000D"] = { blocks = "earlier [15 00 00]; own [14 24 00]",
    why = "the GhostTrain: the earlier block is its opening turn (battle switch 0 clear), toggled once and never "
      .. "again; its own condition is monster switch 0, set by the arming block (vanilla's count and two-standing "
      .. "test, read a turn ahead) and cleared only by the move's turn or the cancel" },
  ["155@0000"] = { blocks = "earlier none; own [14 24 00]",
    why = "Rizopas: the fuse block is the script's first; monster switch 0, set by turn A's roll and cleared only "
      .. "by the move's turn or the cancel" },
  ["14A@0000"] = { blocks = "earlier none; own [14 24 00]",
    why = "Kefka at Narshe: the fuse block is the script's first; monster switch 0, set by his clock's arming turn "
      .. "and cleared only by the move's turn or the cancel" },
  -- ---- end wt/v051-tg-wob2 ----
}
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
  -- the blocks before the fuse block, and the fuse block's own conditions, against what was read by hand (HAND)
  local function handCheck(sp, start, fuseBlock)
    local earlier, x, bstart = {}, start, start
    while x < fuseBlock do
      local b = rb(AI + x)
      x = x + opSize(b)
      if b == 0xFE then earlier[#earlier + 1] = "[" .. conds(AI, bstart) .. "]"; bstart = x end
    end
    local got = string.format("earlier %s; own [%s]", #earlier > 0 and table.concat(earlier, " ") or "none",
      conds(AI, fuseBlock))
    local key = string.format("%03X@%04X", sp, fuseBlock - start)
    local h = HAND[key]
    H.log(string.format("[fuse] %s, the fuse block at script+$%04X: %s (by hand: %s)", WANT[sp], fuseBlock - start,
      got, h and h.why or "NOT READ"))
    H.assertEq(h ~= nil and h.blocks, got, string.format("%s: the blocks before the fuse block and its own conditions "
      .. "are the ones read by hand (HAND[%q]: none of them can take the move's turn or flip between announce and "
      .. "move)", WANT[sp], key))
  end
  local seen, rows = {}, 0
  local r = TBL
  while rw(r) ~= 0xFFFF do
    local sp, lo, len, mkeep, bkeep, flags = rw(r), rw(r + 2), rb(r + 4), rb(r + 5), rb(r + 6), rb(r + 7)
    rows = rows + 1
    seen[sp] = (seen[sp] or 0) + 1
    H.assertEq(WANT[sp] ~= nil, true, string.format("row %d's species $%03X is one of the fuses built (unit A's "
      .. "four fights, the worked example, and the units since)", rows, sp))
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
        -- (a call for backup is a move too: restore_monsters, $F5 with op 0 -- Telstar's waves, wt/v051-tg-wob2;
        -- and so is a withdrawal, kill_monsters, op 1 -- the Whelk's head drawing into its shell, wt/v051-tg-wob1)
        if x >= hi and move == nil and b == 0xF5 and (rb(AI + x + 2) == 0x00 or rb(AI + x + 2) == 0x01) then
          move, moveAt = b, x
        end
        x = x + opSize(b)
      end
      H.assertEq(line ~= nil and move ~= nil, true, string.format("%s: the block announces (a dlg before the fuse) "
        .. "and fires (an attack after it)", WANT[sp]))
      H.assertEq(rolls(AI, blockOf[lo], lineAt, moveAt), "", string.format("%s: nothing rolls from the announce "
        .. "to the move, and the block's conditions hold no roll (an announced move always fires)", WANT[sp]))
      H.assertEq(clearsAfter(AI, moveAt), "", string.format("%s: in the turn that fires, the trigger's clears come "
        .. "before the move (the idiom: a break after the move must not purge them)", WANT[sp]))
      handCheck(sp, start, blockOf[lo])
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
      local bad, nblocks, order, firstBlock = {}, 0, {}, nil
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
            -- the block's first attack, and the clears after it
            local y = bstart
            while rb(AI + y) ~= 0xFE and rb(AI + y) ~= 0xFF do
              local c = rb(AI + y)
              if c < 0xF0 or (c == 0xF0 and rb(AI + y + 1) ~= 0xFE) then
                local o = clearsAfter(AI, y)
                if o ~= "" then order[#order + 1] = o end
                break
              end
              y = y + opSize(c)
            end
            firstBlock = firstBlock or bstart
          end
          if b == 0xFF then break end
          bstart, conditioned = x + 1, false
        end
        x = x + opSize(b)
      end
      H.assertEq(nblocks >= 1 and table.concat(bad, "; "), "", string.format("%s: the %d block(s) of its turns "
        .. "that the switch conditions roll nothing (an announced move always fires)", WANT[sp], nblocks))
      H.assertEq(table.concat(order, "; "), "", string.format("%s: in the turn that fires, the trigger's clears come "
        .. "before the move (the idiom: a break after the move must not purge them)", WANT[sp]))
      handCheck(sp, start, firstBlock)
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
  H.assertEq(seen[0x044], 3, "Telstar has three rows (its calls at 25, 80 and 200; wt/v051-tg-wob2)")
  -- ---- wt/v051-tg-wob1: the Whelk's shell no longer draws the head in (no `kill_monsters MONSTER_2`, $F5 $08 $01
  -- $02, in its script): it calls the head in (set_battle_switch 0, 1: $F9 $01 $00 $01), and only behind the head's
  -- hold, `if_battle_switch_clr 0, 0` ($FC $15 $00 $00), in the same block: else a Broken head could be called in
  -- (bosses-wob.md block 1)
  do
    local start = rw(PTRS + 2 * 0x100)
    local x, guard, kills, calls, guarded = start, false, 0, 0, 0
    while rb(AI + x) ~= 0xFF do
      local b = rb(AI + x)
      if b == 0xFC and rb(AI + x + 1) == 0x15 and rb(AI + x + 2) == 0x00 and rb(AI + x + 3) == 0x00 then guard = true end
      if b == 0xF5 and rb(AI + x + 2) == 0x01 and rb(AI + x + 3) == 0x02 then kills = kills + 1 end
      if b == 0xF9 and rb(AI + x + 1) == 0x01 and rb(AI + x + 2) == 0x00 and rb(AI + x + 3) == 0x01 then
        calls = calls + 1
        if guard then guarded = guarded + 1 end
      end
      x = x + opSize(b)
      if b == 0xFE then guard = false end
    end
    H.log(string.format("[fuse] SHELL_GUARD: the shell's script draws the head in %d time(s); calls it in %d "
      .. "time(s), %d behind the hold", kills, calls, guarded))
    H.assertEq(kills == 0 and calls >= 1 and guarded == calls, true, "the Whelk's shell does not draw the head in, "
      .. "and calls it in only behind the head's hold (if_battle_switch_clr 0, 0 in the same block)")
  end
  -- ---- end wt/v051-tg-wob1 ----
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
    -- the break by LOCKE's Filch (Steal's Tools-window list, row $57), the Ot6TakeShields route (OT6's Break spell
    -- is battle_atmaweapon's: no member of this party knows it)
    via = { { name = "Filch", who = 0x01, cmd = 0x05, row = 0x57, filch = true } },
    arm = "idle",
    bossHp = 60000,
    -- (63 shields: a member's counterattack chips it while the party Defends -- wt/v051-tg-wob1's gate drew a party
    -- whose counters broke the staged 3 in the unbroken case, the roll's arming purged with the Broken turn)
    row = { max = 63, classes = 0x0F },
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
