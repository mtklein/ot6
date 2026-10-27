-- @suite savestate=worldmap_narshe
-- battle_nmiscratch.lua -- the battle NMI leaves OT6's battle scratch
-- ($3ecc-$3ed3) as the main thread left it.  The NMI draws the battle lists
-- (Ot6PreviewList_ext's fold, the list icons, the boost re-fold) with the
-- same scratch bytes the main thread's HUD walkers and battle math use; an
-- NMI that changed them mid-walk froze the Cultists' Tower battle for good
-- (the HUD's class walk shifting a zeroed OT6_SCR_BIT forever:
-- build/attempts/wt/v038-mirror-freeze/).  Ot6NmiScratchSave and
-- Ot6NmiScratchRestore_ext bracket the NMI's OT6 work.
--
--   asserts: across every NMI of a battle in which TERRA opens her magic
--   list, raises and lowers a boost (each re-folds the list inside the NMI)
--   and scrolls it, the eight bytes read at the NMI's exit equal the ones
--   read at its entry; and (the preconditions) NMIs really did run with the
--   magic list open, the list's own fold ran inside them, and at least one
--   NMI's work really changed the scratch before the bracket's restore: at
--   Ot6NmiScratchRestore_ext's entry the scratch differs from the save in
--   OT6_NMISCR.  On a ROM without the bracket (the unfixed build) the same
--   count is taken at IncGameTime_ext's entry inside the NMI, the call the
--   restore replaces, against the NMI's entry bytes, so the red half reads
--   a real change there too.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_MAGIC, ST_TRANS = 0x05, 0x0E, 0x01
local CMD_MAGIC = 0x02
local SCR, SCR_N = 0x7E3ECC, 8
local NMISCR = 0x7EEE23                         -- OT6_NMISCR (ot6_memory.inc)

local function pend(slot) return H.readByte(0x3e9d + slot * 2) end
local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot * 12 + r * 3) == cmd then return r end
  end
  return nil
end
local function worldReady()
  return (H.readWord(0x1f64) & 0x03ff) < 3
     and H.readByte(0x0019) == 0
     and (H.readByte(0x00e7) & 0x01) == 0
end
local function scratch()
  local t = {}
  for i = 0, SCR_N - 1 do t[i + 1] = H.readByte(SCR + i) end
  return t
end
local function hex(t)
  local s = {}
  for i = 1, #t do s[i] = string.format("%02X", t[i]) end
  return table.concat(s, " ")
end

-- the watch: NMI entry (BattleNMI) pushes the scratch, NMI exit (the rti it
-- falls through to, BattleIRQ) pops and compares.  A stack, so a nested
-- NMI (BattleNMI's own $46 guard path) pairs with its own entry.
local W = { nmis = 0, listNmis = 0, changed = 0, foldWrites = 0, undone = 0, stack = {}, refs = {} }
local function watchOn()
  local entry, exit = H.sym("BattleNMI"), H.sym("BattleIRQ")
  local fold = H.sym("Ot6FoldSteps")
  W.refs[#W.refs + 1] = { emu.addMemoryCallback(function()
    W.stack[#W.stack + 1] = { scratch(), H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_MAGIC }
    W.inNmi = (W.inNmi or 0) + 1
  end, emu.callbackType.exec, entry, entry), entry }
  W.refs[#W.refs + 1] = { emu.addMemoryCallback(function()
    local top = table.remove(W.stack)
    W.inNmi = math.max(0, (W.inNmi or 0) - 1)
    if not top then return end
    W.nmis = W.nmis + 1
    if top[2] then W.listNmis = W.listNmis + 1 end
    local now = scratch()
    if hex(now) ~= hex(top[1]) then
      W.changed = W.changed + 1
      if W.changed <= 8 then
        H.log(string.format("[nmiscratch] f%d NMI changed the scratch: entry %s exit %s (menu state %02X)",
          H.frame, hex(top[1]), hex(now), H.readByte(MSTATE)))
      end
    end
  end, emu.callbackType.exec, exit, exit), exit }
  -- the precondition's second half: the list fold runs inside the NMI
  W.refs[#W.refs + 1] = { emu.addMemoryCallback(function()
    if (W.inNmi or 0) > 0 then W.foldWrites = W.foldWrites + 1 end
  end, emu.callbackType.exec, fold, fold), fold }
  -- the third: a real change for the bracket to undo.  At the restore's
  -- entry the scratch is compared with the save it is about to put back;
  -- on a ROM without the restore, at IncGameTime_ext inside the NMI, with
  -- the NMI's entry bytes
  -- (the call spelled out: compose.py injects only the symbols a literal
  -- H.sym("...") names)
  local okR, restore = pcall(function() return H.sym("Ot6NmiScratchRestore_ext") end)
  W.restoreHook = okR and "Ot6NmiScratchRestore_ext" or "IncGameTime_ext"
  local at = okR and restore or H.sym("IncGameTime_ext")
  W.refs[#W.refs + 1] = { emu.addMemoryCallback(function()
    if (W.inNmi or 0) == 0 then return end
    local saved
    if okR then
      saved = {}
      for i = 0, SCR_N - 1 do saved[i + 1] = H.readByte(NMISCR + i) end
    else
      local top = W.stack[#W.stack]
      saved = top and top[1]
    end
    if saved and hex(saved) ~= hex(scratch()) then
      W.undone = W.undone + 1
      if W.undone <= 4 then
        H.log(string.format("[nmiscratch] f%d at %s: saved %s now %s", H.frame, W.restoreHook, hex(saved),
          hex(scratch())))
      end
    end
  end, emu.callbackType.exec, at, at), at }
