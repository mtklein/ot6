-- ot6.lua -- test-harness helpers for OT6 under Mesen 2's headless testrunner.
--
-- Usage pattern (see gen_battle_state.lua / battle_smoke.lua):
--
--   local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
--   H.run({ maxFrames = 60000 }, {
--     H.waitFrames(60),
--     H.pressButtons({ "start" }, 8),
--     H.waitUntil(function() return H.battleActive() end, 5000, "battle"),
--     H.call(function() H.assertEq(H.readByte(0x7E3ECB), 0xBA, "glyph") end),
--   })
--
-- The script is a LIST OF STEPS consumed one per frame by a startFrame event
-- callback.  Every step constructor returns a step object; steps that do
-- work without consuming a frame (call/log/hold/release) chain within the
-- same frame.  The script ALWAYS terminates: run() enforces a global frame
-- budget and calls emu.stop(2) if the steps outlive it.  Exit codes:
--   0 = steps completed         1 = Lua error / failed assert / timeout
--   2 = frame budget exceeded   (testrunner exit code = emu.stop code)
--
-- WHY NO COROUTINES: linear coroutine-style scripting was tried first and
-- crashed Mesen 2.1.1 intermittently-but-often (process exit 255, stdout
-- lost).  Callback-driven state machines have been stable across every long
-- run, so the library builds scripts as explicit step lists instead.
--
-- Environment notes (Mesen 2.1.1, discovered empirically):
--  * Lua 5.4.  io and os are nil (sandbox); print() goes to the testrunner's
--    stdout; emu.log() only goes to the GUI log window (invisible headless).
--  * dofile()/loadfile() DO work, so binary blobs are smuggled in/out as
--    base64: out via print("[b64:tag] ..."), in via generated .lua sidecars.
--    tools/tests/run.sh decodes [b64:*] payloads after each run.
--  * No controller is attached to any port in the testrunner's default
--    config (settings.json {}), so emu.setInput() is a no-op.  Input is
--    injected instead by intercepting CPU reads of the SNES auto-joypad
--    registers $4218/$4219 with a read-type memory callback.

local M = {}

-- ---------------------------------------------------------------- logging --
function M.log(msg)
  -- print goes to the testrunner's stdout.  Deliberately NOT emu.log():
  -- it is invisible under --testrunner and calling it from callbacks is a
  -- crash suspect (see README WORKING NOTES).
  print("[ot6] " .. tostring(msg))
end

-- ----------------------------------------------------------------- base64 --
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.b64encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = B64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        .. B64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        .. (b and B64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "=")
        .. (c and B64:sub(n % 64 + 1, n % 64 + 1) or "=")
  end
  return table.concat(out)
end

local B64INV = {}
for i = 1, #B64 do B64INV[B64:byte(i)] = i - 1 end

