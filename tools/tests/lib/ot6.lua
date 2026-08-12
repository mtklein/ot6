-- ot6.lua -- test-harness helpers for OT6 under Mesen 2's headless testrunner.
--
-- Usage pattern (see gen_battle_state.lua / battle_smoke.lua):
--
--   local H = dofile("tools/tests/lib/ot6.lua")
--   H.run({ maxFrames = 60000 }, {
--     H.waitFrames(60),
--     H.pressButtons({ "start" }, 8),
--     H.waitUntil(function() return H.battleActive() end, 5000, "battle"),
--     H.call(function() H.assertEq(H.readByte(0x7E3E44), 2, "shields") end),
--   })
--
-- The script is a list of steps consumed one per frame by a startFrame event
-- callback.  Every step constructor returns a step object; steps that do
-- work without consuming a frame (call/log/hold/release) chain within the
-- same frame.  The script always terminates: run() enforces a global frame
-- budget and calls emu.stop(2) if the steps run past it.  Exit codes:
--   0 = steps completed         1 = Lua error / failed assert / timeout
--   2 = frame budget exceeded   (testrunner exit code = emu.stop code)
--
-- Why step lists: the library builds scripts as explicit step lists driven
-- by a startFrame callback.  This was originally justified by "coroutines
-- crash Mesen".  Coroutines do not crash Mesen; the failure was the
-- testrunner's wall-clock cap (exit 255, stdout lost) misread as a crash,
-- and coroutines run clean.  The step style stays because the whole suite
-- is written in it.
--
-- This file is the battle core: steps, input, memory, savestates, battle
-- signals, canaries, and the shared field-state reads.
-- The field/world navigation stack (passability model, BFS, navTo /
-- worldNavTo / advanceStory / route) lives in lib/ot6_field.lua, and
-- lib/compose.py inlines both halves into every composed script, so the
-- dofile line above stays the only line a test writes, and H carries the
-- merged API.  The freshness signature (lib/savestate_stamp.sh sig) hashes
-- generator ++ this file ++ ot6_field.lua, in that fixed order.
--
-- Environment notes (Mesen 2.1.1, verified against Mesen's source):
--  * Lua 5.4.  print() goes to the testrunner's stdout.  emu.log() goes to
--    the script log, which nothing reads headless, and --enableStdout does
--    not mirror it (that flag mirrors the emulator message log).  Lua errors
--    and watchdog kills land in the script log too, so they are not visible
--    anywhere.  Use print().
--  * io/os are nil and dofile()/loadfile() raise.  That comes from the
--    setting Debug.ScriptWindow.AllowIoOsAccess (default false), which is
--    configurable rather than a fixed sandbox.  We keep it off and inline
--    everything at compose time, so binary blobs travel as base64: out via
--    print("[b64:tag] ..."), in via compose-time embedding.  run.sh decodes
--    [b64:*] payloads after a run.
--  * Port 0 is a SnesController in the test config, so emu.setInput() is
--    live; input is pushed from an inputPolled callback (see below).

local M = {}

local seqStep -- forward declaration (defined in the step-runner section)

-- ---------------------------------------------------------------- logging --
function M.log(msg)
  -- print goes to the testrunner's stdout.  emu.log() is deliberately not
  -- used: it is invisible under --testrunner and calling it from callbacks
  -- is a crash suspect (see the "Working notes" section of the README).
  --
  -- Every line carries the prefix, including continuation lines.  run.sh's
  -- terminal output is `grep '^\[ot6\]' "$RUN_LOG"` (run.sh:326), so an
  -- unprefixed continuation line reaches the log file and nothing else.
  -- The messages that have continuation lines are all failures explaining
  -- themselves, so those are the lines the terminal most needs.  Measured
  -- 2026-07-30: a timeout's "the fixture you booted is stale" detail sat in
  -- the log while the terminal showed only "timeout after 120 frames
  -- waiting for main menu", which is the misleading half.
  msg = tostring(msg)
  for line in (msg .. "\n"):gmatch("([^\n]*)\n") do
    print("[ot6] " .. line)
  end
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
        n = n & ((1 << bits) - 1) -- keep only the leftover bits
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
-- Controller input follows Mesen's recommended pattern: emu.setInput(input,
-- port) applied inside an `inputPolled` event callback.  setInput's effect
-- lasts until the next poll, so applying it on every poll guarantees the ROM
-- latches our state each frame.  Port 0 is a SnesController in the test
-- config, so setInput is live.
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
      emu.setInput(curPad, 0)             -- argument order is (input, port)
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
-- button is released, since the script owns the pad and there is no human
-- player.
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

