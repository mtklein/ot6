-- @manual
-- probe_list_scroll.lua -- which cells move while a battle list scrolls,
-- and which stop when the list has hit its end under a DOWN still held.
--
--   tools/tests/run.sh tools/tests/probe_list_scroll.lua build/states/list_scroll.log
--   OT6_WATCHDOG=1 tools/tests/run.sh tools/tests/probe_list_scroll.lua build/states/list_scroll_enforce.log
--
-- vector_crash (2026-09-16) failed no-effect on all three attempts while
-- the fight driver walked the item list 43 rows to the Potion: the
-- watchdog's battle signature read actor 0's $890F/$891F and the menu
-- state, which only alternates between the list ($0A) and its scroll
-- animation ($17), and the in-window row sat on its last line while the
-- scroll offset walked.  The list windows keep their cursors in the
-- per-actor block $890F..$896E (btlgfx_ram.inc; UpdateMenuState_0a/0e/
-- 1b/1e/2d/30 in btlgfx_main.asm), one byte per actor indexed by $62CA.
--
-- This probe opens each list the party has (item, magic, tools on
-- vargas_entry; throw on forest_done's train random; rage on gau_joined's
-- Veldt random), presses DOWN the way the fight driver does (5-on/5-off,
-- distinct presses, no auto-repeat) until the block has sat still for
-- 360 frames -- the list's end -- and then keeps pressing 420 frames
-- more.  Every 8 frames it samples the block plus the menu state and logs
-- one `[scroll]` line per change naming the cells that moved; each list
-- ends with a `[scroll] <list> summary` line: per-cell change counts, the
-- frame the end was reached, and what (if anything) moved while DOWN was
-- pressed past it.  The second command line runs the same body with the
-- watchdogs enforcing: the expected verdict is a no-effect FAIL ~300
-- frames after the first list's end, and no trip while it scrolls.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, MSTATE, ACTOR, CMDTBL, CMDROW, BCHID =
  0x7BCA, 0x7BC2, 0x62CA, 0x202E, 0x890F, 0x3ED8
local ST_CMD, ST_TGT = 0x05, 0x38
local LISTS = {
  { name = "item",  cmd = 0x01, st = 0x0A },
  { name = "magic", cmd = 0x02, st = 0x0E },
  { name = "tools", cmd = 0x09, st = 0x30 },
  { name = "throw", cmd = 0x08, st = 0x2D },
  { name = "rage",  cmd = 0x10, st = 0x1E },
  { name = "lore",  cmd = 0x0C, st = 0x1B },
}
local CELLS = {
  { 0x890F, "cmd" },
  { 0x8913, "mag.s" }, { 0x8917, "mag.c" }, { 0x891B, "mag.r" },
  { 0x891F, "lore.s" }, { 0x8923, "lore.c" }, { 0x8927, "lore.r" },
  { 0x892B, "rage.s" }, { 0x892F, "rage.c" }, { 0x8933, "rage.r" },
  { 0x8937, "s21.a" }, { 0x893B, "s21.b" },
  { 0x893F, "mtek.a" }, { 0x8943, "mtek.b" },
  { 0x8947, "item.s" }, { 0x894B, "item.c" }, { 0x894F, "item.r" },
  { 0x8953, "throw.s" }, { 0x8957, "throw.c" }, { 0x895B, "throw.r" },
  { 0x895F, "tools.s" }, { 0x8963, "tools.c" }, { 0x8967, "tools.r" },
  { 0x896B, "x896B" },
  -- not in the block, sampled alongside for the record
  { 0x7BC2, "mstate", abs = true }, { 0x7BD4, "winscr", abs = true },
  { 0x7BBB, "pending", abs = true },
}
local END_QUIET, PAST_END = 360, 420

local function st() return H.readByte(MSTATE) end
local function actor() return H.readByte(ACTOR) & 3 end
local function cmdRowOf(a, cmd)
  for row = 0, 3 do
    if H.readByte(CMDTBL + a * 12 + row * 3) == cmd then return row end
  end
  return nil
end
local function sample(a)
  local t = {}
  for i, c in ipairs(CELLS) do
    t[i] = H.readByte(c.abs and c[1] or (c[1] + a))
  end
  return t