end
local function watchOff()
  for _, r in ipairs(W.refs) do emu.removeMemoryCallback(r[1], emu.callbackType.exec, r[2], r[2]) end
  W.refs = {}
end

local terra
local mf = 0
-- TERRA's magic list, open: other characters defer with X (vanilla's turn
-- cycling), anything unknown backs out with B
local function toList()
  if H.readByte(MENU) == 0 then H.setPad({}); return end
  mf = mf + 1
  if (mf - 1) % 8 >= 4 then H.setPad({}); return end
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS or st == ST_MAGIC then H.setPad({}); return end
  local btn
  if act ~= terra then
    btn = (st == ST_CMD) and "x" or "b"
  elseif st == ST_CMD then
    local want = cmdRowOf(terra, CMD_MAGIC)
    local cur = H.readByte(CMDROW + terra) & 3
    if cur == want then btn = "a" else btn = (cur < want) and "down" or "up" end
  else
    btn = "b"
  end
  H.setPad(btn and { [btn] = true } or {})
end
local function listOpen()
  return H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == terra and H.readByte(MSTATE) == ST_MAGIC
end
local function press(btn, what)
  return H.seqStep({
    H.call(function() H.assertEq(listOpen(), true, "TERRA's magic list is still open before " .. what) end),
    H.pressButtons({ btn }, 6),
    H.waitFrames(30),
  })
end

local plan, idx, goal = nil, 1, { 82, 56 }
H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then
        if H.worldX() == goal[1] and H.worldY() == goal[2] then
          goal = (goal[2] == 56) and { 82, 50 } or { 82, 56 }
        end
        plan = H.worldBfs(goal[1], goal[2]); idx = 1
        if not plan or #plan == 0 then plan = nil; H.setPad({}); return end
      end
      local dir = plan[idx]; idx = idx + 1
      if not dir then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, "grass-area encounter"),
  H.release(),
  H.call(function() watchOn() end),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    for slot = 0, 3 do
      if H.readByte(0x3ED8 + slot * 2) == 0x00 then terra = slot end
    end
    H.assertEq(terra ~= nil, true, "TERRA is really in this party")
    H.assertEq(cmdRowOf(terra, CMD_MAGIC) ~= nil, true, "TERRA really has Magic to open")
  end),
  H.driveUntil(listOpen, 20000, { H.call(toList) }, "TERRA's magic list open"),
  H.waitFrames(30),
  -- each boost change re-folds the open list inside the NMI (OT6_RESTAGE,
  -- Ot6RestageGate_ext); each scroll redraws rows through ListTextCmd_0f
  press("r", "the first R"),
  H.call(function() H.assertEq(pend(terra), 1, "R raised TERRA's pending boost to 1") end),
  press("down", "a scroll down"), press("down", "a scroll down"), press("down", "a scroll down"),
  press("l", "the first L"),
  H.call(function() H.assertEq(pend(terra), 0, "L lowered it back to 0") end),
  press("up", "a scroll up"), press("up", "a scroll up"), press("up", "a scroll up"),
  press("r", "the second R"),
  press("down", "a scroll down"), press("down", "a scroll down"),
  press("l", "the second L"),
  press("up", "a scroll up"), press("up", "a scroll up"),
  H.waitFrames(60),
  H.call(function()
    watchOff()
    H.log(string.format("[nmiscratch] %d NMIs watched, %d with TERRA's magic list open, %d fold calls inside "
      .. "an NMI, %d NMIs whose work changed the scratch before %s, %d NMIs changed the scratch", W.nmis,
      W.listNmis, W.foldWrites, W.undone, W.restoreHook, W.changed))
    H.assertEq(W.listNmis >= 300, true, "the NMI ran with the magic list open (the precondition)")
    H.assertEq(W.foldWrites >= 1, true, "the list's fold (Ot6FoldSteps) ran inside the NMI (the precondition)")
    H.assertEq(W.undone >= 1, true, "an NMI's work really changed the scratch before " .. W.restoreHook
      .. " (the precondition: the bracket had a change to undo)")
    H.assertEq(W.changed, 0, "no NMI changed the main thread's battle scratch ($3ecc-$3ed3)")
  end),
})
