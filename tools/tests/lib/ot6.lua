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
-- THE OTHER HALF: this file is the battle core -- steps, input, memory,
-- savestates, battle signals, canaries, and the shared field-state reads.
-- The field/world NAVIGATION stack (passability model, BFS, navTo /
-- worldNavTo / advanceStory / route) lives in lib/ot6_field.lua, and
-- lib/compose.py inlines BOTH halves into every composed script -- the
-- dofile line above stays the only line a test writes, and H carries the
-- merged API.  The mint signature (lib/frontier_stamp.sh sig) hashes
-- generator ++ this file ++ ot6_field.lua, in that fixed order.
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
  --
  -- EVERY line carries the prefix, not just the first.  run.sh's terminal
  -- output is `grep '^\[ot6\]' "$RUN_LOG"` (run.sh:326), so an unprefixed
  -- continuation line reaches the log file and nothing else -- which is
  -- precisely backwards for the messages that have continuation lines, all
  -- of which are failures explaining themselves.  Measured 2026-07-30: a
  -- timeout's "the fixture you booted is stale" detail sat in the log while
  -- the terminal showed only "timeout after 120 frames waiting for main
  -- menu", the misleading half.
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
--
-- DUPLICATED NAMES.  ca65 scopes names per module, so a name can be defined
-- in two of them (`ExecCmd` is field code AND the battle command dispatcher;
-- 3838 of this ROM's 98483 label names are non-unique).  compose.py refuses
-- to guess: such a name is a compose-time error, and if it reached here at
-- all -- only possible when every occurrence was inside a comment -- it
-- raises below rather than returning either candidate.  Disambiguate by the
-- ca65 SEGMENT that defines it: H.sym("ExecCmd@battle_code").  Segment names
-- come from cfg/ff6-en.cfg and survive the bank shifts that move addresses,
-- so a qualified name is no more fragile than a bare one.
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
      M.lastState = sidecarPath:match("[^/]+$")
      M.log("loading savestate " .. M.lastState ..
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
      -- BATTERY SRAM RIDES THE SAVESTATE (re-measured 2026-08-04: markers
      -- planted in banks $30 and $31, changed live, both restored by
      -- emu.loadSavestate -- the old "savestates do NOT restore battery
      -- sram" comment here was wrong).  So post-load SRAM, weakness codex
      -- included, is a pure function of the fixture's own bytes: no wipe,
      -- no cross-segment leakage within a script, and no cross-run channel
      -- either (run.sh deletes <saves>/*.srm before every boot).  This used
      -- to be the site of an emu.write loop that re-formatted all four
      -- codex pages after every load -- an issue-#75 state write that also
      -- OVERWROTE the fixture's minted codex.  Runs that boot fresh instead
      -- of loading rely on the ROM's own lazy page formatting
      -- (Ot6CodexEnsure / Ot6CodexNewGame / Ot6CodexLoaded,
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

-- True once the battle module has begun loading.
--
-- $7E3BF4 is the party battle-HP table ONLY while the battle module owns that
-- RAM.  Every other module scribbles those bytes, so no single slot and no
-- single sentinel can answer "is a battle up?".  MEASURED shapes:
--
--   field                     FFFF FFFF FFFF FFFF
--   field menu (START)        FFFF FFFF FFFF FFFF
--   moogle defense, on-map    FF00 0020 FF00 0020   <- field scribble
--   party menu / world redraw 0000 0000 0000 0000   <- menu owns the bytes
--   live battle               003F 0044 003D 0000   <- slot 3 EMPTY reads 0
--   live battle, slot 0 dead  0000 0044 003D 0000
--
-- So the test is on the SHAPE of the whole table, not on one slot: every word
-- must be a plausible current HP -- 0 for an empty or dead slot, else 1..9999 --
-- and at least one character must actually be alive.  $FFFF and $FF00 are not
-- HP, and one of them anywhere means these bytes belong to somebody else.
--
-- Three earlier versions, each of which shipped and each of which cost a full
-- frontier re-mint.  Do not reinstate any of them:
--   * slot 0, rejecting 0 -- said "no battle" the moment the first character
--     died, so worldNavTo pressed directions into a live battle (#24).
--   * slot 0, $FFFF only -- said "battle" for every frame a menu was up, and
--     ridePartyMenu blind-A-hammered onto a Status page.
--   * any slot 1..9999 -- accepted the moogle scribble's 0020 and hung
--     gen_moogle for 30,000 frames on map 30.
-- The `< 10000` bound in the original was load-bearing and easy to mistake for
-- a sanity check: it is what rejects the FF00 scribble.
--
-- Known limit, deliberate: a TOTAL party wipe is all zeros, which is also what
-- a menu leaves, so this reports false.  Separating those needs a witness
-- outside this table; a wiped party in a fixture is a failure anyway.
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

-- Exported for lib/ot6_field.lua alone: route() there glues per-leg waits
-- and navigators into one step, and this combinator is the only core
-- LOCAL the field half needs by name (everything else it touches is
-- public M.* API).  Tests never call it -- they hand M.run a plain list,
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
-- and that sentence is a lie of omission often enough to matter.  The usual
-- cause is not the menu: it is that the savestate was minted against a
-- DIFFERENT ROM than the one running, so the first step needing a specific
-- frame -- typically the field X press -- lands on a frame the fixture's
-- timing no longer has.  Read literally the message sends you into the menu
-- code, and it has: at least one agent went looking for a product bug there.
--
-- So every timeout appends what the run actually knows: which fixture it
-- booted, and whether composition already flagged that fixture as minted from
-- sources this tree no longer has (OT6_STALE, emitted by lib/compose.py).
-- This adds context; it never suppresses the failure.
M.lastState = nil

function M.timeoutContext()
  if not M.lastState then
    return ""   -- power-on boot: no fixture to blame, say nothing
  end
  local out = "\n  fixture booted by this run: " .. M.lastState
  local stale = type(OT6_STALE) == "table" and OT6_STALE[M.lastState]
  if stale then
    out = out .. "\n  and it is STALE: " .. stale
    out = out .. "\n  A savestate minted against a different ROM resumes at a"
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
    .. " --check-states\n  Re-mint:  nice -n 10 ninja -f build/build.ninja <state>"
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
        error("timeout after " .. maxFrames .. " frames driving toward " .. what
          .. M.timeoutContext(), 0)
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

-- ------------------------------------------------------- field state --
-- Live reads of the field engine's party/story state.  Shared ground, so
-- they live in the battle core: suite battle tests that boot on a field
-- map read them to step into their encounter (battle_flyin picks its
-- walking lane, battle_kefka asserts the fixture's tile), and the whole
-- navigation stack in lib/ot6_field.lua is built on top of them.
-- Addresses from the vendored disassembly: party object pixel coords
-- $086a/$086d via the $0803 leader offset (src/field/player.asm), map
-- index $1f64 (battle.asm), player-control gate $1eb9 bit7 + map-load
-- $84 + menu-opening $59 (player.asm UpdatePlayerMovement).

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

-- ------------------------------------------------- honest battle endings --
-- Issue #75: a script may inject INPUT and READ memory; it may never WRITE
-- emulated game state.  These two end a battle the way a player can, with
-- zero writes -- the opt-in replacements for clearBattle's kill-bit.  The
-- kill-bit path above stays only while unconverted generators depend on it;
-- new scripts and converted legs use these.
--
-- fightBattle: WIN by edge-tapped A (4 on / 4 off).  A blind A masher is a
-- real strategy on the legs this is for: A on the top command opens the
-- actor's command list, A confirms its first entry, A accepts the default
-- target, and the early-game magitek beams one-shot their trash.  The proof
-- predates the helper: gen_sabin_magitek wins battles 15/16/17 by exactly
-- these taps because kill-bitting them softlocks the win-bit check, and the
-- vanilla-faithful intro guards die to one beam each.  The same edge taps
-- page through battle dialogs, level-ups, and the victory text.  `spare`
-- keeps clearBattle's goal-formation contract: if the battle we're asked to
-- fight IS the goal set-piece, that's a script bug -- fail loudly.
-- Budget note: an honest win costs real ATB rounds -- budget thousands of
-- frames where clearBattle needed hundreds.

-- A stateful controller for parties whose useful command is not necessarily
-- on row 0.  It reads the engine's live command table and cursor and builds a
-- paced controller episode from those observations.  The baseline policy is
-- Fight.  opts.tactical additionally lets Edgar use AutoCrossbow and Sabin use
-- Pummel -- their real early-game whole-side / boss tools -- while everyone
-- else Fights.  It writes nothing.  Button episodes use the menu-proven
-- 6-on/24-off cadence because inputs presented while a battle window is
-- opening are discarded.
--
-- Call frame() on every frame battleLoadStarted() is true and idle() on the
-- falling edge.  frame() sets the controller pad itself.
function M.newFightDriver(tag, opts)
  opts = opts or {}
  local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
  local CMDTBL, CMDROW, BCHID, BP, CURMP =
    0x202E, 0x890F, 0x3ED8, 0x3E9C, 0x3C08
  local CMD_FIGHT, CMD_ITEM, CMD_TOOLS, CMD_BLITZ = 0x00, 0x01, 0x09, 0x0A
  local ST_CMD, ST_ITEM, ST_TGT, ST_TOOLS = 0x05, 0x0A, 0x38, 0x30
  local ITEMSCR, ITEMROW, BATTINV, ITEMLIST = 0x8947, 0x894F, 0x2686, 0x4005
  local BLCOL, BLROW = 0x8963, 0x8967
  local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
  local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
  local AUTOCROSSBOW, PUMMEL = 0xAA, 0x5D
  local F = {}
  local menuStreak, tick, battleTick = 0, 0, 0
  local plan, planActor, held = nil, nil, {}

  local function cmdRow(actor, cmd)
    for row = 0, 3 do
      if M.readByte(CMDTBL + actor * 12 + row * 3) == cmd then
        return row
      end
    end
    return nil
  end

  -- opts.reserve = { [itemId] = n } -- never spend the last n.  THE BAG IS
  -- SHARED ACROSS SCENARIOS, which is a thing this chain learned the hard
  -- way: the Terra party burned its way through every Potion crossing Mt.
  -- Kolts, and solo LOCKE then started his own scenario with two Tonics
  -- and nothing else against a soldier who hits for 115.  A party that
  -- drinks the last Potion because the hole was big enough is not playing
  -- the same game a player is.
  local function battInvIdx(id)
    local floor = (opts.reserve or {})[id] or 0
    for i = 0, 251 do
      if M.readByte(BATTINV + i * 5) == id
         and M.readByte(BATTINV + i * 5 + 3) > floor then return i end
    end
    return nil
  end

  local function makePlan(actor)
    local row = opts.items and cmdRow(actor, CMD_ITEM) or nil
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
    -- THE BOOST BANK.  Spending one BP the moment you have one is the worst
    -- way to play OT6's economy: Ot6ShieldedMulW halves damage while a
    -- monster still has shields, and the ladder is broken:weak:unweak =
    -- 4:2:1 (ot6_break.asm:1487-1497), so the whole game is "boost to break,
    -- THEN hit".  A boosted Fight chips shields per hit; a 1-BP dribble
    -- chips slowly and never gets there.  opts.bank says "act unboosted --
    -- which is itself what regenerates BP, Ot6ActionEnd -- until the bank
    -- reads at least this, then unload."  gen_sfigaro's own steal drive has
    -- always done exactly this and nobody had applied it to Fights.
    local have = M.readByte(BP + actor * 2)
    local boost = 0
    if opts.boost then
      if opts.bank and have < opts.bank then boost = 0
      else boost = math.min(have, 3) end
    end
    if opts.tactical and id == 4 and M.readWord(CURMP + actor * 2) >= 4
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
      plan, planActor = makePlan(actor), actor
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
      -- Use the index RESOLVED WHEN THE PLAN WAS MADE, not a fresh read.
      -- Mid-menu inventory reads measurably lie (gen_sabin_train's shop
      -- drive learned the same thing and verifies purchases only after the
      -- window closes), and a lying read here returns nil, drops the plan,
      -- presses B, and re-plans -- forever.  Measured at battle 11: solo
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
        local wantMask = 1 << plan.target
        if chars ~= wantMask then
          local cur = 0
          for e = 0, 3 do
            if chars & (1 << e) ~= 0 then cur = e; break end
          end
          return { cur < plan.target and "down" or "up" }
        end
      end
      plan, planActor = nil, nil
      return { "a" }
    end
    if st == ST_ITEM or st == ST_TOOLS then
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
      -- eight bytes along ($3BF4 + (4+s)*2).  Logging it is what turns "we
      -- lost" into "we lost AND the boss never dropped below 400", which is
      -- the difference between a harness bug and a balance finding.
      local mhp = {}
      for s2 = 0, 5 do
        local id = M.readWord(M.MONSTER_IDS + s2 * 2)
        if id ~= 0xFFFF and id ~= 0 then
          -- hp, and the SHIELD count beside it: shields live at
          -- $3E38 + entity*2 and monsters are entities 4..9, so slot s is
          -- $3E40 + s*2 (battle_break.lua:34).  Without this the log says
          -- "we are barely scratching it" and cannot say WHY -- shielded
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
    if opts.trace and battleTick % 2 == 0 then
      M.log(string.format("  [%s trace] f+%d menu=%02X st=%02X actor=%d " ..
        "cur=%d plan=%s held=%s", tag or "fight", battleTick, menu,
        M.readByte(MSTATE), M.readByte(ACTOR) & 3, M.readByte(CMDROW +
        (M.readByte(ACTOR) & 3)) & 3, plan and plan.kind or "-",
        held and next(held) and table.concat(held, "+") or "."))
    end
    tick = tick + 1
    -- ONE PRESS PER `cadence` FRAMES, and the number is a real handicap, not
    -- a detail.  At the historical 30 a single boosted Fight costs four
    -- press cycles -- three R's and an A -- which is TWO SECONDS of wall
    -- clock to type one command.  Measured 2026-08-09 on battle 11 (solo
    -- LOCKE, level 8, versus a 495-hp HeavyArmor): he got about three
    -- decisions per fight and lost three attempts running, while a player
    -- typing at any ordinary speed gets ten.  That is the harness losing
    -- the fight, not the party.  6-on/6-off is still comfortably slower
    -- than a human mashing, and it stays clear of the menu's auto-repeat
    -- threshold; callers that have a reason to be slow can ask for it.
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
  }, "fight battle honestly (tap-A)")
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
  }, "fight battle honestly through the Fight menu")
end

-- fleeBattle: hold L+R -- the engine's own run mechanic (see the pad map
-- above; vanilla's run timer counts held L or R).  Shifts fewer frames than
-- fighting when it works, but FAILS (times out) on unrunnable formations
-- and on every event battle whose win-bit the story checks -- callers pick
-- fight vs flee per leg and say why.  Zero writes.
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