function M.b64decode(s)
  local out, n, bits = {}, 0, 0
  for i = 1, #s do
    local v = B64INV[s:byte(i)]
    if v then
      n = n * 64 + v
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        out[#out + 1] = string.char(math.floor(n / 2 ^ bits) % 256)
      end
    end
  end
  return table.concat(out)
end

-- Emit a binary blob to stdout as base64 chunks; run.sh decodes them.
-- "*.mss" tags land in build/states/<tag> (+ .lua sidecar); anything else in
-- build/states/shots/<tag>.
function M.emitBlob(tag, data)
  local enc = M.b64encode(data)
  for i = 1, #enc, 4000 do
    print("[b64:" .. tag .. "] " .. enc:sub(i, i + 3999))
  end
  M.log("emitted blob '" .. tag .. "' (" .. #data .. " bytes)")
end

-- ------------------------------------------------------------------ input --
-- SNES auto-joypad bit layout for pad 1:
--   $4219 (high): B Y Select Start Up Down Left Right
--   $4218 (low):  A X L R 0 0 0 0
local BTN = {
  a = { 0, 0x80 }, x = { 0, 0x40 }, l = { 0, 0x20 }, r = { 0, 0x10 },
  b = { 1, 0x80 }, y = { 1, 0x40 }, select = { 1, 0x20 }, start = { 1, 0x10 },
  up = { 1, 0x08 }, down = { 1, 0x04 }, left = { 1, 0x02 }, right = { 1, 0x01 },
}
local padLo, padHi = 0, 0

-- Always substitute the joypad registers (0 = nothing held).  The values are
-- bit-identical to a real idle/held standard pad, and this always-on
-- configuration is the one proven stable across many long headless runs.
emu.addMemoryCallback(function(addr)
  if addr == 0x4218 then return padLo end
  if addr == 0x4219 then return padHi end
end, emu.callbackType.read, 0x4218, 0x4219)

-- Immediately set the held-button set ({"a","down"} or {a=true,down=true}).
-- (Plain function; the step-flavored wrappers are below.)
function M.setPad(buttons)
  padLo, padHi = 0, 0
  for k, v in pairs(buttons or {}) do
    local name = (type(k) == "number") and v or (v and k or nil)
    local s = name and BTN[name]
    if s then
      if s[1] == 0 then padLo = padLo | s[2] else padHi = padHi | s[2] end
    elseif name then
      error("unknown button: " .. tostring(name))
    end
  end
end

-- ----------------------------------------------------------------- memory --
-- WRAM helpers accept either a $7E-prefixed SNES address (0x7E0000..0x7FFFFF)
-- or a plain offset into the 128 KiB of work RAM (0x0000..0x1FFFF).
local function wramOffset(addr)
  if addr >= 0x7E0000 then return addr - 0x7E0000 end
  return addr
end

function M.readByte(addr) return emu.read(wramOffset(addr), emu.memType.snesWorkRam) end
function M.readWord(addr) return emu.readWord(wramOffset(addr), emu.memType.snesWorkRam) end
function M.writeByte(addr, v) emu.write(wramOffset(addr), v, emu.memType.snesWorkRam) end
function M.writeWord(addr, v) emu.writeWord(wramOffset(addr), v, emu.memType.snesWorkRam) end

-- PRG ROM (file offset into the headerless .sfc image).
function M.readRomByte(addr) return emu.read(addr, emu.memType.snesPrgRom) end
function M.readRomWord(addr) return emu.readWord(addr, emu.memType.snesPrgRom) end

-- ----------------------------------------------------------------- assert --
function M.assertEq(got, want, what)
  if got ~= want then
    local fmt = function(v)
      if type(v) == "number" then return string.format("%d ($%X)", v, v) end
      return tostring(v)
    end
    error(string.format("assertEq failed: %s: got %s, want %s",
      what or "?", fmt(got), fmt(want)), 2)
  end
  M.log("ok: " .. (what or "assertEq") .. " = " .. tostring(got))
end

-- ------------------------------------------------------------- savestates --
-- Mesen's sandboxed Lua cannot write files, so savestates round-trip through
-- stdout: saveState() emits the blob as [b64:<name>] lines and run.sh writes
--   build/states/<name>          (raw Mesen savestate, loadable in the GUI)
--   build/states/<name>.lua      (sidecar: `return "<base64>"`)
-- loadState() reads the sidecar back via loadfile().
function M.saveState(name)
  local blob = emu.createSavestate()
  assert(type(blob) == "string" and #blob > 0, "createSavestate returned nothing")
  M.emitBlob(name, blob)
  return #blob
end

function M.loadState(sidecarPath)
  local base = sidecarPath:match("[^/]+$")
  local b64
  if type(OT6_STATES) == "table" and OT6_STATES[base] then
    -- normal path: lib/compose.py embedded the sidecar at compose time
    -- (runtime loadfile() is avoided -- file loading in this sandbox has
    -- crashed the emulator; see README WORKING NOTES).
    b64 = OT6_STATES[base]
  else
    local chunk, err = loadfile(sidecarPath)
    assert(chunk, "cannot load savestate sidecar " .. sidecarPath ..
      " (not embedded, loadfile failed: " .. tostring(err) .. ")")
    b64 = chunk()
  end
  local blob = M.b64decode(b64)
  assert(#blob > 0, "empty savestate blob for " .. sidecarPath)
  emu.loadSavestate(blob)
  return #blob
end

-- ------------------------------------------------------------ screenshots --
-- emu.takeScreenshot() works headless and returns a 256x224 PNG string
-- (empty string during the first ~100 frames, before the first decoded
-- frame).  The file itself is written by run.sh: build/states/shots/<tag>.png
function M.screenshot(tag)
  local ok, png = pcall(emu.takeScreenshot)
  if ok and type(png) == "string" and #png > 0 then
    M.emitBlob(tag .. ".png", png)
    return #png
  end
  M.log("screenshot '" .. tag .. "' unavailable (no decoded frame yet)")
  return 0
end

-- ----------------------------------------------------- FF6 battle signals --
-- $7E3F46: 6 x 16-bit monster IDs for the current battle ($FFFF = empty
-- slot; note monster #0 "Guard" is a valid 0x0000).  $7E3BF4: 4 x 16-bit
-- party battle HP ($FFFF outside battle).  $7E3ECB: OT6 break-system digit
-- glyph ($B4-$BD) while the battle UI is live.
M.MONSTER_IDS = 0x3F46
M.BATTLE_HP = 0x3BF4
M.BREAK_GLYPH = 0x3ECB

function M.monsterIds()
  local ids = {}
  for i = 0, 5 do ids[i + 1] = M.readWord(M.MONSTER_IDS + i * 2) end
  return ids
end

function M.monstersPresent()
  local n = 0
  for _, id in ipairs(M.monsterIds()) do
    if id ~= 0xFFFF then n = n + 1 end
  end
  return n
end

function M.partyHp()
  local hp = {}
  for i = 0, 3 do hp[i + 1] = M.readWord(M.BATTLE_HP + i * 2) end
  return hp
end

-- True once the battle module has begun loading: the party battle-HP table
-- fills in (it reads $FFFF while in the field module).
function M.battleLoadStarted()
  local hp = M.readWord(M.BATTLE_HP)
  return hp ~= 0xFFFF and hp ~= 0 and hp < 10000
end

-- Cheap "is anything on screen" check: an all-black 256x224 screenshot
-- compresses to ~750 bytes; real scenes are several KB.
function M.screenLooksAlive()
  local ok, png = pcall(emu.takeScreenshot)
  return ok and type(png) == "string" and #png > 2000
end

-- True while a battle is fully up and RENDERING.  A crashed battle load
-- (which this harness has caught) leaves the screen permanently black and
-- fails this.  emu.getState() is deliberately not used here: polling it was
-- correlated with emulator crashes.
function M.battleActive()
  return M.battleLoadStarted() and M.monstersPresent() > 0 and M.screenLooksAlive()
end

-- ------------------------------------------------------- the step runner --
-- A STEP is a table { tick = function(self) return "frame"|"done" end }.
-- "frame" = consumed this frame, call again next frame; "done" = advance.
-- Steps are built fresh per run; constructors below close over their state.

M.frame = 0

local function seqStep(steps)
  return {
    i = 1,
    tick = function(self)
      while self.i <= #steps do
        local r = steps[self.i]:tick()
        if r == "frame" then return "frame" end
        self.i = self.i + 1
      end
      return "done"
    end,
    reset = function(self)
      self.i = 1
      for _, s in ipairs(steps) do
        if s.reset then s:reset() end
      end
    end,
  }
end

-- Wait n frames.
function M.waitFrames(n)
  local c = 0
  return {
    tick = function()
      if c < n then
        c = c + 1
        return "frame"
      end
      return "done"
    end,
    reset = function() c = 0 end,
  }
end

-- Run fn() once (no frame consumed).  fn may call any H.* plain function;
-- everything executes inside the frame callback, on Mesen's main Lua state.
function M.call(fn)
  return { tick = function() fn() return "done" end }
end

-- Log a message (or the result of a function) without consuming a frame.
function M.logStep(msg)
  return M.call(function() M.log(type(msg) == "function" and msg() or msg) end)
end

-- Hold/release as steps.
function M.hold(buttons) return M.call(function() M.setPad(buttons) end) end
function M.release() return M.call(function() M.setPad(nil) end) end

-- Hold `buttons` for `frames` frames (default 4), release, wait 2 frames.
function M.pressButtons(buttons, frames)
  return seqStep({
    M.hold(buttons), M.waitFrames(frames or 4),
    M.release(), M.waitFrames(2),
  })
end

-- Wait until pred() is truthy, polling every pollEvery frames (default 1).
-- Raises (-> FAIL, exit 1) after maxFrames.
function M.waitUntil(pred, maxFrames, what, pollEvery)
  what = what or "condition"
  pollEvery = pollEvery or 1
  local waited = 0
  return {
    tick = function()
      if waited % pollEvery == 0 and pred() then
        M.log("waitUntil '" .. what .. "' satisfied after " .. waited .. " frames")
        return "done"
      end
      waited = waited + 1
      if waited > maxFrames then
        error("timeout after " .. maxFrames .. " frames waiting for " .. what, 0)
      end
      return "frame"
    end,
    reset = function() waited = 0 end,
  }
end

-- Like waitUntil but never raises: records the outcome in H.vars[name]
-- (true/false) for a later M.cond branch.
function M.waitUntilSoft(pred, maxFrames, name, pollEvery)
  pollEvery = pollEvery or 1
  local waited = 0
  return {
    tick = function()
      if waited % pollEvery == 0 and pred() then
        M.vars[name] = true
        return "done"
      end
      waited = waited + 1
      if waited > maxFrames then
        M.vars[name] = false
        return "done"
      end
      return "frame"
    end,
    reset = function() waited = 0 end,
  }
end

M.vars = {}

-- Branch: choose a step list by predicate at the moment it is reached.
function M.cond(pred, thenSteps, elseSteps)
  local chosen = nil
  return {
    tick = function()
      if chosen == nil then
        chosen = pred() and seqStep(thenSteps) or seqStep(elseSteps or {})
      end
      return chosen:tick()
    end,
  }
end

-- Repeat a step list n times.
function M.repeatN(n, steps)
  local body, done = seqStep(steps), 0
  return {
    tick = function()
      while done < n do
        local r = body:tick()
        if r == "frame" then return "frame" end
        done = done + 1
        body:reset()
      end
      return "done"
    end,
  }
end

-- Run the body steps in a loop until pred() is truthy (checked between body
-- cycles and every frame via pollEvery=frames).  Raises after maxFrames.
function M.driveUntil(pred, maxFrames, steps, what)
  what = what or "condition"
  local body = seqStep(steps)
  local waited = 0
  return {
    tick = function()
      if pred() then
        M.log("driveUntil '" .. what .. "' satisfied after " .. waited .. " frames")
        return "done"
      end
      waited = waited + 1
      if waited > maxFrames then
        error("timeout after " .. maxFrames .. " frames driving toward " .. what, 0)
      end
      local r = body:tick()
      if r == "done" then body:reset() end
      return "frame"
    end,
  }
end

-- The runner.  steps: list of step objects.  opts.maxFrames: global budget.
local runnerStarted = false
function M.run(opts, steps)
  assert(not runnerStarted, "ot6.run() called twice")
  runnerStarted = true
  opts = opts or {}
  local budget = opts.maxFrames or 60000
  local root = seqStep(steps)
  local finished = false

  emu.addEventCallback(function()
    if finished then return end
    M.frame = M.frame + 1
    if M.frame > budget then
      finished = true
      M.log("FAIL: frame budget exceeded (" .. budget .. " frames)")
      emu.stop(2)
      return
    end
    local ok, r = pcall(root.tick, root)
    if not ok then
      finished = true
      M.log("FAIL: " .. tostring(r))
      emu.stop(1)
    elseif r == "done" then
      finished = true
      M.log("PASS (frame " .. M.frame .. ")")
      emu.stop(0)
    end
  end, emu.eventType.startFrame)
end

return M