-- OT6 symbol address, derived from ff6/rom/ff6-en.dbg at compose time and
-- injected as the global OT6_SYMS (lib/compose.py, the same mechanism that
-- embeds savestate sidecars as OT6_STATES).  Returns the ca65 `val`: a 24-bit
-- SNES CPU address (e.g. RandA = 0xC24B98), which is what an exec/read
-- memory callback wants.  For a snesPrgRom file offset (readRomByte/Word),
-- mask & 0x3FFFFF: banks $C0-$FF are HiROM, so file = cpu & 0x3FFFFF ($C0:0000
-- -> $000000, $F0:0000 -> $300000).  Errors if the symbol is absent,
-- which means the ROM was not (re)built, the name is wrong, or the script was
-- run raw instead of through run.sh (which composes OT6_SYMS in).  Deriving
-- the address this way replaces hand-maintained address literals, which went
-- stale on every bank-$F0/$C2/$C0 shift.
--
-- Duplicated names: ca65 scopes names per module, so a name can be defined
-- in two of them (`ExecCmd` is both field code and the battle command
-- dispatcher; 3838 of this ROM's 98483 label names are non-unique).
-- compose.py does not guess: such a name is a compose-time error, and if it
-- reached here at all, which is only possible when every occurrence was
-- inside a comment, it raises below rather than returning either candidate.
-- Disambiguate by the ca65 segment that defines it:
-- H.sym("ExecCmd@battle_code").  Segment names come from cfg/ff6-en.cfg and
-- survive the bank shifts that move addresses, so a qualified name is no
-- more fragile than a bare one.
function M.sym(name)
  if type(OT6_SYMS) == "table" and OT6_SYMS[name] then
    return OT6_SYMS[name]
  end
  if type(OT6_SYMS_AMBIG) == "table" and OT6_SYMS_AMBIG[name] then
    local bare = name:match("^[^@]*")
    local firstSeg = OT6_SYMS_AMBIG[name]:match("^([^=]*)=")
    error("symbol " .. tostring(name) .. " is AMBIGUOUS in ff6-en.dbg ("
      .. OT6_SYMS_AMBIG[name] .. ") -- name the segment you mean, e.g. "
      .. 'H.sym("' .. bare .. "@" .. tostring(firstSeg) .. '")', 2)
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
-- an exec memory callback for the main CPU ("This function must be called
-- inside an exec memory operation callback"), and not inside an event
-- callback.  So requests go through a one-shot trampoline: register an exec
-- callback over the full address space, do the work on its first fire (the
-- next instruction the CPU executes), and unregister from within the callback.
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
-- as OT6_STATES[basename], which is the only path.  There is no loadfile()
-- fallback because loadfile raises under the default sandbox setting
-- (Debug.ScriptWindow.AllowIoOsAccess=false), so a fallback could never fire
-- and would replace a clear error with a confusing one.
function M.resolveStateB64(sidecarPath)
  local base = sidecarPath:match("[^/]+$")
  if type(OT6_STATES) == "table" and OT6_STATES[base] then
    return OT6_STATES[base]
  end
  error("savestate sidecar not embedded: " .. sidecarPath ..
    " (compose.py inlines these; run through run.sh, not raw)")
end

-- Step: capture the current state and emit it as build/states/<name>.
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

-- Step: load a savestate captured earlier (path to the .mss.lua sidecar).
function M.loadState(sidecarPath)
  local req
  return seqStep({
    M.call(function()
      local blob = M.b64decode(M.resolveStateB64(sidecarPath))
      assert(#blob > 0, "empty savestate blob for " .. sidecarPath)
      M.lastState = sidecarPath:match("[^/]+$")
      M.log("loading savestate " .. M.lastState ..
        " (" .. #blob .. " bytes)")
      req = M.requestLoadState(blob)
    end),
    M.waitFrames(2),
    M.call(function()
      checkReq(req, "savestate load")
      -- Savestate loads do not detach callbacks (nothing in Mesen's load
      -- path clears them; battle_banner registers exec callbacks before its
      -- load and records straight through).  This call is a no-op once
      -- inputCbRef is set; it is kept so the input hook is live
      -- on paths that load before ever arming it.
      M.rearmInputInjection()
      -- Battery SRAM rides the savestate (re-measured 2026-08-04: markers
      -- planted in banks $30 and $31, changed live, both restored by
      -- emu.loadSavestate; the earlier "savestates do NOT restore battery
      -- sram" comment here was wrong).  Post-load SRAM, weakness codex
      -- included, is therefore a function of the fixture's own bytes: no
      -- wipe, no cross-segment leakage within a script, and no cross-run
      -- channel either (run.sh deletes <saves>/*.srm before every boot).
      -- This used to be the site of an emu.write loop that re-formatted all
      -- four codex pages after every load, an issue-#75 state write that
      -- also overwrote the codex the fixture was generated with.  Runs that
      -- boot fresh instead of loading rely on the ROM's own lazy page
      -- formatting (Ot6CodexEnsure / Ot6CodexNewGame / Ot6CodexLoaded,
      -- ff6/src/battle/ot6_codex.asm): an unsigned page is zeroed and
      -- signed 'O8' by the game the first time anything touches the codex.
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
-- +4 five tilemap words).  This must track OT6_SHADOW in
-- ff6/src/battle/ot6.asm.
-- It lived at $5762 until 2026-07-18, when that address turned out to be
-- inside vanilla's `ram_res w7e5755, 128`; three suite tests had the old
-- address copy-pasted in and started reading vanilla's buffer when it
-- moved.  Read it from here rather than inlining it, so the next move is
-- one edit.
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

-- True once the battle module has begun loading.
--
-- $7E3BF4 is the party battle-HP table only while the battle module owns that
-- RAM.  Every other module writes over those bytes, so no single slot and no
-- single sentinel can say whether a battle is up.  Measured shapes:
--
--   field                     FFFF FFFF FFFF FFFF
--   field menu (START)        FFFF FFFF FFFF FFFF
--   moogle defense, on-map    FF00 0020 FF00 0020   <- field write
--   party menu / world redraw 0000 0000 0000 0000   <- menu owns the bytes
--   live battle               003F 0044 003D 0000   <- empty slot 3 reads 0
--   live battle, slot 0 dead  0000 0044 003D 0000
--
-- So the test looks at the shape of the whole table rather than one slot:
-- every word must be a plausible current HP, 0 for an empty or dead slot and
-- otherwise 1..9999, and at least one character must be alive.  $FFFF and
-- $FF00 are not HP values, so one of them anywhere means these bytes belong
-- to another module.
--
-- Three earlier versions shipped, and each cost a regeneration of every
-- savestate in the chain.  Do not reinstate any of them:
--   * slot 0, rejecting 0: reported no battle as soon as the first character
--     died, so worldNavTo pressed directions into a live battle (#24).
--   * slot 0, $FFFF only: reported a battle for every frame a menu was up,
--     and ridePartyMenu's blind A presses landed on a Status page.
--   * any slot 1..9999: accepted the moogle write's 0020 and hung
--     gen_moogle for 30,000 frames on map 30.
-- The `< 10000` bound in the original is what rejects the $FF00 write, and it
-- is easy to mistake for a sanity check.
--
-- Known limit, accepted: a total party wipe is all zeros, which is also what
-- a menu leaves, so this reports false.  Separating those needs a check
-- outside this table, and a wiped party in a fixture is a failure anyway.
-- Regression: battle_loadgate.lua.
function M.battleLoadStarted()
  local anyLive = false
  for i = 0, 3 do
    local hp = M.readWord(M.BATTLE_HP + i * 2)
    if hp >= 10000 then return false end   -- $FFFF, $FF00: not an HP table
    if hp > 0 then anyLive = true end
  end
  return anyLive
end

-- Cheap "is anything on screen" check: an all-black 256x224 screenshot
-- compresses to ~750 bytes, the battle-transition mosaic to ~2.3 KB, and a
-- real battle scene (bg + sprites + UI windows) to ~10 KB.  4000 separates
-- the transition from a real battle scene.
function M.screenLooksAlive()
  local ok, png = pcall(emu.takeScreenshot)
  return ok and type(png) == "string" and #png > 4000
end

-- True while a battle is fully up and rendering.  A crashed battle load,
-- which this harness has caught, leaves the screen black and fails this
-- check.  emu.getState() is deliberately not used here: polling it was
-- correlated with emulator crashes.
function M.battleActive()
  return M.battleLoadStarted() and M.monstersPresent() > 0 and M.screenLooksAlive()
end

-- ------------------------------------------------------- the step runner --
-- A step is a table { tick = function(self) return "frame"|"done" end }.
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

-- Exported for lib/ot6_field.lua alone: route() there combines per-segment
-- waits and navigators into one step, and this combinator is the only core
-- local the field half needs by name (everything else it touches is
-- public M.* API).  Tests never call it; they hand M.run a plain list,
-- and cond/repeatN/driveUntil wrap it internally.
M.seqStep = seqStep

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

-- ---------------------------------------------------------- timeout blame --
-- A wait that runs out says "timeout after 600 frames waiting for main menu",
-- which often omits the real cause.  The usual cause is that the savestate
-- was generated against a different ROM than the one running, so the first
-- step needing a specific frame, typically the field X press, lands on a
-- frame the fixture's timing no longer has.  Read literally, the message
-- points at the menu code, and at least one agent went looking for a product
-- bug there.
--
-- So every timeout appends what the run knows: which fixture it
-- booted, and whether composition already flagged that fixture as generated
-- from sources this tree no longer has (OT6_STALE, emitted by lib/compose.py).
-- This adds context and does not suppress the failure.
M.lastState = nil

function M.timeoutContext()
  if not M.lastState then
    return ""   -- power-on boot: no fixture to name, so add nothing
  end
  local out = "\n  fixture booted by this run: " .. M.lastState
  local stale = type(OT6_STALE) == "table" and OT6_STALE[M.lastState]
  if stale then
    out = out .. "\n  and it is STALE: " .. stale
    out = out .. "\n  A savestate generated against a different ROM resumes at a"
      .. " PC and a frame parity that\n  have since moved, so the first input"
      .. " needing a specific frame is where it surfaces --\n  usually as a"
      .. " timeout on something innocent, like this one."
  else
    out = out .. "\n  (composition did not flag it stale, so a ROM/fixture"
      .. " mismatch is less likely here --\n  but rule it out before you"
      .. " suspect the feature: a timeout on an input step is what a\n"
      .. "  mismatched pairing looks like.)"
  end
  return out .. "\n  Confirm: python3 tools/tests/lib/compose.py"
    .. " --check-states\n  Regenerate: nice -n 10 ninja -f build/build.ninja <state>"
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
        error("timeout after " .. maxFrames .. " frames waiting for " .. what
          .. M.timeoutContext(), 0)
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
-- "Reached" means each fresh pass.  Task #17 (found by the codex_ctx
-- conversion) was this step latching its first-tick branch forever:
-- it had no reset, so inside a driveUntil body, whose steps replay every
-- cycle via seqStep:reset(), the predicate was consulted once in
-- the step's lifetime and every later cycle replayed the stale
-- branch.  reset() now clears the choice so a replayed cond re-asks its
-- predicate, which is what every driveUntil body was already assuming.
-- Top-level steps and the H.cond(function() return won end, ...) form
-- tick once and are never reset, so their behavior is unchanged.
function M.cond(pred, thenSteps, elseSteps)
  local chosen = nil
  return {
    tick = function()
      if chosen == nil then
        chosen = pred() and seqStep(thenSteps) or seqStep(elseSteps or {})
      end
      return chosen:tick()
    end,
    reset = function()
      chosen = nil
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
-- Completion releases the pad: pred can fire mid-body-cycle, abandoning the
-- body wherever it stands, and a button it was holding at that instant must
-- not stay held into the steps that follow.  (A stuck d-pad auto-repeats
-- the battle-menu cursor and a stuck A confirms into target selection;
-- both affected battle_boost and battle_preview when input injection moved
-- to hardware-faithful next-poll timing.  navTo/advanceStory/clearBattle
-- already release in their preds, and this is the same contract for every
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
        error("timeout after " .. maxFrames .. " frames driving toward " .. what
          .. M.timeoutContext(), 0)
      end
      local r = body:tick()
      if r == "done" then body:reset() end
      return "frame"
    end,
  }
end

-- Step: the standard first-battle entry from a `*_entry` fixture.  The
-- battle_entry savestate parks the party one step short of its
-- encounter trigger, and entering the fight is always the same sequence:
-- hold up long enough to commit the step (20 frames), release and let
-- the engine settle (2), tap A (pressButtons' 4 on / 2 off, which clears
-- any incidental dialog), and cycle until the battle module starts loading;
-- then wait for the battle to be fully up and rendering.  battleActive()
-- takes a screenshot per poll (screenLooksAlive), so the wait polls
-- every 30 frames rather than every frame.
--
-- Deliberately option-free: dozens of tests enter their first fight
-- through this exact sequence, and the constants are part of each
-- test's frame/RNG landing, since a different hold or wait changes which
-- frame the encounter fires on.  This helper gives that majority one
-- definition instead of a copy in each test (31 verbatim copies
-- when it was extracted, several already drifted); a test that needs a
-- different entry (another direction, other timeouts, battle-clearing
-- flag handling, a story scene that walks into its own fight) keeps writing
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

-- ----------------------------------------------------- battle rng seed --
-- The retry ladder's mechanism, measured (issue #83) rather than assumed.
--
-- A battle's whole RNG stream hangs off one byte, seeded once at battle
-- init (ff6/src/battle/battle_main.asm:6174-6176, inside InitBattle
-- at :6138):
--
--     lda     $021e       ; low byte of game time (frames)
--     asl2
--     sta     $be         ; set random number seed
--
-- $021e is wGameTimeFrames (ff6/src/menu/menu_ram.inc:343, the last byte of
-- the $021b hours/minutes/seconds/frames block).  IncGameTime
-- (ff6/src/menu/menu_common.asm:3522-3549) runs it 1..60 and wraps, and it is
-- ticked once per vblank from the field, world and battle NMIs
-- (field/reset.asm:286, world/interrupt.asm:33/320/584,
-- btlgfx/btlgfx_main.asm:1763) and from the menu (menu_common.asm:3496).  A
-- is 8-bit at the store, so the seed is (frames * 4) & $FF: 60 values, 4..240,
-- one per phase.  $be is then the index every battle Rand/RandA/RandCarry
-- walks through RNGTbl (battle_main.asm:12640-12666).
--
-- So the ladder's premise holds -- waiting frames before a fight does move
-- the seed -- but the constant it used did not follow from it.  Measured with
-- probe_ladder_seed.lua on battle_entry's first encounter:
--
--   * attempts 2 and 3 reload the entry blob and then spend a fixed ~92
--     frames of trampoline and settle before their own (n-1)*37, so they land
--     37 apart reliably;
--   * attempt 1 runs in place, so its phase is whatever the generator's own
--     step layout leaves between the blob capture and the entry drive.  That
--     term is not measured anywhere.  Re-running one ladder with 36 frames of
--     lead in front of attempt 1 put attempts 1 and 2 on the same seed $9C
--     with attempt 3 at $4C -- #80's reported signature, one fight played
--     twice;
--   * the drive from the wait to InitBattle took 96..99 frames across six
--     attempts, so even a reliable 37 arrives at the seed as 40.  The stagger
--     is not preserved by construction.
--
-- newSeedLadder replaces the constant with the counter it is trying to move:
-- each attempt waits until $021e reaches its own target phase, spaced as
-- widely as 60 phases allow, and the seed each attempt actually drew is read
-- off the store instruction and required to be distinct.  A ladder that plays
-- one fight twice is the failure mode with no symptom, so it fails the run.

M.SEED_PHASE = 0x021E                   -- wGameTimeFrames
M.SEED_PERIOD = 60                      -- IncGameTime's 1..60 cycle

-- The live phase, and the seed a battle initialising right now would draw.
function M.seedPhase() return M.readByte(M.SEED_PHASE) end
function M.seedOf(phase) return (phase * 4) & 0xFF end

-- Address of the `sta $be` store, found by its bytes rather than copied:
-- AD 1E 02 (lda abs $021e), 0A 0A (asl a, asl a), 85 BE (sta dp $be), scanned
-- forward from InitBattle.  battle_main moves whenever a hook shim changes
-- size, and a stale literal here would silently watch the wrong instruction
-- and report a green ladder forever.  Requiring exactly one match makes a
-- moved or rewritten seeder an error rather than a miss.
local SEED_SIG = { 0xAD, 0x1E, 0x02, 0x0A, 0x0A, 0x85, 0xBE }
local seedStoreAddr = nil
function M.seedStoreAddr()
  if seedStoreAddr then return seedStoreAddr end
  local base = M.sym("InitBattle") & 0x3FFFFF   -- HiROM: cpu addr -> file offset
  local hits = {}
  for off = 0, 0x200 - #SEED_SIG do
    local ok = true
    for i = 1, #SEED_SIG do
      if M.readRomByte(base + off + i - 1) ~= SEED_SIG[i] then ok = false break end
    end
    if ok then hits[#hits + 1] = base + off end
  end
  if #hits ~= 1 then
    error(string.format("battle seed store (lda $021e/asl2/sta $be) not uniquely "
      .. "located within InitBattle+$200: %d matches.  battle_main.asm:6174-6176 "
      .. "is what this looks for; if the seeder changed, this lib changes with it.",
      #hits), 0)
  end
  seedStoreAddr = (hits[1] | 0xC00000) + 5      -- +5 skips lda(3) + asl(1) + asl(1)
  return seedStoreAddr
end

-- A retry ladder that cannot quietly play one fight twice.
--
--   local L = H.newSeedLadder("battle 70")
--   H.run({...}, {
--     ...
--     L.watch(),                  -- once, before the first attempt
--     attempt(1), attempt(2), attempt(3),
--     L.report(),                 -- once, after the last
--   })
--
-- and inside attempt(n), where `H.waitFrames((n - 1) * 37)` used to sit:
--
--     L.spread(n),
--
-- spread(n) latches attempt 1's phase and then holds each later attempt until
-- $021e reaches base + 20*(n-1), which is the widest even spacing three
-- attempts fit into the 60-phase cycle.  The seed the fight actually drew is
-- captured at the store and checked by report(): distinct across attempts, and
-- present for every attempt that ran, so a watcher that never fired fails
-- rather than passing silently.
--
-- opts.attempts (default 3) only sets the spacing.  It is not a licence to
-- widen the ladder: three is the doctrine (#74), and a ladder that loses three
-- different fights is reporting a finding.
function M.newSeedLadder(tag, opts)
  opts = opts or {}
  local attempts = opts.attempts or 3
  local gap = opts.gap or (M.SEED_PERIOD // attempts)
  local L = { tag = tag or "ladder", seeds = {}, extras = {}, targets = {},
              spreads = {} }
  local base, cur, watching = nil, 0, false

  -- Every attempt that called spread(), in order, with the seed its first
  -- battle drew.  Later seedings inside the same attempt (a fled random
  -- encounter on the way back to the fight) are counted but not compared:
  -- what decides "same fight twice" is the first battle after the spread.
  L.watch = function()
    return M.call(function()
      if watching then return end
      watching = true
      local addr = M.seedStoreAddr()
      M.log(string.format("[%s] watching the battle seed store at $%06X "
        .. "(InitBattle=$%06X)", L.tag, addr, M.sym("InitBattle")))
      emu.addMemoryCallback(function()
        if cur == 0 then return end               -- battles before the ladder
        -- Mesen fires exec callbacks before the instruction runs, so A is the
        -- value about to land in $be.
        local seed = emu.getState()["cpu.a"] & 0xff
        local phase = M.seedPhase()
        if L.seeds[cur] then
          L.extras[cur] = (L.extras[cur] or 0) + 1
          return
        end
        L.seeds[cur] = { seed = seed, phase = phase, frame = M.frame }
        M.log(string.format("[%s] attempt %d seeded $be=$%02X from $021e=%d at f%d",
          L.tag, cur, seed, phase, M.frame))
      end, emu.callbackType.exec, addr, addr)
    end)
  end

  -- The spread, derived from the counter the seed is made of.  Replaces
  -- H.waitFrames((n - 1) * 37).  opts.forcePhase pins the target outright and
  -- exists so a negative control can drive two attempts onto one seed and
  -- watch report() fail; nothing else should pass it.
  L.spread = function(n, sopts)
    sopts = sopts or {}
    local target = nil
    return seqStep({
      M.call(function()
        assert(watching, L.tag .. ": L.watch() must run before L.spread()")
        cur = n
        L.spreads[n] = true               -- this attempt owes report() a seed
        L.seeds[n] = nil                          -- this attempt's own fight
        local now = M.seedPhase()
        local forced = sopts.forcePhase
        if type(forced) == "function" then forced = forced() end
        if n == 1 and not forced then base = now end
        assert(base, L.tag .. ": spread(1) must run before spread(" .. n .. ")")
        target = forced or (((base - 1) + gap * (n - 1)) % M.SEED_PERIOD) + 1
        L.targets[n] = target
        M.log(string.format("[%s] attempt %d: phase %d -> target %d "
          .. "(seed $%02X), base %d gap %d%s",
          L.tag, n, now, target, M.seedOf(target), base, gap,
          forced and "  [forcePhase -- negative control]" or ""))
      end),
      -- Not M.waitUntil: `target` is only known once the step above has run,
      -- and waitUntil bakes its description at construction time.  The budget
      -- is three cycles; one is enough if the clock ticks once per frame, so a
      -- timeout here means it does not tick at this point in the route, which
      -- is a finding about the seed rather than about the wait.
      (function()
        local waited = 0
        return {
          tick = function()
            if M.seedPhase() == target then
              M.log(string.format("[%s] attempt %d on phase %d after %d frames",
                L.tag, n, target, waited))
              return "done"
            end
            waited = waited + 1
            if waited > M.SEED_PERIOD * 3 then
              error(string.format("%s: attempt %d never reached game-time phase "
                .. "%d in %d frames (now %d).  $021e is not advancing here, so "
                .. "no wait of any length can move the battle seed at this point "
                .. "in the route.", L.tag, n, target, waited, M.seedPhase()), 0)
            end
            return "frame"
          end,
          reset = function() waited = 0 end,
        }
      end)(),
    })
  end

  -- The check.  Fails on a repeated seed, and fails when nothing was
  -- recorded, so a watcher pointed at the wrong instruction cannot report the
  -- same green as a ladder that genuinely spread.
  L.report = function()
    return M.call(function()
      local ran, silent = {}, {}
      for n = 1, attempts do
        if L.seeds[n] then ran[#ran + 1] = n
        elseif L.spreads[n] then silent[#silent + 1] = n end
      end
      -- An attempt that took a phase and then drew no seed is a battle the
      -- watcher missed, not an attempt that skipped the fight: every ladder
      -- here spreads immediately before an engagement it cannot avoid.  Say so
      -- rather than comparing whatever is left, which is how a check quietly
      -- stops covering the thing it names.  Checked before the empty case
      -- below, because it is the more specific account of the same symptom.
      assert(#silent == 0, string.format(
        "%s: attempt(s) %s took a battle RNG phase and then drew no seed.  The "
        .. "watcher is on `sta $be` at battle init, so either that attempt "
        .. "never reached a battle -- in which case this ladder's shape moved "
        .. "and the spread is in the wrong place -- or the watcher missed one.",
        L.tag, table.concat(silent, ", ")))
      assert(#ran > 0, L.tag .. ": no battle seeding was recorded for any "
        .. "attempt.  Either no attempt reached a battle, or the seed watcher "
        .. "never fired -- both make the distinctness check vacuous.")
      local bySeed = {}
      for _, n in ipairs(ran) do
        local s = L.seeds[n]
        M.log(string.format("[%s] attempt %d drew $be=$%02X (phase %d, f%d%s)",
          L.tag, n, s.seed, s.phase, s.frame,
          L.extras[n] and (", " .. L.extras[n] .. " later battles") or ""))
        local prev = bySeed[s.seed]
        if prev then
          error(string.format("%s: attempts %d and %d both drew battle RNG seed "
            .. "$%02X (game-time phase %d).  Same seed and the same route is "
            .. "the same fight, so these %d attempts are fewer than %d "
            .. "different fights and their verdict is not evidence about the "
            .. "encounter.  Spread the attempts, do not widen the ladder (#74).",
            L.tag, prev, n, s.seed, s.phase, #ran, #ran), 0)
        end
        bySeed[s.seed] = n
      end
      M.log(string.format("[%s] %d attempt(s), %d distinct battle RNG seeds",
        L.tag, #ran, #ran))
      -- Go inert.  The exec callback cannot be removed from outside one (Mesen
      -- wants that on the CPU's own thread), and clearGateSoldier builds a
      -- fresh ladder per engagement, so a finished ladder's watcher would
      -- otherwise keep charging later battles to its last attempt.
      cur = 0
    end)
  end

  return L
end

-- ------------------------------------------------------- field state --
-- Live reads of the field engine's party/story state.  These are shared, so
-- they live in the battle core: suite battle tests that boot on a field
-- map read them to step into their encounter (battle_flyin picks its
-- walking lane, battle_kefka asserts the fixture's tile), and the
-- navigation stack in lib/ot6_field.lua is built on top of them.
-- Addresses from the vendored disassembly: party object pixel coords
-- $086a/$086d via the $0803 leader offset (src/field/player.asm), map
-- index $1f64 (battle.asm), player-control gate $1eb9 bit7 + map-load
-- $84 + menu-opening $59 (player.asm UpdatePlayerMovement).

-- The active party's object record: $0803 holds the byte offset of the
-- party leader's object block (`ldy $0803; lda $086a,y`, in player.asm,
-- reset.asm and elsewhere).  Character 0 (TERRA) owns object offset 0, and
-- TERRA led every fixture up to the Moogle defense, so absolute reads of
-- $086A/$087C were correct for months.  The defense then made
-- LOCKE (object offset $29) the leader, and the lib kept reading TERRA's
-- knocked-out object: position froze at her (14,12) while party 1 stood at
-- (14,14), and hasControl never went true (measured, gen_moogle run 2).
-- Every party-relative read must go through this offset.
local function pobj() return M.readWord(0x0803) end

-- Live tile position = party-object pixel coords >> 4 ($086a x / $086d y,
-- 16-bit, offset by $0803).  The $1fc0/$1fc1 bytes are a lazily-updated
-- cache and go stale mid-walk, so do not navigate on them.
function M.fieldX() return M.readWord(0x086a + pobj()) >> 4 end
function M.fieldY() return M.readWord(0x086d + pobj()) >> 4 end
function M.mapId() return M.readWord(0x1f64) end

-- At rest exactly on a tile: every sub-tile position bit is zero (sub-pixel
-- bytes $0869/$086c plus the low 4 pixel bits of each 16-bit coord).
-- Position samples for navigation are only valid when this holds: the
-- tile coord (pixel>>4) flips early (~1px in) when moving up/left but only
-- at completion moving down/right, so mid-step reads are direction-skewed.
function M.tileAligned()
  local po = pobj()
  return (M.readByte(0x0869 + po) | (M.readByte(0x086a + po) & 0x0F)
        | M.readByte(0x086c + po) | (M.readByte(0x086d + po) & 0x0F)) == 0
end

-- An event script is executing iff the 24-bit event PC {$e5,$e6,$e7}
-- points into the event-script segment (banks $CA-$CC) and is off its idle
-- parking value $ca/0000.  The bank test matters: ambient NPC object
-- scripts (a stove flame, a wandering townsperson) run through the same
-- interpreter out of their RAM queue, and the PC reads $80xxxx (WRAM mirror)
-- for one frame at a time, every few frames, indefinitely on such maps.
-- Those excursions do not mean an event is running, and counting them broke
-- every consecutive-calm-frames predicate (measured in Arvis's house:
-- $800000 one frame in four).
function M.eventRunning()
  local bank = M.readByte(0x00e7)
  if bank < 0xCA or bank > 0xCC then return false end
  return not (bank == 0xCA and M.readByte(0x00e5) == 0
          and M.readByte(0x00e6) == 0)
end

-- A dialog window is open and waiting for a keypress ($ba dialog state,
-- $d3 waiting-for-key).  Advancing is edge-triggered: one held A yields
-- one edge, and multiple pages need press, release, press (4 on / 4 off).
function M.dialogWaiting()
  return M.readByte(0x00ba) == 1 and M.readByte(0x00d3) == 1
end

-- True only when the party can be walked this frame.  Beyond the
-- control-gate flags this checks the party movement type ($087c,y low
-- nibble via the $0803 offset: 2 = user-controlled, 4 = event-controlled;
-- events can walk the party while every other flag looks clear)
-- and the event PC.  Deliberately cheap: RAM reads only, no screenshots
-- (battleLoadStarted is the battle gate, and battleActive()'s screen check
-- is too expensive for a per-frame poll).
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
-- fully torn down.  The A taps are edge-pressed (4 on / 4 off): dialog and
-- victory-text advancing is edge-triggered, so a continuous hold yields
-- one page.  `spare` (optional list of formation species
-- words) is the goal-formation guard: if the battle we are asked to clear
-- is the goal fight, that is a script bug, so this fails with an error
-- instead of instantly killing the fight the route exists to reach.
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

-- -------------------------------------------- input-driven battle endings --
-- Issue #75: a script may inject input and read memory, and may never write
-- emulated game state.  These two end a battle the way a player can, with
-- no writes, and are the opt-in replacements for clearBattle's flag write.
-- The flag-write path above stays while unconverted generators depend on
-- it; new scripts and converted steps use these.
--
-- fightBattle: win by edge-tapped A (4 on / 4 off).  Repeated A presses are
-- a workable strategy on the steps this is for: A on the top command opens
-- the actor's command list, A confirms its first entry, A accepts the
-- default target, and the early-game magitek beams kill their targets in one
-- hit.  This predates the helper: gen_sabin_magitek wins battles 15/16/17 by
-- these taps because the flag write softlocks the win-bit check, and the
-- vanilla-faithful intro guards die to one beam each.  The same edge taps
-- page through battle dialogs, level-ups, and the victory text.  `spare`
-- keeps clearBattle's goal-formation contract: if the battle we are asked to
-- fight is the goal set-piece, that is a script bug and this fails with an
-- error.  Budget note: a played-out win costs real ATB rounds, so budget
-- thousands of frames where clearBattle needed hundreds.

-- ------------------------------------------------------- target cursor --
-- The battle target-select steering machine, consolidated from four
-- copies (battle_steal, battle_stealmp, battle_thief, battle_magicite,
-- the #75 mech family).  The measured facts it encodes:
--   * the live cursor mask ($7B7E monster / $7B7D character) blinks,
--     reading 0 on off-frames, so the mask is latched while target select
--     ($7BC2 == $38) is up, and the latch/age/press state resets as soon
--     as target select is down.  A latch that survives between selections
--     confirms immediately on the previous action's cursor (battle_steal's
--     measured wrong-monster steal off a stale latch);
--   * steering rotates the d-pad one direction per press cycle rather than
--     per frame; a per-frame rotation flips direction mid-hold and registers
--     nothing (battle_steal's measurement);
--   * the cursor grid follows the formation's screen layout, so rotating
--     through all four directions settles on any reachable slot: monster
--     grids walk {left,down,right,up} (battle_steal's measured 08 -left->
--     04 -down-> 01), character columns {down,up,left,right}.
-- Known limit (probe_tgtcursor, measured on mrf_entry's 2x2 group-80
-- formation): the two-press rotation cycles among three hover positions
-- and the ally column, and cannot reach a slot that needs a bare
-- up-then-right (left,left -> $08; up -> $04; right -> $01).  All four
-- masks are reachable by single presses with a dwell between them; a
-- caller whose formation needs that steers with its own press plan and
-- uses only the latch half of this machine.
-- opts: mask = 0x7B7E (monster, default) or 0x7B7D (character); dirs = the
-- rotation list; minAge = settled frames before confirming (default 4).
-- Use: call observe() once per drive frame, in any menu state (it manages
-- its own reset); inside ST_TGT call steer(targetSlot, mf), which returns a
-- button name: "a" once the latched mask has settled on 1<<targetSlot for
-- minAge frames (or immediately when targetSlot is nil, which takes the
-- default), otherwise the next rotation direction.  mf is the caller's
-- drive-frame counter, the same one that paces its press cadence.
function M.targetCursor(opts)
  opts = opts or {}
  local mask = opts.mask or 0x7B7E
  local dirs = opts.dirs or { "left", "down", "right", "up" }
  local minAge = opts.minAge or 4
  local T = { mask = nil, age = 0, press = 0 }
  function T.observe()
    if M.readByte(0x7BC2) == 0x38 then
      local m = M.readByte(mask)
      if m ~= 0 then
        if m == T.mask then T.age = T.age + 1
        else T.mask, T.age = m, 1 end
      end
    else
      T.mask, T.age, T.press = nil, 0, 0
    end
  end
  function T.steer(target, mf)
    if target == nil then return "a" end
    if T.mask == (1 << target) and T.age >= minAge then return "a" end
    if (mf - 1) % 8 == 0 then T.press = T.press + 1 end
    return dirs[((T.press - 1) // 2) % #dirs + 1]
  end
  return T
end

-- A stateful controller for parties whose useful command is not necessarily
-- on row 0.  It reads the engine's live command table and cursor and builds a
-- paced controller episode from those observations.  The baseline policy is
-- Fight.  opts.tactical additionally lets Edgar use AutoCrossbow and Sabin use
-- Pummel, their early-game whole-side and boss tools, while everyone
-- else Fights.  It writes nothing.  Button episodes use the 6-on/24-off
-- cadence proven in the menus, because inputs presented while a battle window
-- is opening are discarded.
--
-- Call frame() on every frame battleLoadStarted() is true and idle() on the
-- falling edge.  frame() sets the controller pad itself.
function M.newFightDriver(tag, opts)
  opts = opts or {}
  local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
  local CMDTBL, CMDROW, BCHID, BP, CURMP =
    0x202E, 0x890F, 0x3ED8, 0x3E9C, 0x3C08
  local CMD_FIGHT, CMD_ITEM, CMD_MAGIC, CMD_TOOLS, CMD_BLITZ =
    0x00, 0x01, 0x02, 0x09, 0x0A
  local ST_CMD, ST_ITEM, ST_MAGIC, ST_TGT, ST_TOOLS, ST_ESPER =
    0x05, 0x0A, 0x0E, 0x38, 0x30, 0x16
  local ITEMSCR, ITEMROW, BATTINV, ITEMLIST = 0x8947, 0x894F, 0x2686, 0x4005
  local BLCOL, BLROW = 0x8963, 0x8967
  -- the magic list's cursor triple (btlgfx_main UpdateMenuState_0e:
  -- scroll+row is the absolute grid row, col the column; master record
  -- rec maps to cell (rec-1)//2 , (rec-1)%2, the mapping battle_brokendeath
  -- measured and used to drive Celes's Ice at record 8)
  local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B
  local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
  local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
  local AUTOCROSSBOW, PUMMEL = 0xAA, 0x5D
  local F = {}
  local menuStreak, tick, battleTick = 0, 0, 0
  local plan, planActor, held = nil, nil, {}
  local tgtSpin = 0                    -- frames spent undecided in ST_TGT

  local function cmdRow(actor, cmd)
    for row = 0, 3 do
      if M.readByte(CMDTBL + actor * 12 + row * 3) == cmd then
        return row
      end
    end
    return nil
  end

  -- opts.reserve = { [itemId] = n }: never spend the last n.  The bag is
  -- shared across scenarios: the Terra party used every Potion crossing Mt.
  -- Kolts, and solo LOCKE then started his own scenario with two Tonics
  -- and nothing else against a soldier who hits for 115.  A party that
  -- spends the last Potion whenever the HP gap is large enough is not
  -- playing the way a player does.
  local function battInvIdx(id)
    local floor = (opts.reserve or {})[id] or 0
    for i = 0, 251 do
      if M.readByte(BATTINV + i * 5) == id
         and M.readByte(BATTINV + i * 5 + 3) > floor then return i end
    end
    return nil
  end

  local function makePlan(actor)
    -- opts.healer = <battle chid>: only that character runs the item
    -- healing line; everyone else attacks.  Measured need (2026-08-09, the
    -- escape cave): with every actor healing, a party whose only damage is
    -- LOCKE's Fight heal-locks, because one enemy round costs more HP than
    -- the Tonic his turn restores, so he never attacks, the monster never
    -- dies, and the bag drains to a wipe.  A player splits the jobs, with
    -- the safe back-row member healing and the fighter fighting.  Unset
    -- means the earlier behavior, in which every actor may heal, which is
    -- right for solo parties.
    local mayHeal = opts.healer == nil
        or M.readByte(BCHID + actor * 2) == opts.healer
    local row = (opts.items and mayHeal) and cmdRow(actor, CMD_ITEM) or nil
    if row ~= nil then
      for e = 0, 3 do
        if M.readWord(0x3C1C + e * 2) > 0 and M.readWord(0x3BF4 + e * 2) == 0
           and battInvIdx(FENIX_DOWN) then
          M.log(string.format("[%s] actor=%d revive entity %d with Fenix Down",
            tag or "fight", actor, e))
          return { kind = "item", item = FENIX_DOWN, target = e, row = row,
                   idx = battInvIdx(FENIX_DOWN) }
        end
      end
      local target, worst = nil, 101
      local threshold = opts.healPercent or 60
      for e = 0, 3 do
        local hp, maxhp = M.readWord(0x3BF4 + e * 2), M.readWord(0x3C1C + e * 2)
        if hp > 0 and maxhp > 0 then
          local pct = hp * 100 // maxhp
          if pct < threshold and pct < worst then target, worst = e, pct end
        end
      end
      if target ~= nil then
        local hp, maxhp = M.readWord(0x3BF4 + target * 2),
                          M.readWord(0x3C1C + target * 2)
        local item = (maxhp - hp >= 80 and battInvIdx(POTION)) and POTION
                  or battInvIdx(TONIC) and TONIC
                  or battInvIdx(POTION) and POTION or nil
        if item then
          M.log(string.format("[%s] actor=%d heal entity %d (%d/%d) with $%02X",
            tag or "fight", actor, target, hp, maxhp, item))
          return { kind = "item", item = item, target = target, row = row,
                   idx = battInvIdx(item) }
        end
      end
    end
    local id = M.readByte(BCHID + actor * 2)
    -- The boost bank.  Spending one BP as soon as it is available plays
    -- OT6's economy badly: Ot6ShieldedMulW halves damage while a
    -- monster still has shields, and the damage ratios are broken:weak:
    -- unweak = 4:2:1 (ot6_break.asm:1487-1497), so the intended play is to
    -- boost until the shield breaks and then hit.  A boosted Fight removes
    -- shields faster per hit; spending 1 BP at a time removes them slowly
    -- and often never breaks them.  opts.bank means: act unboosted, which is
    -- what regenerates BP (Ot6ActionEnd), until the bank reads at least this
    -- value, then spend.  gen_sfigaro's steal drive already worked this way,
    -- and it had not been applied to Fights.
    local have = M.readByte(BP + actor * 2)
    local boost = 0
    if opts.boost then
      if opts.bank and have < opts.bank then boost = 0
      else boost = math.min(have, 3) end
    end
    -- opts.summon = { [charId] = { mp = cost } }: the once-per-battle genju,
    -- through the menu route battle_magicite measured (2026-07-27): from the
    -- magic list scrolled to the top, UP runs CheckHasGenju and opens the
    -- esper window ($7BC2 = $16), A commits, and A confirms the default
    -- target.  The engine's latch is the gate: the caster's entity bit in
    -- $3f2e, which once set makes UpdateEnabledMagic grey the row
    -- (battle_magicite point 3), so the plan is offered only while that bit
    -- is clear and the character can pay.  The Magic command row only exists
    -- while the stone is worn (battle_subjob's grant), so an unequipped
    -- caller falls through to the branches below the same way a mage out of
    -- MP does.  Written for the Cranes re-test (2026-08-10): BISMARK's Sea
    -- Song is the game's only water attack, and water is that fight's
    -- intended weakness.
    local sm = opts.summon and opts.summon[id]
    if sm and M.readWord(CURMP + actor * 2) >= (sm.mp or 50)
       and (M.readWord(0x3f2e) & M.readWord(0x3018 + actor * 2)) == 0
       and cmdRow(actor, CMD_MAGIC) then
      return { kind = "summon", row = cmdRow(actor, CMD_MAGIC) }
    end
    -- opts.magic = { [charId] = { rec = N, mp = cost } }: the attack-magic
    -- line, the same shape as the tactical skills.  Open the Magic list
    -- through the $7BC2 state machine, steer to master record N against
    -- the live cursor cells, and confirm on the default enemy target.  The
    -- caller supplies the record number, which is a measured grid position
    -- rather than a spell id, and the MP cost; a character below the cost
    -- falls through to the branches below, so a mage out of MP Fights
    -- instead of wedging the menu.
    local mg = opts.magic and opts.magic[id]
    if mg and M.readWord(CURMP + actor * 2) >= (mg.mp or 8)
       and cmdRow(actor, CMD_MAGIC) then
      return { kind = "magic", rec = mg.rec, row = cmdRow(actor, CMD_MAGIC),
               boostLeft = boost }
    end
    -- opts.tools = false disables the Tools line while keeping the rest of
    -- the tactical kit.  Measured need (2026-08-10, the Cranes): AutoCrossbow
    -- hits all targets, and each Crane counts every hit in an if_hit retal
    -- var; past the threshold the victim casts on its sibling the element
    -- that sibling absorbs (Bolt2/Fire2 across the deck; +329 hp observed on
    -- the Left Crane, more than three of our boosted hits undone).  Against
    -- a formation where a multi-target attack heals the enemy, Edgar's
    -- single-target pierce Fight removes the same class-weak shields without
    -- triggering the sibling heal.
    if opts.tactical and opts.tools ~= false and id == 4
       and M.readWord(CURMP + actor * 2) >= 4
       and cmdRow(actor, CMD_TOOLS) then
      return { kind = "skill", cmd = CMD_TOOLS, skill = AUTOCROSSBOW,
               row = cmdRow(actor, CMD_TOOLS), boostLeft = boost }
    end
    if opts.tactical and id == 5 and M.readWord(CURMP + actor * 2) >= 4
       and cmdRow(actor, CMD_BLITZ) then
      return { kind = "skill", cmd = CMD_BLITZ, skill = PUMMEL,
               row = cmdRow(actor, CMD_BLITZ), boostLeft = boost }
    end
    local fight = cmdRow(actor, CMD_FIGHT)
    if fight == nil then return { kind = "switch" } end
    return { kind = "fight", row = fight, boostLeft = boost }
  end

  local function button(actor)
    local st = M.readByte(MSTATE)
    if plan == nil or planActor ~= actor then
      if st ~= ST_CMD then return nil end
      plan, planActor, tgtSpin = makePlan(actor), actor, 0
      M.log(string.format("[%s] actor=%d char=%d plan=%s",
        tag or "fight", actor, M.readByte(BCHID + actor * 2), plan.kind))
      return nil
    end
    if st == ST_CMD then
      if plan.kind == "switch" then return { "x" } end
      if plan.boostLeft and plan.boostLeft > 0 then
        plan.boostLeft = plan.boostLeft - 1
        return { "r" }
      end
      local cur = M.readByte(CMDROW + actor) & 3
      if cur == plan.row then return { "a" } end
      return { cur < plan.row and "down" or "up" }
    end
    if st == ST_ITEM and plan.kind == "item" then
      -- Use the index resolved when the plan was made rather than a fresh
      -- read.  Mid-menu inventory reads return wrong values (gen_sabin_train's
      -- shop drive hit the same thing and verifies purchases only after the
      -- window closes), and a wrong read here returns nil, drops the plan,
      -- presses B, and re-plans, without end.  Measured at battle 11: solo
      -- LOCKE logged "heal entity 0 (58/168) with $E9" twice in three
      -- hundred frames with his HP never moving, and died holding four
      -- Potions.
      local want = plan.idx or battInvIdx(plan.item)
      if want == nil then plan, planActor = nil, nil; return { "b" } end
      local cur = M.readByte(ITEMSCR + actor) + M.readByte(ITEMROW + actor)
      if cur < want then return { "down" } end
      if cur > want then return { "up" } end
      return { "a" }
    end
    if st == ST_MAGIC and plan.kind == "summon" then
      -- UP walks the grid cursor to the top and, from the top, opens the
      -- esper window, so one button serves both phases (the cursor cells are
      -- live, so this converges from any scroll position).
      return { "up" }
    end
    if st == ST_ESPER and plan.kind == "summon" then
      return { "a" }
    end
    if st == ST_MAGIC and plan.kind == "magic" then
      local idx = plan.rec - 1
      local wr, wc = idx // 2, idx % 2
      local ar = M.readByte(MSCROLL + actor) + M.readByte(MROW + actor)
      local col = M.readByte(MCOL + actor)
      if ar < wr then return { "down" } end
      if ar > wr then return { "up" } end
      if col < wc then return { "right" } end
      if col > wc then return { "left" } end
      return { "a" }
    end
    if st == ST_TOOLS and plan.kind == "skill" then
      local want
      for i = 0, 7 do
        if M.readByte(ITEMLIST + i * 3) == plan.skill then want = i; break end
      end
      if want == nil then plan, planActor = nil, nil; return { "b" } end
      local wc, wr = want % 2, want // 2
      local cc, cr = M.readByte(BLCOL + actor), M.readByte(BLROW + actor)
      if cc ~= wc then return { wc > cc and "right" or "left" } end
      if cr ~= wr then return { wr > cr and "down" or "up" } end
      return { "a" }
    end
    if st == ST_TGT then
      if plan.kind == "item" then
        local chars, mons = M.readByte(TGTCHARS), M.readByte(TGTMONS)
        if mons ~= 0 then return { "right" } end
        -- Neither side is selected.  The old code fell into the
        -- steer below with chars = 0, which sets cur = 0, compares
        -- `0 < plan.target`, false for target 0, and presses UP
        -- without end.  A solo party's only valid target is 0, so this
        -- deadlock can only happen to a party of one, which is
        -- the shape of battle 11.
        if chars == 0 then return { "right" } end
        local wantMask = 1 << plan.target
        if chars ~= wantMask then
          local cur = 0
          for e = 0, 3 do
            if chars & (1 << e) ~= 0 then cur = e; break end
          end
          -- Even with a live mask, an unreachable target would spin
          -- here.  tgtSpin is the backstop: after enough undecided frames,
          -- confirm on whoever is highlighted rather than hold the turn open
          -- until the fight is lost.
          tgtSpin = tgtSpin + 1
          if tgtSpin < 40 then
            return { cur < plan.target and "down" or "up" }
          end
          M.log(string.format("[%s] target steer gave up (chars=%02X " ..
            "want=%02X) -- confirming on whoever is highlighted",
            tag or "fight", chars, wantMask))
        end
      end
      -- opts.focus = { {slot=S, mask=M}, ... }: monster kill order, steered
      -- against the live target mask ($7B7E) the way the item line
      -- steers $7B7D.  Each entry names a monster slot (for the liveness
      -- check against $3BFC) and the $7B7E mask bit that puts the cursor on
      -- it.  These are two different orderings, measured different
      -- (2026-08-10, the Cranes): the mask's bit 0 is the cursor's default
      -- rest position and landed damage on slot 1 ($010E), so mask bits
      -- follow the on-screen formation layout rather than monster-table
      -- order.  The need comes from the same fight: each Crane counts hits in
      -- an if_hit retal var, and past the threshold the victim casts on its
      -- sibling the element that sibling absorbs.  With the unfocused
      -- default (everyone on the Right), the Right Crane cast Bolt2 into the
      -- Left all fight: the Left healed to full each time, and because Bolt2
      -- is lightning the same casts walked the Left's Giga Volt charge to
      -- level 3, whose damage wiped the party ($010D at 1800/1800 across
      -- three attempts' close dumps).
      -- Focus picks the first entry whose slot is still alive; single-
      -- target plans steer to its mask (summons and items keep their own
      -- targeting), and the tgtSpin backstop still confirms rather than
      -- holding the turn open.
      if opts.focus and plan.kind ~= "item" and plan.kind ~= "summon" then
        local want = nil
        for _, e in ipairs(opts.focus) do
          local mid = M.readWord(M.MONSTER_IDS + e.slot * 2)
          if mid ~= 0 and mid ~= 0xFFFF
             and M.readWord(0x3BFC + e.slot * 2) > 0 then want = e.mask; break end
        end
        if want ~= nil then
          local mons = M.readByte(TGTMONS)
          if mons ~= want then
            tgtSpin = tgtSpin + 1
            if tgtSpin < 24 then
              -- on the ally side (mons == 0), LEFT crosses to the enemy
              -- side.  Among monsters the walk leads with LEFT/RIGHT,
              -- measured on the Cranes (side-by-side formation): 24 ticks
              -- of down/up never moved the rest mask, so the pair is a
              -- horizontal walk
              if mons == 0 then return { "left" } end
              local dirs = { "left", "right", "down", "up" }
              return { dirs[1 + ((tgtSpin // 6) % 4)] }
            end
            M.log(string.format("[%s] focus steer gave up (mons=%02X " ..
              "want=%02X) -- confirming on whoever is highlighted",
              tag or "fight", mons, want))
          end
        end
      end
      if opts.traceTgt then
        M.log(string.format("[%s] tgt CONFIRM kind=%s actor=%d chars=%02X "
          .. "mons=%02X", tag or "fight", plan.kind, actor,
          M.readByte(TGTCHARS), M.readByte(TGTMONS)))
      end
      plan, planActor, tgtSpin = nil, nil, 0
      return { "a" }
    end
    if st == ST_ITEM or st == ST_TOOLS or st == ST_MAGIC or st == ST_ESPER then
      plan, planActor = nil, nil
      return { "b" }
    end
    return nil
  end

  function F.idle()
    menuStreak, tick, battleTick = 0, 0, 0
    plan, planActor, held = nil, nil, {}
  end

  function F.frame()
    battleTick = battleTick + 1
    local menu = M.readByte(MENU)
    if battleTick == 1 or battleTick % 300 == 0 then
      local actor, state = M.readByte(ACTOR) & 3, M.readByte(MSTATE)
      local rows = {}
      for row = 0, 3 do
        rows[#rows + 1] = string.format("%02X",
          M.readByte(CMDTBL + actor * 12 + row * 3))
      end
      local hp = {}
      for e = 0, 3 do hp[#hp + 1] = tostring(M.readWord(0x3BF4 + e * 2)) end
      -- monsters live in entity slots 4..9, so their HP is the same table
      -- eight bytes along ($3BF4 + (4+s)*2).  Logging it records how much
      -- damage the party did, which is what separates a harness bug from a
      -- balance finding.
      local mhp = {}
      for s2 = 0, 5 do
        local id = M.readWord(M.MONSTER_IDS + s2 * 2)
        if id ~= 0xFFFF and id ~= 0 then
          -- hp, and the shield count beside it: shields live at
          -- $3E38 + entity*2 and monsters are entities 4..9, so slot s is
          -- $3E40 + s*2 (battle_break.lua:34).  Without the shield count the
          -- log shows low damage without showing the cause, since shielded
          -- damage is halved and a broken monster takes 4x.
          mhp[#mhp + 1] = string.format("%d/sh%d",
            M.readWord(0x3BFC + s2 * 2), M.readByte(0x3E40 + s2 * 2))
        end
      end
      M.log(string.format("[%s] battle f+%d menu=%02X state=%02X actor=%d " ..
        "cursor=%d cmds=%s partyhp=%s monhp=%s monsters=%d", tag or "fight",
        battleTick, menu, state, actor, M.readByte(CMDROW + actor) & 3,
        table.concat(rows, ","), table.concat(hp, ","),
        table.concat(mhp, ","), M.monstersPresent()))
    end
    if menu == 0 then
      -- Text pages, victory screens, and the command-window handoff all need
      -- A eventually.  Preserve the old edge-A behavior only while there is
      -- no interactive menu to steer.
      menuStreak, tick = 0, 0
      plan, planActor, held = nil, nil, {}
      M.setPad((M.frame % 8 < 4) and { "a" } or {})
      return
    end

    menuStreak = menuStreak + 1
    if menuStreak < 4 then M.setPad({}); return end
    local traceActor = M.readByte(ACTOR) & 3
    if opts.trace and M.readByte(MSTATE) == ST_ITEM then
      -- the item window, in full: the cursor sum the driver steers ($8947
      -- scroll + $894F row) beside the battle inventory it computes
      -- its target index from ($2686, 5 bytes/entry: id at +0, qty at +3).
      -- If those two disagree about what row 3 is, every heal confirms the
      -- wrong item, which is the symptom being debugged.
      local inv = {}
      for i = 0, 11 do
        local id, qty = M.readByte(BATTINV + i * 5), M.readByte(BATTINV + i * 5 + 3)
        inv[#inv + 1] = string.format("%d:%02X x%d", i, id, qty)
      end
      M.log(string.format("  [%s ITEM] scroll=%d row=%d sum=%d want=%s | %s",
        tag or "fight", M.readByte(ITEMSCR + traceActor),
        M.readByte(ITEMROW + traceActor),
        M.readByte(ITEMSCR + traceActor) + M.readByte(ITEMROW + traceActor),
        plan and tostring(plan.idx) or "-", table.concat(inv, " ")))
    end
    if opts.trace and battleTick % 2 == 0 then
      M.log(string.format("  [%s trace] f+%d menu=%02X st=%02X actor=%d " ..
        "cur=%d plan=%s held=%s", tag or "fight", battleTick, menu,
        M.readByte(MSTATE), M.readByte(ACTOR) & 3, M.readByte(CMDROW +
        (M.readByte(ACTOR) & 3)) & 3, plan and plan.kind or "-",
        held and next(held) and table.concat(held, "+") or "."))
    end
    tick = tick + 1
    -- One press per `cadence` frames, and the number affects outcomes.
    -- At the historical 30 a single boosted Fight costs four
    -- press cycles, three R presses and an A, which is two seconds of wall
    -- clock to enter one command.  Measured 2026-08-09 on battle 11 (solo
    -- LOCKE, level 8, versus a 495-hp HeavyArmor): he got about three
    -- decisions per fight and lost three attempts in a row, while a player
    -- pressing at an ordinary speed gets ten.  The loss came from the input
    -- rate rather than the party.  6-on/6-off is still slower
    -- than a human pressing buttons, and it stays clear of the menu's
    -- auto-repeat threshold; callers that have a reason to be slow can ask
    -- for it.
    local ph = tick % (opts.cadence or 30)
    local actor = M.readByte(ACTOR) & 3
    if plan and planActor ~= actor then plan, planActor = nil, nil end
    if ph == 0 then held = button(actor) or {} end
    M.setPad(ph < 6 and held or {})
  end

  return F
end

function M.fightBattle(maxFrames, spare)
  local spareSet = {}
  for _, w in ipairs(spare or {}) do spareSet[w] = true end
  local aPhase = 0
  return M.driveUntil(function()
    return not M.battleLoadStarted()
  end, maxFrames or 20000, {
    M.call(function()
      aPhase = (aPhase + 1) % 8
      if M.battleLoadStarted() and next(spareSet) and M.formationHas(spareSet) then
        error("fightBattle: asked to auto-fight a spared formation " ..
          string.format("(%04X %04X %04X %04X %04X %04X)",
            table.unpack(M.formationWords())), 0)
      end
      M.setPad(aPhase < 4 and { "a" } or {})
    end),
  }, "fight battle (tap-A)")
end

-- The command-table-aware counterpart to fightBattle().  Prefer this for a
-- mixed party or any route where command row 0 is not proven to be Fight.
function M.fightBattleByMenu(maxFrames, spare)
  local spareSet = {}
  for _, w in ipairs(spare or {}) do spareSet[w] = true end
  local F = M.newFightDriver("fightBattleByMenu")
  return M.driveUntil(function()
    return not M.battleLoadStarted()
  end, maxFrames or 30000, {
    M.call(function()
      if M.battleLoadStarted() and next(spareSet) and M.formationHas(spareSet) then
        error("fightBattleByMenu: asked to auto-fight a spared formation " ..
          string.format("(%04X %04X %04X %04X %04X %04X)",
            table.unpack(M.formationWords())), 0)
      end
      F.frame()
    end),
  }, "fight battle through the Fight menu")
end

-- fleeBattle: hold L+R, which is the engine's run mechanic (see the pad map
-- above; vanilla's run timer counts held L or R).  It takes fewer frames than
-- fighting when it works, and it times out on unrunnable formations
-- and on every event battle whose win-bit the story checks, so callers pick
-- fight or flee per step and record why.  No writes.
function M.fleeBattle(maxFrames)
  return M.driveUntil(function()
    return not M.battleLoadStarted()
  end, maxFrames or 9000, {
    M.call(function() M.setPad({ l = true, r = true }) end),
  }, "flee battle (hold L+R)")
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
