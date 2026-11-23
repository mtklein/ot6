-- @suite savestate=kolts_cave
-- battle_stophead.lua -- a Stopped monster's queued turn is consumed only when
-- it has not begun: Ot6BrokenTurn's Stop arm with a command-list head other
-- than $1f (#546, #553).
--
-- Ot6BrokenTurn (ot6_break.asm) reads a monster's command list as ExecAction
-- takes its queue entry.  A Stopped monster whose list head is command $1f
-- (the AI script's turn, queued before the Stop landed: a pin, Fenrir's) has
-- that turn consumed as a Broken one's is; a head that is any other command
-- is the rest of a turn the script had already begun, which vanilla holds
-- while Stopped ($3AA0 bit 4 at ExecAction @016d) and runs once the Stop
-- ends, so the arm hands the list back untouched.
--
-- Play does not reach the second case: a monster's later commands each run in
-- their own ExecAction as they come up, so no monster is ever Stopped with a
-- non-$1f head when its queue entry is taken (#553: four battles against the
-- Retainers, none).  So it is staged.  DECLARED SYNTHETIC SETUP
-- (tools/state_write_waivers.txt): at the entry of Ot6BrokenTurn for the
-- first monster whose queued turn reaches ExecAction (X = its entity offset,
-- the list's head command $1f, not Broken, not Stopped), this suite writes
--   * Stop in the engine's own shape, battle_stopwindow's: $3EF8,x bit 4, the
--     $3AF1,x counter at $12 (SetStatus_14) and $3AA0,x bit 4 (the gauge
--     hold);
--   * case "rest" only: the head entry's command ($3420 + 2*head) from $1f to
--     $00, a Fight: the rest of a turn its script had begun.
-- That is the whole write; everything after is the engine's.  Observed at
-- Ot6NoActionMark, the instruction after `jsl Ot6BrokenTurn` (A = what it
-- handed back):
--   case "turn" (the control; head $1f): A = $FF, the turn consumed -- the
--     staging reaches the Stop arm;
--   case "rest" (head $00): A = the list's head pointer, the list untouched.
-- Both cases branch from one snapshot at the battle's open, so they meet the
-- same monster's same turn.  A mechanism test, not play.
--
-- The battle is a natural Mt. Kolts cave encounter paced into from
-- kolts_cave; the party Defends (H.kitBattle, an empty plan).  Varying the
-- draw: a lab sets PACE_BURN (encounters used up first) ahead of the file,
-- and OT6_SEED_SHIFT moves the battle's RNG; runs in build/attempts/wt/v051-tests/stophead/.
-- Mutant stop_any_head (`C9 1F F0` -> `C9 1F 80` in Ot6BrokenTurn: every
-- Stopped head is consumed) is red at "rest".
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local ST3, STOP_COUNT, ATBFLAGS, BROKEN, LISTPTR, LISTCMD = 0x3EF8, 0x3AF1, 0x3AA0, 0x3E88, 0x32CC, 0x3420
local STOP, STOP_TICKS, CMD_TURN, CMD_FIGHT = 0x10, 0x12, 0x1F, 0x00
local function map() return H.mapId() & 0x1ff end

local case = nil          -- "turn" or "rest" while armed
local staged = nil        -- { x, head, f } once the staging has been written
local seen = nil          -- { a, ptr, f } what Ot6BrokenTurn handed back
local results = {}
H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),
  H.paceToEncounter("stophead"),
  H.call(function()
    local w = {}
    for _, f in ipairs(H.formationWords()) do w[#w + 1] = string.format("%03X", f) end
    H.log(string.format("[stophead] the cave drew %s; $BE $%02X", table.concat(w, " "), H.readByte(0xBE)))
    local bt = H.sym("Ot6BrokenTurn")
    emu.addMemoryCallback(function()
      if case == nil or staged ~= nil then return end
      local x = emu.getState()["cpu.x"] & 0xFF
      if x < 8 or x > 18 or x % 2 ~= 0 then return end
      local head = H.readByte(LISTPTR + x)
      if head >= 0x80 or H.readByte(BROKEN + x) ~= 0 or (H.readByte(ST3 + x) & STOP) ~= 0 then return end
      if H.readByte(LISTCMD + head * 2) ~= CMD_TURN then return end
      -- the declared staging (see the header)
      H.writeByte(ST3 + x, H.readByte(ST3 + x) | STOP)
      H.writeByte(STOP_COUNT + x, STOP_TICKS)
      H.writeByte(ATBFLAGS + x, H.readByte(ATBFLAGS + x) | 0x10)
      if case == "rest" then H.writeByte(LISTCMD + head * 2, CMD_FIGHT) end
      staged = { x = x, head = head, f = H.frame }
      H.log(string.format("[stophead] f%d case %s: monster entity %d's queued turn reaches ExecAction (head $%02X): "
        .. "Stopped%s", H.frame, case, x, head, case == "rest" and ", head command $1F -> $00" or ""))
    end, emu.callbackType.exec, bt, bt)
    local na = H.sym("Ot6NoActionMark")
    emu.addMemoryCallback(function()
      if staged == nil or seen ~= nil then return end
      local st = emu.getState()
      if (st["cpu.x"] & 0xFF) ~= staged.x then return end
      seen = { a = st["cpu.a"] & 0xFF, ptr = H.readByte(LISTPTR + staged.x), f = H.frame }
      H.log(string.format("[stophead] f%d case %s: Ot6BrokenTurn handed back $%02X; the list's head now $%02X",
        H.frame, case, seen.a, seen.ptr))
    end, emu.callbackType.exec, na, na)
  end),
  H.lazy(function()
    local snap, req = nil, nil
    local steps = { H.call(function() snap = H.requestSaveState() end), H.waitFrames(2),
      H.call(function() H.checkReq(snap, "the snapshot at the battle's open") end) }
    for i, c in ipairs({ "turn", "rest" }) do
      steps[#steps + 1] = H.call(function()
        if i > 1 then H.setPad({}); req = H.requestLoadState(snap.blob) end
      end)
      steps[#steps + 1] = H.waitFrames(2)
      steps[#steps + 1] = H.call(function()
        if i > 1 then H.checkReq(req, "the battle's open"); H.rearmInputInjection() end
        case, staged, seen = c, nil, nil
        H.log(string.format("[stophead] case %s, from the battle's open", c))
      end)
      steps[#steps + 1] = H.kitBattle({}, { idle = "defend", maxFrames = 20000, care = false,
        giveUp = function() return seen ~= nil end })
      steps[#steps + 1] = H.call(function()
        H.assertEq(seen ~= nil, true, string.format("case %s: a monster's queued turn reached ExecAction and was "
          .. "staged before the battle ended", c))
        results[c] = { staged = staged, seen = seen }
        case = nil
      end)
    end
    return H.seqStep(steps)
  end),
  H.call(function()
    local t, r = results.turn, results.rest
    H.assertEq(t.staged.x, r.staged.x, "both cases meet the same monster's turn (one snapshot)")
    H.assertEq(t.seen.a, 0xFF, string.format("control: a Stopped monster whose head is command $1F has the turn "
      .. "consumed (Ot6BrokenTurn hands back $FF; entity %d)", t.staged.x))
    H.assertEq(r.seen.a, r.staged.head, string.format("a Stopped monster whose head is another command keeps it: "
      .. "Ot6BrokenTurn hands back the list's head $%02X, not $FF (entity %d)", r.staged.head, r.staged.x))
    H.log("[stophead] PASS: the Stop arm consumes a turn not yet begun and keeps the rest of one begun")
  end),
})
