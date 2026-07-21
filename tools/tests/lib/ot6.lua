-- ot6.lua -- test-harness helpers for OT6 under Mesen 2's headless testrunner.
--
-- Usage pattern (see gen_battle_state.lua / battle_smoke.lua):
--
--   local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
--   H.run({ maxFrames = 60000 }, {
--     H.waitFrames(60),
--     H.pressButtons({ "start" }, 8),
--     H.waitUntil(function() return H.battleActive() end, 5000, "battle"),
--     H.call(function() H.assertEq(H.readByte(0x7E3E44), 2, "shields") end),
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
-- WHY STEP LISTS: the library builds scripts as explicit step lists driven
-- by a startFrame callback.  This was originally justified by "coroutines
-- crash Mesen" -- they do not; that was the testrunner's wall-clock cap
-- (exit 255, stdout lost) misread as a crash, and coroutines run clean.
-- The step style stays because the whole suite is written in it.
--
-- Environment notes (Mesen 2.1.1, verified against Mesen's source):
--  * Lua 5.4.  print() goes to the testrunner's stdout.  emu.log() goes to
--    the SCRIPT log, which nothing reads headless -- and --enableStdout does
--    NOT mirror it (that flag mirrors the emulator message log).  Lua errors
--    and watchdog kills land there too, i.e. silently.  print() or nothing.
--  * io/os are nil and dofile()/loadfile() raise, but that is the setting
--    Debug.ScriptWindow.AllowIoOsAccess (default false), not a fixed
--    sandbox.  We keep it off and inline everything at compose time, so
--    binary blobs travel as base64: out via print("[b64:tag] ..."), in via
--    compose-time embedding.  run.sh decodes [b64:*] payloads after a run.
--  * Port 0 is a SnesController in the test config, so emu.setInput() is
--    live; input is pushed from an inputPolled callback (see below).

local M = {}

local seqStep -- forward declaration (defined in the step-runner section)

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
      n = (n << 6) | v
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        out[#out + 1] = string.char((n >> bits) & 0xFF)
        n = n & ((1 << bits) - 1) -- keep only the leftover bits (precision!)
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
-- Controller input the proper Mesen way: emu.setInput(input, port) applied
-- inside an `inputPolled` event callback -- the officially recommended
-- pattern (setInput's effect lasts until the next poll, so applying it on
-- every poll guarantees the ROM latches our state each frame).  Port 0 is a
-- SnesController in the test config, so setInput is live.
local ALL_BTN = { "a", "b", "x", "y", "l", "r", "select", "start",
                  "up", "down", "left", "right" }
local curPad = {}
for _, b in ipairs(ALL_BTN) do curPad[b] = false end

local inputCbRef = nil

-- (Re)register the inputPolled callback that pushes curPad into the
-- emulator.  Idempotent; call sites re-arm defensively after savestate
-- loads.
function M.rearmInputInjection()
  if not inputCbRef then
    inputCbRef = emu.addEventCallback(function()
      emu.setInput(curPad, 0)             -- NB: (input, port) -- input first!
    end, emu.eventType.inputPolled)
  end
end
M.rearmInputInjection()

function M.disableInputInjection()
  if inputCbRef then
    pcall(emu.removeEventCallback, inputCbRef, emu.eventType.inputPolled)
    inputCbRef = nil
    M.log("input injection disabled (inputPolled callback removed)")
  end
end

-- Set the held-button set ({"a","down"} or {a=true,down=true}); every other
-- button is released (the script fully owns the pad -- no human player).
function M.setPad(buttons)
  for _, b in ipairs(ALL_BTN) do curPad[b] = false end
  for k, v in pairs(buttons or {}) do
    local name = (type(k) == "number") and v or (v and k or nil)
    if name then
      if curPad[name] == nil then error("unknown button: " .. tostring(name)) end
      curPad[name] = true
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

-- OT6 symbol address, derived from ff6/rom/ff6-en.dbg at COMPOSE time and
-- injected as the global OT6_SYMS (lib/compose.py, the same mechanism that
-- embeds savestate sidecars as OT6_STATES).  Returns the ca65 `val`: a 24-bit
-- SNES *CPU* address (e.g. RandA = 0xC24B98) -- exactly what an exec/read
-- memory callback wants.  For a snesPrgRom FILE offset (readRomByte/Word),
-- mask & 0x3FFFFF: banks $C0-$FF are HiROM, so file = cpu & 0x3FFFFF ($C0:0000
-- -> $000000, $F0:0000 -> $300000).  Errors clearly if the symbol is absent,
-- which means the ROM was not (re)built, the name is wrong, or the script was
-- run raw instead of through run.sh (which composes OT6_SYMS in).  This is the
-- always-correct-by-derivation replacement for hand-maintained address
-- literals that went stale on every bank-$F0/$C2/$C0 shift.
function M.sym(name)
  if type(OT6_SYMS) == "table" and OT6_SYMS[name] then
    return OT6_SYMS[name]
  end
  error("symbol " .. tostring(name) .. " not in ff6-en.dbg -- rebuild the ROM "
    .. "(compose.py derives OT6_SYMS from ff6/rom/ff6-en.dbg; run via run.sh)", 2)
end

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
-- Mesen 2 requires emu.createSavestate()/emu.loadSavestate() to run inside
-- an EXEC memory callback for the main CPU ("This function must be called
-- inside an exec memory operation callback"), not an event callback.  So
-- requests go through a one-shot trampoline: register an exec callback over
-- the full address space, do the work on its first fire (the very next
-- instruction the CPU executes), and unregister from within the callback.
-- Results are harvested a frame or two later by the calling step.
--
-- Persistence: sandboxed Lua cannot write files, so blobs round-trip through
-- stdout: [b64:<name>] lines that run.sh decodes into
--   build/states/<name>          (raw Mesen savestate, loadable in the GUI)
--   build/states/<name>.lua      (sidecar: `return "<base64>"`)
-- and lib/compose.py embeds referenced sidecars back in as OT6_STATES.

function M.requestSaveState()
  local req = {}
  local ref
  ref = emu.addMemoryCallback(function()
    if req.fired then return end
    req.fired = true
    local ok, err = pcall(function() req.blob = emu.createSavestate() end)
    req.ok = ok and type(req.blob) == "string" and #req.blob > 0
    req.error = err
    req.done = true
    emu.removeMemoryCallback(ref, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  return req
end

function M.requestLoadState(blob)
  local req = {}
  local ref
  ref = emu.addMemoryCallback(function()
    if req.fired then return end
    req.fired = true
    local ok, err = pcall(function() emu.loadSavestate(blob) end)
    req.ok = ok
    req.error = err
    req.done = true
    emu.removeMemoryCallback(ref, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  return req
end

local function checkReq(req, what)
  assert(req and req.done, what .. " did not complete (trampoline never fired)")
  assert(req.ok, what .. " failed: " .. tostring(req.error))
end
M.checkReq = checkReq

-- Resolve a savestate sidecar to its base64 payload.  compose.py embedded it
-- as OT6_STATES[basename]; that is the only path.  There is no loadfile()
-- fallback because loadfile RAISES under the default sandbox setting
-- (Debug.ScriptWindow.AllowIoOsAccess=false), so a fallback could never fire
-- -- it would only replace a clear error with a confusing one.
function M.resolveStateB64(sidecarPath)
  local base = sidecarPath:match("[^/]+$")
  if type(OT6_STATES) == "table" and OT6_STATES[base] then
    return OT6_STATES[base]
  end
  error("savestate sidecar not embedded: " .. sidecarPath ..
    " (compose.py inlines these; run through run.sh, not raw)")
end

-- STEP: capture the current state and emit it as build/states/<name>.
function M.saveState(name)
  local req
  return seqStep({
    M.call(function() req = M.requestSaveState() end),
    M.waitFrames(2),
    M.call(function()
      checkReq(req, "savestate capture")
      M.emitBlob(name, req.blob)
    end),
  })
end

-- STEP: load a savestate captured earlier (path to the .mss.lua sidecar).
function M.loadState(sidecarPath)
  local req
  return seqStep({
    M.call(function()
      local blob = M.b64decode(M.resolveStateB64(sidecarPath))
      assert(#blob > 0, "empty savestate blob for " .. sidecarPath)
      M.log("loading savestate " .. sidecarPath:match("[^/]+$") ..
        " (" .. #blob .. " bytes)")
      req = M.requestLoadState(blob)
    end),
    M.waitFrames(2),
    M.call(function()
      checkReq(req, "savestate load")
      -- Savestate loads do NOT detach callbacks (nothing in Mesen's load
      -- path clears them; battle_banner registers exec callbacks before its
      -- load and records straight through).  This call is a no-op once
      -- inputCbRef is set; kept only so the input hook is guaranteed live
      -- on paths that load before ever arming it.
      M.rearmInputInjection()
      -- determinism: savestates do NOT restore battery sram, so the
      -- weakness codex persists across runs. invalidate it so every
      -- test starts from a virgin codex (battle_codex re-teaches).
      emu.write(0x316000, 0, emu.memType.snesMemory)
      emu.write(0x316001, 0, emu.memType.snesMemory)
    end),
  })
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
-- party battle HP ($FFFF outside battle).
M.MONSTER_IDS = 0x3F46
M.BATTLE_HP = 0x3BF4

-- OT6 HUD tilemap shadow: 6 lines x stride 14 (+0 cur addr, +2 prev addr,
-- +4 five tilemap words).  MUST track OT6_SHADOW in ff6/src/battle/ot6.asm.
-- It lived at $5762 until 2026-07-18, when that turned out to be inside
-- vanilla's `ram_res w7e5755, 128` -- three suite tests had the old address
-- copy-pasted in and silently started reading vanilla's buffer when it
-- moved.  Read it from here, never inline, so the next move is one edit.
M.SHADOW = 0xECF1
M.SHADOW_STRIDE = 14
function M.shadowLine(line) return M.SHADOW + line * M.SHADOW_STRIDE end

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
-- compresses to ~750 bytes, the battle-transition mosaic to ~2.3 KB, and a
-- real battle scene (bg + sprites + UI windows) to ~10 KB.  4000 splits the
-- transition from the real thing.
function M.screenLooksAlive()
  local ok, png = pcall(emu.takeScreenshot)
  return ok and type(png) == "string" and #png > 4000
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

seqStep = function(steps)
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
-- ------------------------------------------------------------ ot6 canary --
-- Every OT6 font cell in VRAM must match its ROM source data, byte for
-- byte.  Catches battle/effect art clobbering our claimed font cells (the
-- fight-2 bug class) without hardcoding sums: the expected bytes come from
-- the ROM itself, so glyph art edits never stale the canary.
function M.glyphCanary()
  local vr, rom = emu.memType.snesVideoRam, emu.memType.snesPrgRom
  local function findSig(sig)
    -- scan the whole OT6 slice of bank F0: v0.2 grew the code ahead of the
    -- bg glyph table (Ot6BgGlyphData sits at ~$F0109A now), so the window
    -- has to reach past the first 4K it used to fit inside.
    for base = 0x300000, 0x303FF0 do
      local hit = true
      for i = 1, 16 do
        if emu.read(base+i-1, rom) ~= sig[i] then hit = false; break end
      end
      if hit then return base end
    end
    return nil
  end
  -- first 16 bytes of Ot6FontIcons (fire) and Ot6BgGlyphData (shield-1)
  local icons = findSig({0x10,0x10,0x30,0x38,0x38,0x3c,0x6c,0x7c,
                         0x6e,0x7e,0xee,0xfe,0x7e,0x7c,0x3c,0x00})
  local bg    = findSig({0x7e,0x00,0x91,0x7e,0xb1,0x7e,0x91,0x7e,
                         0x52,0x3c,0x3c,0x38,0x18,0x00,0x00,0x00})
  M.assertEq(icons ~= nil, true, "Ot6FontIcons found in rom bank F0")
  M.assertEq(bg ~= nil, true, "Ot6BgGlyphData found in rom bank F0")
  local function checkTile(cell, romBase, tag)
    local v = 0xB000 + cell*16          -- 2bpp font cell in vram
    for i = 0, 15 do
      local got, want = emu.read(v+i, vr), emu.read(romBase+i, rom)
      M.assertEq(got, want, string.format("%s: cell %02X byte %d", tag, cell, i))
    end
  end
  local iconCells = {0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}
  for k, cell in ipairs(iconCells) do
    checkTile(cell, icons + (k-1)*16, "element icon")
  end
  for k = 1, 16 do
    local cell = emu.read(bg - 17 + k, rom)  -- Ot6BgGlyphCellTbl precedes the data
    checkTile(cell, bg + (k-1)*16, "hud glyph")
  end
end

-- true if any OT6 shield/broken glyph word sits in the bg3 field-area map
-- (the under-monster hud). formation-agnostic presence check.
function M.fieldHudPresent()
  local vr = emu.memType.snesVideoRam
  local reg = M.readByte(0x897b)
  local base = ((reg - (reg % 4)) * 256) * 2
  local set = {[0x65]=1,[0x66]=1,[0x67]=1,[0x69]=1,[0x6a]=1,[0x6b]=1,[0x71]=1}
  for off = 0, 0x7FE, 2 do
    if emu.read(base+off+1, vr) == 0x21 and set[emu.read(base+off, vr)] then
      return true
    end
  end
  return false
end

-- party-window bp pip glyph word for menu row 0 (first party member)
function M.pipWord()
  local reg = M.readByte(0x897f)
  local base = ((reg - (reg % 4)) * 256) * 2
  return emu.readWord(base + 0x68, emu.memType.snesVideoRam)
end

function M.isPipGlyph(w)
  local set = {[0x72]=1,[0x73]=1,[0x75]=1,[0x76]=1,[0x77]=1,[0x79]=1}
  return (w >> 8) == 0x21 and set[w & 0xFF] ~= nil
end

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
-- Completion RELEASES the pad: pred can fire mid-body-cycle, abandoning the
-- body wherever it stands, and a button it was holding at that instant must
-- not stay stuck into the steps that follow.  (A stuck d-pad auto-repeats
-- the battle-menu cursor and a stuck A confirms into target selection --
-- both bit battle_boost/battle_preview when input injection moved to
-- hardware-faithful next-poll timing.  navTo/advanceStory/clearBattle
-- already release in their preds; this is the same contract for every
-- drive.)
function M.driveUntil(pred, maxFrames, steps, what)
  what = what or "condition"
  local body = seqStep(steps)
  local waited = 0
  return {
    tick = function()
      if pred() then
        M.setPad({})
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

-- STEP: the canonical first-battle entry from a doorstep fixture.  The
-- battle_doorstep savestate parks the party one step short of its
-- encounter trigger, and entering the fight is always the same dance:
-- hold up long enough to commit the step (20 frames), release and let
-- the engine settle (2), tap A (pressButtons' 4 on / 2 off -- clears any
-- incidental dialog), and cycle until the battle module starts loading;
-- then wait for the battle to be fully up and RENDERING.  battleActive()
-- takes a screenshot per poll (screenLooksAlive), so the wait polls
-- every 30 frames, not every frame.
--
-- Deliberately option-free: dozens of tests enter their first fight
-- through this exact sequence, and the constants are part of each
-- test's frame/RNG landing -- a different hold or wait changes which
-- frame the encounter fires on.  This helper exists so that majority is
-- ONE definition instead of a fleet-wide copy-paste (31 verbatim copies
-- when it was extracted, several already drifted); a test that needs a
-- different entry (another direction, other timeouts, kill-bit
-- handling, a story scene that walks into its own fight) keeps writing
-- its own drive.
function M.enterEncounter()
  return seqStep({
    M.driveUntil(function() return M.battleLoadStarted() end, 4000, {
      M.hold({ "up" }), M.waitFrames(20), M.release(), M.waitFrames(2),
      M.pressButtons({ "a" }, 4),
    }, "battle load"),
    M.waitUntil(function() return M.battleActive() end, 900, "battle active", 30),
  })
end

-- The runner.  steps: list of step objects.  opts.maxFrames: global budget.
local runnerStarted = false
-- ------------------------------------------------------------- field --
-- Field navigation, so routes are coordinate-aware instead of blind
-- timed holds (which desync on any map).  Addresses from the vendored
-- disassembly: party tile x/y $1fc0/$1fc1 (src/field/player.asm
-- InitPlayerPos), map index $1f64 (battle.asm), player-control gate
-- $1eb9 bit7 + map-load $84 + menu-opening $59 (player.asm
-- UpdatePlayerMovement).  Movement is grid-oriented, one tile per step:
-- up=-Y down=+Y left=-X right=+X, PLUS the four diagonals a left/right
-- press produces on a diagonal-movement tile (every Figaro staircase).
-- Passability is computed from RAM by porting both of the engine's
-- movement branches (see "true passability model" below), so routes are
-- found by BFS, not discovered by playing.

-- The active party's object record: $0803 holds the BYTE OFFSET of the
-- party leader's object block (`ldy $0803; lda $086a,y` -- player.asm,
-- reset.asm, everywhere).  Character 0 (TERRA) owns object offset 0, and
-- TERRA led every fixture up to the Moogle defense, so absolute reads of
-- $086A/$087C were silently correct for months -- until the defense made
-- LOCKE (object offset $29) the leader and the lib kept watching TERRA's
-- knocked-out body: position froze at her (14,12) while party 1 stood at
-- (14,14), and hasControl never went true (measured, gen_moogle run 2).
-- Every party-relative read MUST go through this offset.
local function pobj() return M.readWord(0x0803) end

-- LIVE tile position = party-object pixel coords >> 4 ($086a x / $086d y,
-- 16-bit, offset by $0803).  The $1fc0/$1fc1 bytes are a lazily-updated
-- cache and go stale mid-walk, so never navigate on them.
function M.fieldX() return M.readWord(0x086a + pobj()) >> 4 end
function M.fieldY() return M.readWord(0x086d + pobj()) >> 4 end
function M.mapId() return M.readWord(0x1f64) end

-- At rest exactly on a tile: every sub-tile position bit is zero (sub-pixel
-- bytes $0869/$086c plus the low 4 pixel bits of each 16-bit coord).
-- Position samples for navigation are only valid when this holds -- the
-- tile coord (pixel>>4) flips EARLY (~1px in) when moving up/left but only
-- at completion moving down/right, so mid-step reads are direction-skewed.
function M.tileAligned()
  local po = pobj()
  return (M.readByte(0x0869 + po) | (M.readByte(0x086a + po) & 0x0F)
        | M.readByte(0x086c + po) | (M.readByte(0x086d + po) & 0x0F)) == 0
end

-- A REAL event script is executing iff the 24-bit event PC {$e5,$e6,$e7}
-- points into the event-script segment (banks $CA-$CC) and is off its idle
-- parking value $ca/0000.  The bank test matters: ambient NPC object
-- scripts (a stove flame, a wandering townsperson) run through the same
-- interpreter out of their RAM queue -- the PC reads $80xxxx (WRAM mirror)
-- for one frame at a time, every few frames, forever on such maps.  Those
-- excursions are not "an event is running", and counting them broke every
-- consecutive-calm-frames predicate (measured in Arvis's house: $800000
-- one frame in four).
function M.eventRunning()
  local bank = M.readByte(0x00e7)
  if bank < 0xCA or bank > 0xCC then return false end
  return not (bank == 0xCA and M.readByte(0x00e5) == 0
          and M.readByte(0x00e6) == 0)
end

-- A dialog window is open and waiting for a keypress ($ba dialog state,
-- $d3 waiting-for-key).  Advancing is EDGE-triggered: one held A yields
-- exactly one edge; multiple pages need press-RELEASE-press (4 on / 4 off).
function M.dialogWaiting()
  return M.readByte(0x00ba) == 1 and M.readByte(0x00d3) == 1
end

-- true only when the party can actually be walked this frame.  Beyond the
-- control-gate flags this checks the party movement type ($087c,y low
-- nibble via the $0803 offset: 2 = user-controlled, 4 = event-controlled
-- -- events can walk the party with every other flag looking innocent)
-- and the event PC.  Deliberately cheap: RAM reads only, no screenshots
-- (battleLoadStarted is the battle gate; battleActive()'s screen check
-- has no business in a per-frame poll).
function M.hasControl()
  return (M.readByte(0x1eb9) & 0x80) == 0
     and M.readByte(0x0084) == 0
     and M.readByte(0x0059) == 0
     and (M.readByte(0x087c + pobj()) & 0x0F) == 2
     and not M.eventRunning()
     and not M.battleLoadStarted()
end

-- Six formation species words for the current battle ($57c0+2i); the
-- goal-formation guards below match on these.
M.FORMATION = 0x57C0
function M.formationWords()
  local w = {}
  for i = 0, 5 do w[i + 1] = M.readWord(M.FORMATION + i * 2) end
  return w
end
function M.formationHas(set)          -- set: { [speciesWord] = true, ... }
  for i = 0, 5 do
    if set[M.readWord(M.FORMATION + i * 2)] then return true end
  end
  return false
end

-- Kill everything in the current battle via each monster's own status
-- byte (present bit $3aa8 bit0 -> set dead $3eec bit7) and tap A through
-- the victory/exp text.  Returns a step that resolves when the battle is
-- fully torn down.  The A taps are EDGE-pressed (4 on / 4 off): dialog and
-- victory-text advancing is edge-triggered, so a continuous hold yields
-- exactly one page ever.  `spare` (optional list of formation species
-- words) is the goal-formation guard: if the battle we're asked to clear
-- IS the goal fight, that's a script bug -- fail loudly instead of
-- silently instakilling the thing the route exists to reach.
function M.clearBattle(maxFrames, spare)
  local spareSet = {}
  for _, w in ipairs(spare or {}) do spareSet[w] = true end
  local aPhase = 0
  return M.driveUntil(function()
    return not M.battleLoadStarted()   -- implies battleActive() false too
  end, maxFrames or 9000, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if M.battleLoadStarted() and M.monstersPresent() > 0 then
        if next(spareSet) and M.formationHas(spareSet) then
          error("clearBattle: refusing to kill a spared formation " ..
            string.format("(%04X %04X %04X %04X %04X %04X)",
              table.unpack(M.formationWords())), 0)
        end
        for slot = 0, 5 do
          if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
            M.writeByte(0x3eec + slot * 2, M.readByte(0x3eec + slot * 2) | 0x80)
          end
        end
      end
      M.setPad(aPhase < 4 and { "a" } or {})
    end),
  }, "clear battle")
end

-- ----------------------------------------------- true passability model --
-- Port of the engine's own step check.  UpdatePlayerMovement
-- (src/field/player.asm:325) reads the d-pad and takes ONE of two branches;
-- both are modelled here, because Figaro Castle is built out of the second.
--
-- Tile id at (x,y) = the BG1 tilemap byte $7f0000[y*256+x]; its properties
-- are p1 = $7e7600[id] (the prop byte the engine keeps for the party's own
-- tile in $b8) and p2 = $7e7700[id] (directional exits, in $b9).
--
-- CARDINAL branch (@4978, player.asm:456-507 -> CheckPlayerMove @4e16,
-- player.asm:1072).  A step from cur=(x,y) toward dir is allowed iff ALL of:
--   1. p2(cur) has the direction's exit bit (up=$08 right=$01 down=$04
--      left=$02 -- player.asm DirectionBitTbl:1210);
--   2. p1(dst)&7 ~= 7 (counter/wall tile);
--   3. the bridge/z-level rules pass (below, transcribed branch for
--      branch; party z-level = $b2 low bits, bit0 upper / bit1 lower);
--   4. no object occupies dst: $7e2000[dstY*256+dstX] bit7 SET means free
--      (the engine allows crossing UNDER an occupied bridge tile; we skip
--      that special case -- conservative, and movement-verify covers it).
--
-- DIAGONAL branch (@48d4, player.asm:379-453).  UpdatePlayerMovement tests
-- the party's OWN tile first (player.asm:368-377): if p1(cur) & $c0 is set
-- -- and it is not a bridge tile the party is standing on the lower z-level
-- of -- a LEFT or RIGHT press moves the party DIAGONALLY instead, one tile
-- in each axis.  Which diagonal is a property of the tile, not the press:
--   p1 bit7 ($80), "\" tiles:  right -> down-right (dir $06, :403)
--                              left  -> up-left    (dir $08, :420)
--   p1 bit6 ($40), "/" tiles:  right -> up-right   (dir $05, :394)
--                              left  -> down-left  (dir $07, :429)
-- bit7 wins when both are set (:385 `bmi`, :410 `bpl`).  The destination
-- tests are the whole of it: p1(dst) must carry the SAME diagonal bit and
-- must not be exactly $f7 (:389-393, :399-402, :416-419, :424-428).  The
-- branch consults NOTHING else -- not p2's exit bits, not the counter rule,
-- not the z-level rules, not the object map (it never touches $7e2000 and
-- never calls GetObjMapAdjacent), and it never calls CheckDoor.  The
-- movement direction it stores in $087e is 5..8, and _c04f8d (player.asm
-- :1286) maps those to exactly the four diagonal neighbours; CalcObjMoveDir
-- (obj.asm:5521) then drives both axes at the cardinal rate, so a diagonal
-- step is one tile in x AND one in y (ObjMoveRateH/V rows for dir 5..8).
-- UP and DOWN presses are not handled by this branch at all (:380/:405 test
-- only $07 bit0/bit1) and fall through to the cardinal path, as does a
-- left/right press whose diagonal destination fails (:396, :400, :417, :426
-- all jump into @4978).  So on a diagonal tile the diagonal is TRIED FIRST
-- and the cardinal move of the same press only happens when it is refused:
-- that is why stepAllowed says "no" to a cardinal left/right that the
-- engine would turn into a diagonal.
--
-- The four cardinal names double as press names; the four diagonal names
-- are moves the model plans and verifies but never presses directly.
-- DIRS/DIRIDX stay CARDINAL: they are the world map's move set too, and the
-- overworld module (ff6/src/world/) has no diagonal branch at all -- its
-- GetPlayerInput tests one passability bit per cardinal direction
-- (move.asm @1ead..@1ff3).  Only the field walks diagonals.
local DIRS   = { "up", "right", "down", "left" }
local DIRIDX = { up = 0, right = 1, down = 2, left = 3 }
local DIRBIT = { up = 0x08, right = 0x01, down = 0x04, left = 0x02 }
local DELTA  = { up = { 0, -1 }, right = { 1, 0 },
                 down = { 0, 1 }, left = { -1, 0 },
                 upright = { 1, -1 }, downright = { 1, 1 },
                 downleft = { -1, 1 }, upleft = { -1, -1 } }
-- the FIELD's move set: the four presses plus the four diagonals they can
-- turn into.  PRESS is the button a move is executed with.
local MOVES  = { "up", "right", "down", "left",
                 "upright", "downright", "downleft", "upleft" }
local MOVEIDX = { up = 0, right = 1, down = 2, left = 3,
                  upright = 4, downright = 5, downleft = 6, upleft = 7 }
local PRESS  = { up = "up", right = "right", down = "down", left = "left",
                 upright = "right", downright = "right",
                 downleft = "left", upleft = "left" }

-- BG1 tilemap byte for a tile.  The tilemap's row stride is 256 ($7f0000 +
-- row*256 + col: UpdateLocalTiles builds its row pointers as {lo=0,hi=row},
-- player.asm:1385-1399), but the COORDINATES wrap at the map's own size
-- masks $86/$87, not at 256 (`and $86` / `and $87`, player.asm:1387-1412).
-- Those come from InitScrollClip via ScrollClipTbl = $0f/$1f/$3f/$7f
-- (scroll.asm:298-320, table at :244), so they are never zero and no
-- guard is needed; Figaro's exterior map 55 is $3f/$3f, its interiors
-- $7f/$3f (map_prop.dat record 33*map + 23).
function M.maptile(x, y)
  local xm, ym = M.readByte(0x0086), M.readByte(0x0087)
  return M.readByte(0x7F0000 + (y & ym) * 256 + (x & xm))
end

-- The diagonal move a `press` produces standing on the tile whose prop byte
-- is `c` at party z-level `z`, or nil if this press moves cardinally here.
-- Transcribed from player.asm:368-429 (see the branch table above).
local function diagStep(x, y, c, press, z)
  if press ~= "left" and press ~= "right" then return nil end  -- :380/:405
  if (c & 0xC0) == 0 then return nil end                       -- :374-376
  if (c & 0x04) ~= 0 and z == 0x02 then return nil end         -- :368-373
  local bit = (c & 0x80) ~= 0 and 0x80 or 0x40                 -- :385/:410
  local mv
  if bit == 0x80 then mv = press == "right" and "downright" or "upleft"
  else                mv = press == "right" and "upright"   or "downleft" end
  local d = DELTA[mv]
  local t = M.readByte(0x7E7600 + M.maptile(x + d[1], y + d[2]))
  if t == 0xF7 or (t & bit) == 0 then return nil end           -- :389-:428
  return mv
end

-- the step check, parameterized on the party z-level so the pathfinder can
-- track z along a hypothetical path instead of assuming it constant
local function stepAllowed(x, y, move, z)
  local c = M.readByte(0x7E7600 + M.maptile(x, y))     -- p1(cur)
  local press = PRESS[move]
  local diag = diagStep(x, y, c, press, z)
  if move ~= press then return move == diag end  -- asked about a diagonal
  if diag then return false end     -- this press moves diagonally, not here
  local d = DELTA[move]
  local nx, ny = x + d[1], y + d[2]
  local e = M.readByte(0x7E7700 + M.maptile(x, y))     -- p2(cur), exit bits
  local t = M.readByte(0x7E7600 + M.maptile(nx, ny))   -- p1(dst)
  if (e & 0x0F & DIRBIT[move]) == 0 then return false end -- no exit that way
  if (t & 0x07) == 0x07 then return false end            -- counter/wall
  if (c & 0x04) ~= 0 then                 -- cur is a bridge tile:
    if (z & 0x01) ~= 0 then               --   party upper: dst must not be
      if (t & 0x02) ~= 0 then return false end          -- lower-only
    else                                  --   party lower: dst must not be
      if (t & 0x01) ~= 0 then return false end          -- upper-only
    end
  elseif (t & 0x03) == 0x03 then          -- dst walkable on both z-levels
    -- always allowed
  elseif (c & 0x03) == 0x03 then          -- cur on both: any dst EXCEPT a
    if (t & 0x04) ~= 0 then return false end            -- bridge tile
  elseif (((c & 0x03) ~ 0x03) & (t & 0x03)) ~= 0 then
    return false                          -- z-levels incompatible
  end
  if (M.readByte(0x7E2000 + (ny & 0xFF) * 256 + (nx & 0xFF)) & 0x80) == 0 then
    return false                          -- an NPC/object stands there
  end
  return true
end

-- can the party make `move` from tile (x,y) RIGHT NOW (live z-level)?
-- `move` is any of MOVES: the four presses, or one of the four diagonals
-- (true only where the engine would turn that press into that diagonal).
function M.canStep(x, y, move)
  return stepAllowed(x, y, move, M.readByte(0x00b2) & 0x03)
end

-- the button that executes `move` (diagonals are pressed left/right)
function M.movePress(move) return PRESS[move] end

-- party z-level after stepping OFF (x,y): kept on a bridge/both tile,
-- otherwise taken from the tile being left (player.asm @4eef, :1196-1201).
-- The diagonal branch spells the same rule out longhand -- keep z if the
-- tile is a bridge ($04) or is both-z-levels ($03), else take $b8&3
-- (player.asm:432-439) -- so one function serves both branches.
local function zAfter(x, y, z)
  local c = M.readByte(0x7E7600 + M.maptile(x, y))
  if (c & 0x07) >= 0x03 then return z end
  return c & 0x03
end

local function edgeKey(x, y, move)
  return ((y & 0xFF) * 256 + (x & 0xFF)) * 8 + MOVEIDX[move]
end

-- BFS a path from the party's CURRENT tile to (tx,ty) over stepAllowed
-- edges, tracking the z-level a walker would carry along each candidate
-- path (nodes are (x,y,z) triples).  `blockedEdges` (optional, keys from
-- edgeKey) prunes edges the executor has PROVEN wrong empirically.
-- Returns a list of MOVES names (four cardinals plus the four diagonals a
-- press turns into on a diagonal tile), or nil (unreachable / >4096 nodes).
function M.bfsPath(tx, ty, blockedEdges)
  blockedEdges = blockedEdges or {}
  local sx, sy = M.fieldX(), M.fieldY()
  local sz = M.readByte(0x00b2) & 0x03
  local function nkey(x, y, z) return (z << 16) | ((y & 0xFF) << 8) | (x & 0xFF) end
  local seen = { [nkey(sx, sy, sz)] = true }
  local q, qi = { { sx, sy, sz } }, 1
  local parent = {}                       -- nkey -> { parentNkey, dir }
  while qi <= #q do
    local x, y, z = q[qi][1], q[qi][2], q[qi][3]
    qi = qi + 1
    if x == tx and y == ty then           -- collect dirs back to the start
      local dirs, k = {}, nkey(x, y, z)
      while parent[k] do
        table.insert(dirs, 1, parent[k][2])
        k = parent[k][1]
      end
      return dirs
    end
    if qi > 4096 then return nil end      -- sane radius: give up, not hang
    local zn = zAfter(x, y, z)
    for _, dir in ipairs(MOVES) do
      if not blockedEdges[edgeKey(x, y, dir)] and stepAllowed(x, y, dir, z) then
        local d = DELTA[dir]
        local k = nkey(x + d[1], y + d[2], zn)
        if not seen[k] then
          seen[k] = true
          parent[k] = { nkey(x, y, z), dir }
          q[#q + 1] = { x + d[1], y + d[2], zn }
        end
      end
    end
  end
  return nil
end

-- ------------------------------------------------------- BFS navigation --
NAV = {}
function M.navReset()
  NAV = { blocked = {}, nblocked = 0, plan = 0, idx = 0, hb = 0 }
end
M.navReset()
function M.navDump()   -- debugging one-liner (kept from the old navigator)
  return string.format("bfs plan=%d idx=%d blocked=%d",
    NAV.plan or 0, NAV.idx or 0, NAV.nblocked or 0)
end

-- targets may be numbers or thunks (resolved each tick, so a route can
-- aim at a coord it only knows at runtime)
local function resolve(v) return type(v) == "function" and v() or v end

-- Walk to tile (tx,ty) on the current map: BFS a plan over the true
-- passability model, then execute it ONE VERIFIED STEP at a time.  Each
-- iteration (only when user-controlled and tile-aligned): hold the step's
-- direction until the tile coord changes, release (a begun 16px step
-- always completes), wait for tile-alignment, and check the landing
-- against the plan.  A press that never moves us proves the model wrong
-- for that edge: blocklist it (persists across re-plans within this
-- navTo) and re-BFS.  Any deviation from the plan (event force-moves,
-- post-battle drift) also re-plans -- BFS is cheap, guessing isn't.
-- Encounters that fire mid-walk are cleared inline with the kill-bit
-- idiom UNLESS the formation matches opts.spare (the goal fight: hands
-- off, let opts.arrive see it).  Dialogs are advanced with EDGE-pressed
-- A; other control losses (events walking the party) get a neutral pad.
--   opts.arrive    extra terminator predicate (checked before everything)
--   opts.maxFrames frame budget -> error (default 20000)
--   opts.spare     list of formation species words never to kill-bit
--   opts.noPathRetries  BFS-no-path retries, 45 idle frames apart, before
--                  erroring (default 20).  A no-path is often TRANSIENT:
--                  an NPC standing in a one-tile corridor blocks the
--                  object map exactly while its scene runs (the Figaro
--                  gate guard, measured), and erroring instantly turned
--                  every such scene into a route failure.
function M.navTo(txIn, tyIn, opts)
  opts = opts or {}
  local maxFrames = opts.maxFrames or 20000
  local arrive = opts.arrive
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  M.navReset()
  local plan, idx = nil, 1
  local pend = nil          -- the in-flight/unverified step
  local aPhase = 0          -- edge-press phasing for A (4 on / 4 off)
  local battN, dlgN, lostN = 0, 0, 0   -- debounce counters (see below)
  local noPathN, pause = 0, 0          -- no-path retry state
  local function drop(why)  -- discard the plan, saying why (once, not per frame)
    if plan or pend then
      M.log(string.format("nav: %s at (%d,%d); plan dropped", why,
        M.fieldX(), M.fieldY()))
    end
    plan, pend = nil, nil
    NAV.plan, NAV.idx = 0, 0
  end
  return M.driveUntil(function()
    local done
    if arrive and arrive() then
      done = true
    else
      done = M.fieldX() == resolve(txIn) and M.fieldY() == resolve(tyIn)
         and M.hasControl() and M.tileAligned()
    end
    if done then M.setPad({}) end
    return done
  end, maxFrames, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if M.frame - NAV.hb >= 600 then
        NAV.hb = M.frame
        M.log(string.format("nav f%d (%d,%d) %s", M.frame, M.fieldX(),
          M.fieldY(), M.navDump()))
      end
      -- classify the frame, DEBOUNCED: the battle/dialog signals live in
      -- RAM the field module also scribbles on, so require 3 consecutive
      -- frames before acting -- a real battle/dialog persists for hundreds.
      -- Acting on a 1-frame ghost would tap A on the open field.
      battN = M.battleLoadStarted() and battN + 1 or 0
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      lostN = M.hasControl() and 0 or lostN + 1
      -- 1. battle: clear it, but NEVER the goal formation
      if battN >= 3 then
        drop("battle")
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad({})                 -- goal fight: hands off, arrive() sees it
          return
        end
        if M.monstersPresent() > 0 then
          for slot = 0, 5 do
            if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              M.writeByte(0x3eec + slot * 2, M.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      -- 2. dialog waiting for a keypress: edge-tap A through it
      if dlgN >= 3 then
        drop("dialog")
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      -- 3. any other control loss (event walking the party, fades, or a
      --    yet-undebounced battle/dialog): neutral pad and wait -- jamming
      --    directions or A only corrupts state
      if lostN > 0 or battN > 0 or dlgN > 0 then
        if lostN >= 3 then drop("control lost") end
        M.setPad({})
        return
      end
      -- 4. a step is in flight: hold until the tile coord changes
      if pend and pend.holding then
        if M.fieldX() ~= pend.x or M.fieldY() ~= pend.y then
          pend.holding = false         -- it'll glide to rest on its own
          M.setPad({})
          return
        end
        pend.held = pend.held + 1
        if pend.held > 30 then         -- never moved: the model was wrong
          NAV.blocked[edgeKey(pend.x, pend.y, pend.dir)] = true
          NAV.nblocked = NAV.nblocked + 1
          M.log(string.format("nav: edge (%d,%d)->%s blocked in reality; re-plan",
            pend.x, pend.y, pend.dir))
          plan, pend = nil, nil
          M.setPad({})
          return
        end
        M.setPad({ [PRESS[pend.dir]] = true })
        return
      end
      -- 5. between steps: position samples are only valid at rest on a tile
      if not M.tileAligned() then M.setPad({}); return end
      if pause > 0 then pause = pause - 1; M.setPad({}); return end
      local x, y = M.fieldX(), M.fieldY()
      -- 6. verify the landing of the last step against the plan
      if pend then
        if x == pend.tx and y == pend.ty then
          pend = nil                   -- clean step, plan still on track
        else
          -- Landed off-plan.  A slide FURTHER along the same move (the
          -- engine can carry more than one tile) leaves the edge itself
          -- proven good; anything else condemns it.  Tested as "the
          -- displacement is a positive whole multiple of the move's
          -- delta", which holds for the diagonals too -- the old
          -- along/perp pair assumed a cardinal unit vector and would have
          -- condemned every correct diagonal step (delta (1,-1) scores
          -- along 2, perp -2).
          local d = DELTA[pend.dir]
          local dx, dy = x - pend.x, y - pend.y
          local k = math.max(math.abs(dx), math.abs(dy))
          if not (k > 0 and dx == d[1] * k and dy == d[2] * k) then
            NAV.blocked[edgeKey(pend.x, pend.y, pend.dir)] = true
            NAV.nblocked = NAV.nblocked + 1
          end                          -- (same-direction slide: edge was fine)
          M.log(string.format("nav: step (%d,%d)->%s landed (%d,%d); re-plan",
            pend.x, pend.y, pend.dir, x, y))
          plan, pend = nil, nil
        end
      end
      -- 7. (re)plan when we have no plan or it ran out
      if plan and idx > #plan then plan = nil end
      if not plan then
        plan = M.bfsPath(resolve(txIn), resolve(tyIn), NAV.blocked)
        idx = 1
        if not plan then
          -- transient blockage patience: idle 45 frames and re-search.
          -- the blocklist is forgiven first (a condemned edge may be the
          -- only corridor once the blocker moves off it).
          noPathN = noPathN + 1
          if noPathN > (opts.noPathRetries or 20) then
            error(string.format(
              "navTo: no path (%d,%d)->(%d,%d) [%d edges blocklisted, %d retries]",
              x, y, resolve(txIn), resolve(tyIn), NAV.nblocked, noPathN - 1), 0)
          end
          if NAV.nblocked > 0 then NAV.blocked, NAV.nblocked = {}, 0 end
          M.log(string.format("nav: no path (%d,%d)->(%d,%d); waiting (retry %d)",
            x, y, resolve(txIn), resolve(tyIn), noPathN))
          pause = 45
          M.setPad({})
          return
        end
        noPathN = 0
        NAV.plan, NAV.idx = #plan, idx
        M.log(string.format("nav: planned %d steps from (%d,%d)", #plan, x, y))
        if #plan == 0 then M.setPad({}); return end  -- pred will notice
      end
      -- 8. launch the next step
      local dir = plan[idx]
      idx = idx + 1
      NAV.idx = idx
      local d = DELTA[dir]
      pend = { x = x, y = y, dir = dir, tx = x + d[1], ty = y + d[2],
               held = 0, holding = true }
      M.setPad({ [PRESS[dir]] = true })   -- a diagonal is pressed left/right
    end),
  }, "navTo")
end

-- Ride out a NON-INTERACTIVE story stretch: long automatic events with
-- intermittent dialogs and scripted battles (the esper-scene class).  The
-- hands-off companion to navTo -- no walking, no plan, just keep the story
-- unstuck until pred() is truthy (checked every frame; raises after
-- maxFrames).  Frames are classified with navTo's 3-frame debounce (the
-- battle/dialog signal bytes live in RAM the field module also scribbles
-- on; acting on a one-frame ghost would tap A on the open field):
--   battle  -> kill-bit everything present + edge-tap A through the text.
--              A formation matching opts.spare is a scripted set-piece:
--              never kill-bitted, and hands OFF for its first 300 frames,
--              THEN edge-tapped.  Both halves are load-bearing (measured,
--              esper zap): the set-piece ends via a monster-turn battle
--              event, and A pressed during the load queues player actions
--              that keep the turn engine busy forever -- but once the
--              event owns the stage (its opening battle dialog is up by
--              ~250 frames), it stalls without A to advance that text;
--   dialog  -> edge-tap A;
--   anything else -> neutral pad.  Control lost means an event is walking
--              the party; control held means the story is between beats.
--              Either way blind A is worse than patience: on the open
--              field it talks to NPCs and re-fires triggers.
function M.advanceStory(pred, maxFrames, opts)
  opts = opts or {}
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  local aPhase = 0
  local battN, dlgN = 0, 0
  local hb = -600                      -- heartbeat: log immediately, then every 600
  return M.driveUntil(function()
    local done = pred()
    if done then M.setPad({}) end
    return done
  end, maxFrames or 20000, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if M.frame - hb >= 600 then
        hb = M.frame
        M.log(string.format(
          "story f%d map=%d (%d,%d) ctl=%s algn=%s dlg=%s batt=%s ev=%s",
          M.frame, M.mapId(), M.fieldX(), M.fieldY(),
          tostring(M.hasControl()), tostring(M.tileAligned()),
          tostring(M.dialogWaiting()), tostring(M.battleLoadStarted()),
          tostring(M.eventRunning())))
      end
      battN = M.battleLoadStarted() and battN + 1 or 0
      dlgN  = M.dialogWaiting() and dlgN + 1 or 0
      if battN >= 3 then
        if battN == 3 then             -- rising edge: name the fight once
          local w = M.formationWords()
          M.log(string.format("story: battle up (%04X %04X %04X %04X %04X %04X)",
            w[1], w[2], w[3], w[4], w[5], w[6]))
        end
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad(battN > 300 and aPhase < 4 and { "a" } or {})
          return
        end
        if M.monstersPresent() > 0 then
          for slot = 0, 5 do
            if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              M.writeByte(0x3eec + slot * 2, M.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if dlgN >= 3 then
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      M.setPad({})
    end),
  }, "advanceStory")
end

-- ------------------------------------------------------- world map nav --
-- The overworld is a separate engine (ff6/src/world/) with its own
-- position registers and a 1-bit passability rule; every field predicate
-- above is meaningless there.  The world module keeps DP=$0000
-- (world_start.asm has no phd/pld; its menu path reads $e0 plain), so
-- these are absolute zero-page addresses:
--   $E0/$E2  tile x/y -- the high bytes of the 16-bit position words at
--            $DF/$E1 (word = tile*256 + fraction; move.asm integrates
--            velocity into them at @1e56)
--   $DF/$E1  low bytes = sub-tile fraction; both zero <=> at rest.
--            Moving down/right the tile byte flips at step completion;
--            moving up/left it borrows through on the FIRST frame (both
--            measured, probe_world step traces) -- same direction skew
--            as the field, so position samples gate on worldAligned()
--   $E3/$E5  16-bit velocity; GetPlayerInput zeroes both every aligned
--            frame, then sets +-$10 for a held passable direction
--   $F6     facing 0=up 1=right 2=down 3=left
--   $E7     bit0 = world event script running (Figaro/Narshe triggers)
--   $19     fade/exit trigger (nonzero = leaving the world map)
--   $E8     bit0 = menu opening, bit3 = once-per-tile event/battle
--            latch, bit4 = reload-world (battle return, zone eater)
--
-- MOVEMENT IS LATCHED TO THE STEP: MovePlayer gates its whole body,
-- input read included, on both fractions being zero (move.asm:834-841),
-- so a begun step always glides to the next tile boundary -- a 4-frame
-- tap was measured carrying the party a full tile with velocity held at
-- $10 for all 16 frames (probe_world).  The executor therefore just
-- holds the planned direction whenever it is aligned; releases are
-- never needed mid-step.

-- On the world map iff (word $1F64 & $3FF) < 3: the top-level dispatch
-- masks #$03ff (field/reset.asm:66).  Raw compares are wrong there --
-- entrance/parent records ride flag bits in the high byte (measured
-- $2000 on the world after the Narshe exit; $0200|55 entering Figaro).
function M.worldMode() return (M.readWord(0x1f64) & 0x3FF) < 3 end
-- which world: 0=WoB 1=WoR 2=Serpent Trench (GetWorldTileProp masks the
-- LOW BYTE only, move.asm @21d7)
function M.worldId() return M.readWord(0x1f64) & 0xFF end

function M.worldX() return M.readByte(0x00e0) end
function M.worldY() return M.readByte(0x00e2) end
function M.worldAligned()
  return M.readByte(0x00df) == 0 and M.readByte(0x00e1) == 0
end

-- WorldTileProp = $EE9B14 (world/tile_prop.asm:4) -> rom file $2E9B14;
-- 256 words per world, index = worldId*512 + tiletype*2.  Cached per
-- world id on first use (512 rom reads once, not per BFS node).
local WORLD_PROP_FILE = 0x2E9B14
local worldPropCache, worldPropWorld = nil, nil
function M.worldTileProp(x, y)
  local w = M.worldId()
  if worldPropWorld ~= w then
    worldPropCache, worldPropWorld = {}, w
    for t = 0, 255 do
      worldPropCache[t] = M.readRomWord(WORLD_PROP_FILE + w * 512 + t * 2)
    end
  end
  local t = M.readByte(0x7F0000 + (y & 0xFF) * 256 + (x & 0xFF))
  return worldPropCache[t]
end

-- A step onto (x,y) is legal on foot iff bit4 ($0010) of the DESTINATION
-- tile's property word is clear -- the engine checks nothing else, no
-- exit bits / z-levels / object map (GetPlayerInput tests exactly this
-- per direction, move.asm @1ead..@1ff3; verified live: predictions from
-- this rule matched real movement at the Narshe spawn, probe_world).
-- Other bits, informational: $20 forest (legal, sets the hidden flag),
-- $40 random battles enabled here.
function M.worldPassable(x, y)
  return (M.worldTileProp(x, y) & 0x0010) == 0
end
function M.worldCanStep(x, y, dir)
  local d = DELTA[dir]
  return M.worldPassable(x + d[1], y + d[2])
end

local function worldEdgeKey(x, y, dir)
  return ((y & 0xFF) * 256 + (x & 0xFF)) * 4 + DIRIDX[dir]
end

-- BFS a path from the party's CURRENT world tile to (tx,ty).  The map
-- wraps at 256 in both axes.  `blockedEdges` (keys from worldEdgeKey)
-- prunes edges the executor has proven wrong, same contract as the
-- field bfsPath.  The node cap is 20000, not the field's 4096: world
-- legs run 60+ tiles (Narshe->Figaro BFS'd 63 steps, probe_world3) and
-- the search disc grows with them.
function M.worldBfs(tx, ty, blockedEdges)
  blockedEdges = blockedEdges or {}
  local sx, sy = M.worldX(), M.worldY()
  local function key(x, y) return (y & 0xFF) * 256 + (x & 0xFF) end
  local seen = { [key(sx, sy)] = true }
  local q, qi = { { sx, sy } }, 1
  local parent = {}
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]
    qi = qi + 1
    if x == tx and y == ty then
      local dirs, k = {}, key(x, y)
      while parent[k] do
        table.insert(dirs, 1, parent[k][2])
        k = parent[k][1]
      end
      return dirs
    end
    if qi > 20000 then return nil end
    for _, dir in ipairs(DIRS) do
      if not blockedEdges[worldEdgeKey(x, y, dir)] then
        local d = DELTA[dir]
        local nx, ny = (x + d[1]) & 0xFF, (y + d[2]) & 0xFF
        local k = key(nx, ny)
        if not seen[k] and M.worldPassable(nx, ny) then
          seen[k] = true
          parent[k] = { key(x, y), dir }
          q[#q + 1] = { nx, ny }
        end
      end
    end
  end
  return nil
end

-- true when the world engine will accept a step this frame: on the world
-- map, no world event script ($E7 bit0 -- the Figaro/Narshe gate events
-- run through it), not fading out to a field map ($19), and none of
-- $E8's takeover bits: bit0 menu opening, bit5 battle pending/running
-- (set the INSTANT the encounter roll wins, move.asm's `ora #$20`
-- before BattleZoom -- long before battleLoadStarted's HP-table signal,
-- which is what let a battle transition masquerade as a dead edge in
-- gen_figaro run 1), bit4 reload-world (the post-battle fade/init).
-- battleLoadStarted is still checked for the battle interior itself.
-- ($E9 reads $04 during normal control -- measured -- so it is
-- deliberately not gated on.)
function M.worldHasControl()
  return M.worldMode()
     and M.readByte(0x0019) == 0
     and (M.readByte(0x00e7) & 0x01) == 0
     and (M.readByte(0x00e8) & 0x31) == 0
     and not M.battleLoadStarted()
end

-- Walk to world tile (tx,ty): the field navTo's verified-step loop on
-- the world engine.  Differences, each measured (probe_world/3):
--  * hold-through: input is read only at tile boundaries, so the walker
--    holds the planned direction continuously; a landing is verified
--    when the fractions return to zero, and only then is the next
--    direction chosen (re-plan on any mismatch, blocklist an edge whose
--    press provably never moved us)
--  * battles RELOAD THE WORLD: move.asm:916-921 snapshots the tile into
--    $1F60/$1F61 before Battle_ext and world_start.asm:465-482 reruns
--    ReloadMap after -- measured: kill-bit clear, then ~95 frames of
--    fade/init, position and facing back exactly, danger counter zeroed.
--    The walker clears non-spared battles inline (kill-bit + edge-A) and
--    stalls until the reload finishes (aligned + full brightness) before
--    planning again
--  * no dialog branch: world triggers run world event scripts, not the
--    field dialog engine; $BA/$D3 are stale field RAM here
--   opts.arrive    extra terminator (checked first, every frame)
--   opts.maxFrames frame budget -> error (default 20000)
--   opts.spare     formation species words never to kill-bit
function M.worldNavTo(txIn, tyIn, opts)
  opts = opts or {}
  local maxFrames = opts.maxFrames or 20000
  local arrive = opts.arrive
  local spareSet = {}
  for _, w in ipairs(opts.spare or {}) do spareSet[w] = true end
  local blocked, nblocked = {}, 0
  local plan, idx = nil, 1
  local pend = nil
  local aPhase = 0
  local battN = 0
  local hb = -600
  local function resolveT(v) return type(v) == "function" and v() or v end
  return M.driveUntil(function()
    local done
    if arrive and arrive() then
      done = true
    else
      done = M.worldX() == resolveT(txIn) and M.worldY() == resolveT(tyIn)
         and M.worldHasControl() and M.worldAligned()
    end
    if done then M.setPad({}) end
    return done
  end, maxFrames, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if M.frame - hb >= 600 then
        hb = M.frame
        M.log(string.format("wnav f%d (%d,%d) plan=%s idx=%d blocked=%d",
          M.frame, M.worldX(), M.worldY(),
          plan and tostring(#plan) or "-", idx, nblocked))
      end
      battN = M.battleLoadStarted() and battN + 1 or 0
      -- 1. battle: clear it (never a spared formation), then let the
      --    world reload run out before touching the plan again
      if battN >= 3 then
        plan, pend = nil, nil
        if next(spareSet) and M.formationHas(spareSet) then
          M.setPad({})
          return
        end
        if M.monstersPresent() > 0 then
          for slot = 0, 5 do
            if M.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              M.writeByte(0x3eec + slot * 2, M.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        M.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      -- 2. anything that is not plain walkable control: hands off (the
      --    post-battle reload, world event scripts, fades)
      if battN > 0 or not M.worldHasControl() then M.setPad({}); return end
      -- 3. mid-step: the latch owns it; keep the pad as-is
      if not M.worldAligned() then return end
      -- 4. the reload's own fade ends before brightness is back; a step
      --    launched into the fade works but leaves position samples one
      --    frame stale -- cheap to just wait it out (getState only runs
      --    at rest, not per frame)
      if (emu.getState()["ppu.screenBrightness"] or 0) < 15 then
        M.setPad({})
        return
      end
      local x, y = M.worldX(), M.worldY()
      -- 5. verify the landing of the last step
      if pend then
        if x == pend.tx and y == pend.ty then
          pend = nil
        elseif x == pend.x and y == pend.y then
          -- still on the start tile.  1-2 aligned frames here are normal
          -- launch latency (the pad applies at the next input poll and
          -- velocity lands the frame after); a press that has not moved
          -- us in 10 is provably refused by the engine.
          pend.stall = pend.stall + 1
          if pend.stall > 10 then
            blocked[worldEdgeKey(pend.x, pend.y, pend.dir)] = true
            nblocked = nblocked + 1
            M.log(string.format("wnav: edge (%d,%d)->%s dead; re-plan",
              pend.x, pend.y, pend.dir))
            plan, pend = nil, nil
            M.setPad({})
            return
          end
          M.setPad({ [pend.dir] = true })
          return
        else
          M.log(string.format("wnav: step (%d,%d)->%s landed (%d,%d); re-plan",
            pend.x, pend.y, pend.dir, x, y))
          plan, pend = nil, nil
        end
      end
      -- 6. (re)plan.  If the blocklist made the target unreachable,
      -- forgive it once and re-search clean before giving up: world
      -- corridors run one tile wide (the desert pass measured so), and
      -- a single falsely-condemned edge there would otherwise be fatal
      -- while a genuinely dead edge just gets re-condemned next lap.
      if plan and idx > #plan then plan = nil end
      if not plan then
        plan = M.worldBfs(resolveT(txIn), resolveT(tyIn), blocked)
        if not plan and nblocked > 0 then
          M.log(string.format(
            "wnav: no path with %d blocked edges; amnesty + re-plan", nblocked))
          blocked, nblocked = {}, 0
          plan = M.worldBfs(resolveT(txIn), resolveT(tyIn), blocked)
        end
        idx = 1
        if not plan then
          error(string.format(
            "worldNavTo: no path (%d,%d)->(%d,%d) [%d edges blocklisted]",
            x, y, resolveT(txIn), resolveT(tyIn), nblocked), 0)
        end
        M.log(string.format("wnav: planned %d steps from (%d,%d)", #plan, x, y))
        if #plan == 0 then M.setPad({}); return end
      end
      -- 7. launch the next step and hold it
      local dir = plan[idx]
      idx = idx + 1
      local d = DELTA[dir]
      pend = { x = x, y = y, dir = dir,
               tx = (x + d[1]) & 0xFF, ty = (y + d[2]) & 0xFF, stall = 0 }
      M.setPad({ [dir] = true })
    end),
  }, "worldNavTo")
end

-- Drive a route that crosses engine modes: legs = { {mode="field", x, y,
-- opts}, {mode="world", x, y, opts}, ... }.  Between legs the engine is
-- expected to change modes on its own (an exit tile fires as the
-- previous leg lands, a world trigger loads a field map); each leg first
-- waits for its declared mode plus the matching settle gates -- control,
-- tile alignment, full screen brightness, then a 30-frame margin, the
-- post-map-load discipline every field fixture uses -- and only then
-- dispatches the mode's navigator.
function M.route(legs)
  local steps = {}
  for _, leg in ipairs(legs) do
    local isWorld = leg.mode == "world"
    steps[#steps + 1] = M.waitUntil(function()
      if isWorld then
        return M.worldHasControl() and M.worldAligned()
      end
      return not M.worldMode() and M.hasControl() and M.tileAligned()
    end, (leg.opts and leg.opts.modeWait) or 1200,
      "route: " .. leg.mode .. " mode + control", 5)
    steps[#steps + 1] = M.waitUntil(function()
      return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    end, 900, "route: " .. leg.mode .. " fade-in", 10)
    steps[#steps + 1] = M.waitFrames(30)
    steps[#steps + 1] = isWorld and M.worldNavTo(leg.x, leg.y, leg.opts)
                        or M.navTo(leg.x, leg.y, leg.opts)
  end
  return seqStep(steps)
end

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