end
local function padStr(p) return p.down and "down" or (p.b and "b" or (p.a and "a" or "--")) end

local measured = {}
-- the state machine, rebuilt per fixture stanza
local function listWalker(fixture, wanted, budget)
  local mode, cur, a0, s0 = "cmd", nil, nil, nil
  local walkStart, lastMove, endFrame, pastMoves, openStart = 0, 0, nil, 0, 0
  local counts, lastAt, logged, pad = {}, {}, 0, {}
  local ph, tick = 0, 0
  local function press(b) pad = { [b] = true }; H.setPad(tick % 10 < 5 and pad or {}) end
  local function summary()
    local parts = {}
    for i, c in ipairs(CELLS) do
      if counts[i] then
        parts[#parts + 1] = string.format("%s x%d (last f%d)", c[2], counts[i], lastAt[i])
      end
    end
    H.log(string.format("[scroll] %s summary (%s, actor %d char %d): walk from f%d, "
      .. "end reached at f%d (%d frames, block still %d frames); cells moved: %s; "
      .. "DOWN pressed %d frames past the end: %d block/menu-state changes",
      cur.name, fixture, a0, H.readByte(BCHID + a0 * 2), walkStart,
      endFrame or -1, (endFrame or H.frame) - walkStart, END_QUIET,
      #parts > 0 and table.concat(parts, ", ") or "NONE",
      PAST_END, pastMoves))
  end
  local function allDone()
    for _, l in ipairs(wanted) do if not measured[l.name] then return false end end
    return true
  end
  return H.driveUntil(function()
    return allDone() or not H.battleLoadStarted()
  end, budget, {
    H.call(function()
      tick = tick + 1
      ph = (ph + 1) % 8
      if H.readByte(MENU) == 0 then H.setPad(ph < 2 and { "a" } or {}); return end
      local s, a = st(), actor()
      if mode == "cmd" then
        if s == ST_TGT then H.setPad(ph < 3 and { "a" } or {}); return end
        if s ~= ST_CMD then H.setPad({}); return end
        cur = nil
        for _, l in ipairs(wanted) do
          if not measured[l.name] and cmdRowOf(a, l.cmd) then cur = l; break end
        end
        local row = cur and cmdRowOf(a, cur.cmd) or (cmdRowOf(a, 0x00) or 0)
        local c = H.readByte(CMDROW + a) & 3
        if c ~= row then press(c < row and "down" or "up"); return end
        if cur then
          mode, a0, openStart = "open", a, H.frame
          H.log(string.format("[scroll] %s: actor %d char %d, command row %d; opening",
            cur.name, a, H.readByte(BCHID + a * 2), row))
        end
        press("a"); return
      end
      if mode == "open" then
        if s == cur.st then
          mode = "walk"; walkStart, lastMove = H.frame, H.frame
          s0 = sample(a0); counts, lastAt, logged, pastMoves = {}, {}, 0, 0
          local parts = {}
          for i, c in ipairs(CELLS) do parts[#parts + 1] = string.format("%s=%02X", c[2], s0[i]) end
          H.log(string.format("[scroll] %s open at f%d: %s", cur.name, H.frame, table.concat(parts, " ")))
          H.screenshot("scroll_" .. cur.name .. "_open")
          press("down"); return
        end
        if s == ST_CMD and H.frame - openStart > 600 then
          H.log(string.format("[scroll] %s: window did not open (st=%02X); skipping", cur.name, s))
          measured[cur.name] = "skipped"; mode = "cmd"; return
        end
        press("a"); return
      end
      if mode == "walk" or mode == "past" then
        if s ~= cur.st and s ~= 0x17 and not (cur.name == "item" and s == 0x18) then
          H.log(string.format("[scroll] %s: left the list at f%d (st=%02X, menu=%02X); abandoning",
            cur.name, H.frame, s, H.readByte(MENU)))
          if endFrame then summary() end
          measured[cur.name] = "abandoned"; mode = "cmd"; H.setPad({}); return
        end
        press("down")
        if H.frame % 8 == 0 then
          local s1 = sample(a0)
          local diffs = {}
          for i, c in ipairs(CELLS) do
            if s1[i] ~= s0[i] then
              counts[i] = (counts[i] or 0) + 1; lastAt[i] = H.frame
              diffs[#diffs + 1] = string.format("%s %02X->%02X", c[2], s0[i], s1[i])
              if not c.abs or c[2] == "mstate" then lastMove = H.frame end
              if mode == "past" then pastMoves = pastMoves + 1 end
            end
          end
          if #diffs > 0 and (logged < 12 or mode == "past" or H.frame % 64 == 0) then
            logged = logged + 1
            H.log(string.format("[scroll] %s f%d pad=%s st=%02X %s: %s", cur.name,
              H.frame, padStr(pad), s, mode, table.concat(diffs, ", ")))
          end
          s0 = s1
          if mode == "walk" and H.frame - lastMove >= END_QUIET then
            endFrame = lastMove
            H.log(string.format("[scroll] %s: end reached at f%d (block still %d frames); "
              .. "pressing DOWN %d more frames", cur.name, endFrame, END_QUIET, PAST_END))
            H.screenshot("scroll_" .. cur.name .. "_end")
            mode = "past"
          elseif mode == "past" and H.frame - endFrame - END_QUIET >= PAST_END then
            summary()
            measured[cur.name] = "measured"; mode = "close"
          end
        end
        return
      end
      if mode == "close" then
        if s == ST_CMD then mode = "cmd"; H.setPad({}); return end
        press("b"); return
      end
    end),
  }, fixture .. ": walk every list to its end")
end

local function jiggle(what, budget)
  local ph = 0
  return H.driveUntil(function() return H.battleLoadStarted() end, budget or 20000, {
    H.call(function()
      ph = (ph + 1) % 64
      if H.dialogWaiting() then H.setPad(ph % 8 < 4 and { "a" } or {}); return end
      local w = H.worldMode and H.worldMode()
      local ctl = w and H.worldHasControl() or H.hasControl()
      local al = w and H.worldAligned() or H.tileAligned()
      if ctl and al then H.setPad(ph < 32 and { left = true } or { right = true })
      else H.setPad({}) end
    end),
  }, what)
end

local function stanza(fixture, path, entry, wanted)
  local L = {}
  for _, n in ipairs(wanted) do
    for _, l in ipairs(LISTS) do if l.name == n then L[#L + 1] = l end end
  end
  local steps = {
    H.loadState(path),
    H.waitFrames(60),
  }
  if entry == "a" then
    local ph = 0
    steps[#steps + 1] = H.waitUntil(function() return H.hasControl() end, 900, fixture .. " field control", 5)
    steps[#steps + 1] = H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
      H.call(function() ph = (ph + 1) % 12; H.setPad(ph < 4 and { "a" } or {}) end),
    }, fixture .. ": A opens the fight")
  else
    steps[#steps + 1] = jiggle(fixture .. ": a random rolls")
  end
  steps[#steps + 1] = H.release()
  steps[#steps + 1] = H.waitUntil(function() return H.battleActive() end, 900, fixture .. " battle active", 15)
  steps[#steps + 1] = H.waitFrames(120)
  steps[#steps + 1] = listWalker(fixture, L, 30000)
  steps[#steps + 1] = H.release()
  steps[#steps + 1] = H.call(function()
    local parts = {}
    for _, l in ipairs(L) do parts[#parts + 1] = l.name .. "=" .. tostring(measured[l.name]) end
    H.log(string.format("[scroll] %s done: %s", fixture, table.concat(parts, " ")))
  end)
  return steps
end

local steps = {}
-- literal sidecar paths: compose.py finds them by scanning the script
for _, s in ipairs(stanza("vargas_entry", "build/states/vargas_entry.mss.lua", "a",
    { "item", "magic", "tools" })) do steps[#steps + 1] = s end
for _, s in ipairs(stanza("forest_done", "build/states/forest_done.mss.lua", "jiggle",
    { "throw" })) do steps[#steps + 1] = s end
for _, s in ipairs(stanza("gau_joined", "build/states/gau_joined.mss.lua", "jiggle",
    { "rage" })) do steps[#steps + 1] = s end

H.run({ maxFrames = 120000, retries = 1 }, steps)
