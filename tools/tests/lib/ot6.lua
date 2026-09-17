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
  -- print goes to the testrunner's stdout.  emu.log() is not used: it is
  -- invisible under --testrunner and calling it from callbacks is a crash
  -- suspect.
  --
  -- Every line carries the prefix, including continuation lines.  run.sh's
  -- terminal output is `grep '^\[ot6\]' "$RUN_LOG"`, so an unprefixed
  -- continuation line reaches the log file and nothing else.
  msg = tostring(msg)
  if OT6_LIVE then
    -- the live broadcast's note stream, one line per call, newlines folded
    print("[ot6note] " .. (M.frame or 0) .. " " .. msg:gsub("\n", " | "))
  end
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
  -- The end marker (lib/decode_b64.py): one tag can carry several
  -- emissions in one log -- a ladder screenshotting each attempt, and now
  -- a retried segment re-emitting every artifact on its replay.  The
  -- decoder used to split them on base64 padding alone, which cannot see
  -- a boundary when the payload's length is a multiple of three; that
  -- concatenates two emissions into one corrupt file.  This line says
  -- where each one ends.
  print("[b64end:" .. tag .. "] " .. #data)
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

-- ------------------------------------------------------ live broadcast --
-- run.sh prepends `OT6_LIVE = <n>` to the composed copy (on by default;
-- OT6_LIVE=0 in the environment disables, a number > 1 sets the screenshot
-- interval in frames, default 128).  The taps ride stdout into the run log,
-- which tools/stream/live.py follows while the run happens:
--
--   [ot6shot] <frame> <b64 png>       a screenshot every interval frames
--   [ot6pad] <frame> <btn+btn|-->     emitted from setPad, only on change
--   [ot6note] <frame> <text>          emitted from M.log, one line per call
--
-- None carry the [ot6] prefix, so run.sh's terminal grep skips them and
-- they exist only in the log file.  The frame stamp is M.frame; the pad set
-- here is latched by the ROM at the frame's inputPolled, so it can land one
-- frame after the stamp.
local LIVE_IVL = (type(OT6_LIVE) == "number" and OT6_LIVE > 1) and OT6_LIVE
                 or 128
function M.liveShot()
  local png = emu.takeScreenshot()
  if png and #png > 0 then
    print("[ot6shot] " .. M.frame .. " " .. M.b64encode(png))
  end
end
local recPadLast = nil
local function recordPad()
  local held = {}
  for _, b in ipairs(ALL_BTN) do
    if curPad[b] then held[#held + 1] = b end
  end
  local s = (#held > 0) and table.concat(held, "+") or "--"
  if s ~= recPadLast then
    recPadLast = s
    print("[ot6pad] " .. M.frame .. " " .. s)
  end
end

-- The post-game-over pad freeze (#153).  A game over must end the
-- attempt: whatever a driver presses after one is a press into the
-- annihilated screen, the fade, or the title's Continue -- and one A there
-- loads the last save while every predicate reads healthy again.  So from
-- the moment the canary counts a game over until the script restores a
-- snapshot (M.requestLoadState, the ladders' recovery path), setPad holds
-- the pad neutral.  A run without allowGameOver has already stopped by
-- then; a ladder that reloads and clears M.gameOverFired never notices.
M.padFrozen = false
local padFrozenSaid = false
function M.freezePad(why)
  if M.padFrozen then return end
  M.padFrozen = true
  padFrozenSaid = false
  M.log(string.format("pad frozen (f%d): %s -- no further presses until a " ..
    "snapshot is restored, so nothing here can Continue a save", M.frame, why))
end
function M.thawPad()
  M.padFrozen = false
end

-- Set the held-button set ({"a","down"} or {a=true,down=true}); every other
-- button is released, since the script owns the pad and there is no human
-- player.
function M.setPad(buttons)
  for _, b in ipairs(ALL_BTN) do curPad[b] = false end
  if M.padFrozen then
    if buttons ~= nil and next(buttons) ~= nil and not padFrozenSaid then
      padFrozenSaid = true
      M.log(string.format("pad frozen: a press was dropped at f%d (the run " ..
        "is past a game over; restore a snapshot to press again)", M.frame))
    end
    buttons = nil
  end
  for k, v in pairs(buttons or {}) do
    local name = (type(k) == "number") and v or (v and k or nil)
    if name then
      if curPad[name] == nil then error("unknown button: " .. tostring(name)) end
      curPad[name] = true
    end
  end
  if OT6_LIVE then recordPad() end
end

-- ------------------------------------------------ callback registration --
-- The retry runner at the bottom of this file replays a segment's body
-- after a seed-dependent failure.  Mesen only lets a callback be removed
-- from inside a CPU callback, so the previous attempt's callbacks cannot
-- be unregistered; they are made INERT instead, by an attempt-epoch guard
-- that M.segmentBody wraps around emu.addMemoryCallback /
-- emu.addEventCallback before the body ever runs.
--
-- Two kinds of registration must survive a replay and so are made through
-- the raw handles captured here, before that shim exists: the one-shot
-- savestate trampolines (an inert load trampoline would strand the run
-- mid-reload) and the run canary (an inert canary is a silent
-- auto-Continue).  Everything else -- the ladders' seed watchers, the
-- recovery/exec observers, a generator's own logging watches -- is
-- re-registered by the replayed body and wants the old copy inert.
local rawAddMemoryCallback = emu.addMemoryCallback
local rawAddEventCallback = emu.addEventCallback

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
-- injected as the global OT6_SYMS (lib/compose.py).  Returns the ca65 `val`:
-- a 24-bit SNES CPU address (e.g. RandA = 0xC24B98).  For a snesPrgRom file
-- offset (readRomByte/Word), mask & 0x3FFFFF: banks $C0-$FF are HiROM, so
-- file = cpu & 0x3FFFFF ($C0:0000 -> $000000, $F0:0000 -> $300000).
--
-- A name can be defined in two modules (ca65 scopes per module); such a
-- name is a compose-time error unless every occurrence was inside a
-- comment, in which case it raises below.  Disambiguate by the ca65 segment
-- that defines it: H.sym("ExecCmd@battle_code").
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
-- an exec memory callback for the main CPU, not inside an event callback.
-- So requests go through a one-shot trampoline: register an exec callback
-- over the full address space, do the work on its first fire, and
-- unregister from within the callback.  Results are harvested a frame or
-- two later by the calling step.
--
-- Persistence: sandboxed Lua cannot write files, so blobs round-trip through
-- stdout: [b64:<name>] lines that run.sh decodes into
--   build/states/<name>          (raw Mesen savestate, loadable in the GUI)
--   build/states/<name>.lua      (sidecar: `return "<base64>"`)
-- and lib/compose.py embeds referenced sidecars back in as OT6_STATES.

-- How many trampolines are registered and not yet fired.  Two pending at
-- once collide: both register over the full address space, the first
-- fires, removes itself and returns, and Mesen then invokes the second
-- with its "inside an exec callback" state already cleared, so its
-- createSavestate/loadSavestate is refused ("This function must be called
-- inside an exec memory operation callback" -- measured 2026-09-16 when
-- the segment runner's boot snapshot landed on the same frame as a
-- generator's fixture load).  The runner waits for zero before it asks.
M.pendingStateReqs = 0

function M.requestSaveState()
  local req = {}
  local ref
  M.pendingStateReqs = M.pendingStateReqs + 1
  ref = rawAddMemoryCallback(function()
    if req.fired then return end
    req.fired = true
    M.pendingStateReqs = M.pendingStateReqs - 1
    local ok, err = pcall(function() req.blob = emu.createSavestate() end)
    req.ok = ok and type(req.blob) == "string" and #req.blob > 0
    req.error = err
    req.done = true
    emu.removeMemoryCallback(ref, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  end, emu.callbackType.exec, 0x000000, 0xFFFFFF)
  return req
end

function M.requestLoadState(blob)
  M.finishRecoveryTrace("state_reload")
  -- a restored snapshot restarts the experiment: the post-game-over pad
  -- freeze (see M.freezePad) ends here, with the game over it answered --
  -- and so does the runner's memory of a counted game over the body had
  -- not handled (#205): a stall after this reload is the reload's own
  M.thawPad()
  if RUN ~= nil then RUN.goUnhandled = nil end
  local req = {}
  local ref
  M.pendingStateReqs = M.pendingStateReqs + 1
  ref = rawAddMemoryCallback(function()
    if req.fired then return end
    req.fired = true
    M.pendingStateReqs = M.pendingStateReqs - 1
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

-- Resolve a savestate sidecar to its base64 payload.  compose.py embeds it
-- as OT6_STATES[basename], which is the only path; there is no loadfile()
-- fallback because loadfile raises under the sandbox.
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
      -- Savestate loads do not detach callbacks.  This call is a no-op once
      -- inputCbRef is set; it is kept so the input hook is live on paths
      -- that load before ever arming it.
      M.rearmInputInjection()
      -- Battery SRAM rides the savestate: emu.loadSavestate restores banks
      -- $30/$31.  Post-load SRAM, weakness codex included, is therefore a
      -- function of the fixture's own bytes.
      -- The first fixture a run loads is its BOOT POINT: the segment
      -- runner's replay starts the body again from here, and this is
      -- where an attempt's seed variation is idled in (M.bootMark).
      M.bootMark("fixture " .. tostring(M.lastState))
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
-- $7E3BF4: 4 x 16-bit party battle HP ($FFFF outside battle).
--
-- The formation record at $3F44: +$00 mold/bg1 bits, +$01 monsters present,
-- +$02..$07 six 8-bit monster ID low bytes, +$08..$0D six packed xxxxyyyy
-- positions, +$0E the six ID high bits.  IDs land at $3F46..$3F4B one byte
-- each, positions at $3F4C..$3F51, MSB mask at $3F52.
--
-- monstersPresent() counts the present mask ($3F45 low six bits), and
-- monsterIds() decodes the six ID bytes plus their MSBs.  For a monster's
-- SPECIES (0..383) prefer OT6_SPECIES ($57c0, M.formationSpecies): it is
-- full-width and carries off-stage loads too; these ID low bytes only tell
-- present slots apart.
M.MONSTER_IDS = 0x3F46          -- +$02..$07: six 8-bit ID low bytes
M.MONSTER_PRESENT = 0x3F45      -- +$01, low 6 bits: bit i set => slot i on stage
M.MONSTER_ID_MSB = 0x3F52       -- +$0E, --abcdef: bit (5-slot) is slot's ID high bit
M.BATTLE_HP = 0x3BF4

-- OT6 HUD tilemap shadow: 6 lines x stride 14 (+0 cur addr, +2 prev addr,
-- +4 five tilemap words).  This must track OT6_SHADOW in
-- ff6/src/battle/ot6.asm.  Read it from here rather than inlining it
-- elsewhere.
M.SHADOW = 0xECF1
M.SHADOW_STRIDE = 14
function M.shadowLine(line) return M.SHADOW + line * M.SHADOW_STRIDE end

-- Six entries, one per monster slot: the on-stage slots carry their decoded
-- ID (the low byte at $3F46+slot widened by that slot's MSB in $3F52), and
-- the empty slots read $FFFF.  Kept six-wide because every caller indexes
-- ids[1..6]; monstersPresent counts the mask directly.
function M.monsterIds()
  local mask = M.readByte(M.MONSTER_PRESENT) & 0x3F
  local msb = M.readByte(M.MONSTER_ID_MSB)
  local ids = {}
  for slot = 0, 5 do
    if (mask & (1 << slot)) ~= 0 then
      ids[slot + 1] = M.readByte(M.MONSTER_IDS + slot)
                    | (((msb >> (5 - slot)) & 1) << 8)
    else
      ids[slot + 1] = 0xFFFF
    end
  end
  return ids
end

-- How many monsters are on stage: popcount of the present mask's low six
-- bits ($3F45).
function M.monstersPresent()
  local mask = M.readByte(M.MONSTER_PRESENT) & 0x3F
  local n = 0
  while mask ~= 0 do
    n = n + (mask & 1)
    mask = mask >> 1
  end
  return n
end

function M.partyHp()
  local hp = {}
  for i = 0, 3 do hp[i + 1] = M.readWord(M.BATTLE_HP + i * 2) end
  return hp
end

-- The wipe verdict from one reading of the battle module's party table
-- (#166).  rows are the four battle slots in order, { actor, present, hp,
-- maxhp } each -- $3ed8+2e, $3aa0+2e bit 0, $3bf4+2e, $3c1c+2e -- and
-- flags is $3ebc.  The addresses and the reasoning sit on
-- M.partyWipedInBattle (ot6_field.lua), which reads them; this half is
-- the decision on its own, so battle_healpolicy can put the Veldt's and
-- the Narshe descent's measured bytes through it without an emulator.
--
-- A seat counts when its actor byte is not $ff AND its present bit is set:
-- a formation's hidden character AI (GAU on the Veldt, actor 11 at full
-- HP in seat 2 with the bit clear) is seated but not in the party, and the
-- engine's own alive mask leaves it out the same way.  A counted seat
-- whose actor byte is out of range or whose max HP is implausible says
-- another module owns these bytes right now: not a battle, not a wipe.
-- With at least one seat counted, LoseBattle's flag (bit 0) is the
-- engine's own verdict, and every counted HP word at 0 is the same verdict
-- read up to a couple of hundred frames earlier.
function M.wipeVerdict(rows, flags)
  local seated, alive = 0, 0
  for _, r in ipairs(rows) do
    if r.actor ~= 0xFF and r.present then
      if r.actor > 15 or r.maxhp == 0 or r.maxhp >= 10000 then return false end
      seated = seated + 1
      if r.hp > 0 then alive = alive + 1 end
    end
  end
  if seated == 0 then return false end
  if (flags & 0x01) ~= 0 then return true end
  return alive == 0
end

-- True once the battle module has begun loading.
--
-- $7E3BF4 is the party battle-HP table only while the battle module owns
-- that RAM; other modules write over the same bytes.  So this checks the
-- shape of the whole table rather than one slot: every word must be a
-- plausible current HP (0 for an empty or dead slot, else 1..9999) and at
-- least one character alive.  $FFFF/$FF00 anywhere means these bytes
-- belong to another module.
--
-- A total party wipe is all zeros, the same shape a menu leaves, so the
-- zeros alone say nothing; the seat table tells them apart (#205): actors
-- seated ($3ed8), present ($3aa0 bit 0) and a plausible max HP behind
-- each -- M.wipeVerdict's reading, the one the run canary has trusted
-- since #166.  Measured on locke_scenario (2026-09-16, a probe through a
-- field menu, a battle load and a solo loss): outside a battle the table
-- reads all $FFFF or all zero with the seat bytes $FF/0 and max HP
-- $FFFF/0; InitParty's frame seats the actor with max HP still 0 (which
-- the verdict rejects) and LoadCharProp writes the HP the next frame; and
-- from the one seat's HP hitting 0 until the field writes $FFFF back
-- (456 frames, LoseBattle's $3ebc bit 0 landing 281 in) the wipe shape
-- holds without a gap.  So a wipe reads as the battle still being up,
-- which it is: the engine sits on the Annihilated screen until a press,
-- and a driver keeps its frame() -- the [death] and [wipe] lines a solo
-- loss never got, and the A a person presses there.
function M.battleLoadStarted()
  local anyLive = false
  for i = 0, 3 do
    local hp = M.readWord(M.BATTLE_HP + i * 2)
    if hp >= 10000 then return false end   -- $FFFF, $FF00: not an HP table
    if hp > 0 then anyLive = true end
  end
  if anyLive then return true end
  return M.partyWipedInBattle ~= nil and M.partyWipedInBattle() or false
end

-- Cheap "is anything on screen" check: an all-black 256x224 screenshot
-- compresses to ~750 bytes, the battle-transition mosaic to ~2.3 KB, and a
-- real battle scene (bg + sprites + UI windows) to ~10 KB.  4000 separates
-- the transition from a real battle scene.
function M.screenLooksAlive()
  local ok, png = pcall(emu.takeScreenshot)
  return ok and type(png) == "string" and #png > 4000
end

-- True while a battle is fully up and rendering.  A crashed battle load
-- leaves the screen black and fails this check.  emu.getState() is not
-- used here: polling it is correlated with emulator crashes.
function M.battleActive()
  return M.battleLoadStarted() and M.monstersPresent() > 0 and M.screenLooksAlive()
end

-- --------------------------------------------- absorbed-weapon guard --
-- Fail the run when a character enters a fight holding a weapon whose
-- element something in the formation ABSORBS, because then every swing
-- heals the enemy.  Checks ABSORB only (not NULL): a null match is a
-- judgement call against the boss's break axis, weighed by class rather
-- than element, so it is left to a human rather than swapped
-- automatically.
--
-- monster_prop.dat: 32-byte records, +23 absorb, +24 null, +25 weak.
-- item_prop_en.dat: 30-byte records, +$00 type (&$07 == 1 is a weapon),
-- +$0F element.
M.ELEM_NAMES = { "fire", "ice", "bolt", "poison", "wind", "holy", "earth",
                 "water" }

-- Edgar's two damaging Tools, by item id, for callers of newFightDriver's
-- opts.tool.  AutoCrossbow is pierce-class and hits every enemy; the Bio
-- Blaster is element $08 poison and hits every enemy.
M.AUTOCROSSBOW = 0xAA
M.BIO_BLASTER = 0xA4

function M.elemStr(mask)
  local out = {}
  for i, n in ipairs(M.ELEM_NAMES) do
    if (mask >> (i - 1)) & 1 == 1 then out[#out + 1] = n end
  end
  return #out > 0 and table.concat(out, "|") or "-"
end

local ITEM_REC, ITEM_TYPE, ITEM_ELEM, ITEM_POWER = 30, 0x00, 0x0F, 0x14
-- a consumable's status cure masks: +21 status 1 (Fenix Down $F0 carries
-- DEAD $80 there), +22 status 2 (Remedy $F5 carries $48)
local ITEM_ST1, ITEM_ST2 = 0x15, 0x16
local MON_REC, MON_ABSORB = 32, 23

-- Item +$0F, but only for records the game itself calls a weapon: +$00's
-- low three bits are the type (1 = weapon) and $80 marks an unused record
-- (data-formats.md).  A shield in the left hand must not be read as one.
function M.weaponElement(item)
  if item == nil or item > 0xFF then return 0 end
  local base = (M.sym("ItemProp") & 0x3FFFFF) + item * ITEM_REC
  local t = M.readRomByte(base + ITEM_TYPE)
  if (t & 0x80) ~= 0 or (t & 0x07) ~= 1 then return 0 end
  return M.readRomByte(base + ITEM_ELEM)
end

-- Spell +$01, the element byte of magic_prop_en.dat's 14-byte record.
-- Boost folding moves a cast up its own family and families share one
-- element, so the base spell's byte answers for every tier it can fold to.
function M.spellElement(id)
  if id == nil or id > 0xFF then return 0 end
  return M.readRomByte((M.sym("MagicProp") & 0x3FFFFF) + id * 14 + 1)
end

-- Item +$14, the power byte.  For a consumable that is how much it heals.
-- It is the engine's input rather than its output, so a caller that can
-- watch a use land should prefer what it measures; newFightDriver uses
-- this as the prior and replaces it with the observed number.
function M.itemPower(item)
  if item == nil or item > 0xFF then return 0 end
  return M.readRomByte((M.sym("ItemProp") & 0x3FFFFF)
    + item * ITEM_REC + ITEM_POWER)
end

-- An item's status cure masks (ItemProp +21 / +22, the record shape
-- Fenix Down's DEAD $80 sits in).  Remedy $F5 reads $48 = SILENCE|SAP in
-- status 2, byte-identical to vanilla's record, so a Remedy never cured
-- Muddle (STATUS2 bit 5) -- battle_magicite measured two Remedies leave
-- muddled Edgar muddled (2026-09-07), and that is vanilla, not authored.
-- A plain physical hit clears it: CalcMaxDmg strips sleep and muddle from
-- a physically damaged target (battle_main.asm @0c45, `and $3ee5,y`),
-- which is what the fight driver's Muddle rule below does.
function M.itemStatus1(item)
  if item == nil or item > 0xFF then return 0 end
  return M.readRomByte((M.sym("ItemProp") & 0x3FFFFF) + item * ITEM_REC + ITEM_ST1)
end
function M.itemStatus2(item)
  if item == nil or item > 0xFF then return 0 end
  return M.readRomByte((M.sym("ItemProp") & 0x3FFFFF) + item * ITEM_REC + ITEM_ST2)
end
M.ST2_MUDDLE = 0x20                   -- STATUS2::CONFUSE, $3ee5 + entity*2

-- The Muddle rule (#170), as arithmetic on the four status bytes a person
-- reads off the muddle animation: a muddled actor never plans (the game
-- picks its command and target -- RandCharAction -- so a confirm here is
-- an AoE aimed wherever the engine re-aims it, and NUMBER 024's opening
-- Muddle turned Edgar's NoiseBlaster and Sabin's Fire Dance on their own
-- party), and a muddled LIVING ally gets a plain Fight before anything
-- else, because the hit is the cure.  Returns "defer" for the actor, the
-- ally's entity to hit, or nil.
--
--   actor    the deciding entity 0..3
--   status2  entity -> $3ee5 byte
--   hp       entity -> HP;  maxhp  entity -> max HP (0 for an empty slot)
function M.muddleRule(o)
  local st, hp, maxhp = o.status2 or {}, o.hp or {}, o.maxhp or {}
  if ((st[o.actor] or 0) & M.ST2_MUDDLE) ~= 0 then return "defer" end
  for e = 0, 3 do
    if e ~= o.actor and ((st[e] or 0) & M.ST2_MUDDLE) ~= 0
       and (hp[e] or 0) > 0 and (maxhp[e] or 1) > 0 then
      return e
    end
  end
  return nil
end

-- The turn-denying statuses (#187), read off the same four bytes the
-- Muddle rule reads.  Stop (STATUS3 bit 4, $3ef8): Ot6Gate holds the
-- gauge (battle_main.asm @08d5 `jsl Ot6Gate / bne` "return if target has
-- stop status or is broken"), so no window opens until $3af1's counter
-- runs out.  Sleep and Berserk (STATUS2 bits 7 and 4, $3ee5): the gauge
-- fills, but the ATB-full check @0941 (`peaflg STATUS12, {DEAD, PETRIFY,
-- ZOMBIE, SLEEP, CONFUSE, BERSERK} ... bcc CancelAction`) cancels the
-- menu and hands the turn to the engine -- a sleeper does nothing, a
-- berserker Fights whom RandCharAction picks.  Imp (STATUS1 bit 5, $3ee4)
-- is NOT one of them: an imp keeps its window with every command but
-- Fight, Item and Magic's Imp spell greyed (BattleCmdProp's IMP flag;
-- @1029 zeroes its battle power), so it is a cure question rather than a
-- planning one.  Measured 2026-09-16 (probe_statuses.lua, the world walk
-- off camp_escaped): Berserk landed on SHADOW as his window opened
-- ($7BCA=01 $7BC2=01 actor=1), the driver planned a Fight for him, and
-- the engine took the window away inside the pulse (the plan died as
-- actor_changed); his gauge then read $0097 with $3AA0=$29 for ~1400
-- frames while the engine's own Fights went out under his name.  The
-- driver treats these as arithmetic on the bytes: a denied actor is
-- never planned for, never pressed at, and never counted on to act.
M.ST1_IMP, M.ST2_BERSERK, M.ST2_SLEEP, M.ST3_STOP = 0x20, 0x10, 0x80, 0x10
--   s1, s2, s3   the entity's STATUS1/2/3 bytes
-- Returns the name of the status that denies the turn, or nil.
function M.turnDenied(o)
  if ((o.s3 or 0) & M.ST3_STOP) ~= 0 then return "Stop" end
  if ((o.s2 or 0) & M.ST2_SLEEP) ~= 0 then return "Sleep" end
  if ((o.s2 or 0) & M.ST2_BERSERK) ~= 0 then return "Berserk" end
  return nil
end
-- The cure in the bag for one status bit, from the ROM's own item
-- records (M.itemStatus1/2) rather than a table of beliefs: the first of
-- `items` that `has` says the bag holds and whose record carries the
-- bit.  The default order is Green Cherry ($F8: STATUS1 $20, Imp only)
-- then Remedy ($F5: STATUS1 $65 = Petrify|Imp|Poison|Blind, STATUS2 $48 =
-- Sap|Mute) -- the single-purpose item first, the field care's order.
-- Nothing in that pair carries Berserk's STATUS2 $10 (ROM read 2026-09-16,
-- build/ot6.sfc ItemProp), so Berserk's cure is "none in the bag" until
-- the ROM says otherwise; Sleep clears under any physical hit (CalcMaxDmg
-- @0c45 strips sleep and muddle) and Stop only with its counter.
--
--   byte   1 or 2, which status byte the bit lives in
--   bit    the status bit
--   has    function(item) -> true when the bag holds one to spend
--   items  the candidates in order (optional)
M.GREEN_CHERRY, M.REMEDY = 0xF8, 0xF5
function M.statusCure(o)
  for _, item in ipairs(o.items or { M.GREEN_CHERRY, M.REMEDY }) do
    local rec
    if o.byte == 2 then rec = M.itemStatus2(item) else rec = M.itemStatus1(item) end
    if (rec & o.bit) ~= 0 and o.has(item) then return item end
  end
  return nil
end

-- Ticks until an ATB gauge fills, from the two words the engine keeps per
-- entity: $3218,x is the 16-bit gauge it adds the constant $3ac8,x to on
-- every ATB tick (battle_main.asm _c211bb), read as FULL when its high
-- byte is 0 (`lda $3219,x / beq` "branch if atb gauge is full"; the
-- overflow does `stz $3219,x`; an empty gauge is set to $01).  The raise
-- rule compares these across entities, so the unit is the tick and the
-- absolute value is never needed.  nil for a gauge that cannot fill.
function M.atbEta(gauge, const)
  if ((gauge or 0) >> 8) == 0 then return 0 end
  if const == nil or const <= 0 then return nil end
  return math.ceil((0x10000 - gauge) / const)
end

-- What one enemy round costs a member between their turns (#206, #194),
-- priced from the engine's own clock rather than from a sum of past
-- worsts: the enemy actions that can land before the member's next turn,
-- each at the worst single action that enemy has measured.  Summing the
-- worst of each kind overpriced a solo soldier with one action a turn
-- (TekLaser 149 + Battle 113 = 262 against a 250 Potion, #206: LOCKE died
-- at 17 HP holding 3 BP); the largest loss seen underpriced two Tek
-- Lasers from two slots converging on EDGAR before his next turn (#194).
--
--   window   ATB ticks until the member's next turn (M.atbEta; for the
--            member acting now, a full refill of its gauge)
--   enemies  one per living monster: { slot, eta, period, worst } --
--            eta the ticks until its gauge fills (0 = full, nil = it
--            cannot fill), period the ticks a full refill takes (nil =
--            once at most), worst the largest single action it has landed
--            (on this member, else on anybody; nil = not measured)
--   fallback the per-action price for an enemy that acts in the window
--            with nothing measured (the largest single action any enemy
--            has landed this battle); nil = such an action adds nothing
--
-- A gauge that fills at or inside the window acts once, plus once per
-- full period that still fits.  Returns the cost, the enemy actions
-- counted, the arithmetic as a string, and the steady rate: what a
-- window-long round costs on average (each enemy's worst x window /
-- period), which is the price for a count of rounds rather than for the
-- next one (the finisher gate's "the rounds the kill still needs").
function M.roundCost(o)
  local window = o.window or 0
  local cost, actions, parts, rate = 0, 0, {}, 0
  local gauges = {}
  for _, en in ipairs(o.enemies or {}) do
    gauges[#gauges + 1] = string.format("s%d eta %s/%s", en.slot or -1,
      tostring(en.eta), tostring(en.period))
    local n = 0
    if en.eta ~= nil and window >= 0 and en.eta <= window then
      n = 1
      if en.period ~= nil and en.period > 0 then
        n = n + (window - en.eta) // en.period
      end
    end
    local each0 = en.worst or o.fallback
    if en.eta ~= nil and each0 ~= nil then
      if en.period ~= nil and en.period > 0 then
        rate = rate + each0 * window // en.period
      elseif n > 0 then
        rate = rate + each0
      end
    end
    if n > 0 then
      local each, how = en.worst, "worst"
      if each == nil then each, how = o.fallback, "unmeasured, at the battle's worst" end
      actions = actions + n
      if each ~= nil then
        cost = cost + n * each
        parts[#parts + 1] = string.format("s%d %dx%d (%s)", en.slot or -1, n, each, how)
      else
        parts[#parts + 1] = string.format("s%d %dx? (unmeasured)", en.slot or -1, n)
      end
    end
  end
  local why = string.format("%d enemy action(s) inside %d ticks%s [%s]", actions, window,
    #parts > 0 and (": " .. table.concat(parts, " + ")) or "", table.concat(gauges, ", "))
  return cost, actions, why, rate
end

-- Is a heal worth the turn it costs?  All of newFightDriver's heal policy,
-- kept out here as arithmetic on plain numbers so battle_healpolicy can put
-- the measured cases through it without an emulated fight.
--
--   hp, maxhp   the candidate's HP
--   restore     what the heal in hand actually gives back
--   roundCost   what one round takes off this candidate, measured in the
--               fight; 0 before the enemy has landed a round
--   allies      living party members other than the actor deciding
--   threshold   the top-up fraction, opts.healPercent
--   mp          true for a cast, which is paid in MP rather than out of the
--               bag; see the party clause below for the one thing it changes
--
-- Returns the reason to heal, or nil for "act instead".  If the heal
-- restores at least what a round costs, topping up below threshold or
-- covering danger is always worth it.  Otherwise: alone, healing never
-- outpaces the damage so the candidate acts instead; with allies present,
-- healing an endangered ally is worth the turn, and an `mp` heal (a cast,
-- not a bag item) also tops up below threshold since MP is not a fixed
-- supply the way bag items are.
function M.healDecision(o)
  local hp, maxhp = o.hp or 0, o.maxhp or 0
  local gain, cost = o.restore or 0, o.roundCost or 0
  if hp <= 0 or maxhp <= 0 then return nil end
  local pct = hp * 100 // maxhp
  local endangered = hp <= cost         -- one round could finish them
  if gain >= cost then
    -- healing outruns the damage, so topping up can be repeated for ever.
    -- Before the enemy has landed a round, cost is 0 and this is the whole
    -- rule.
    if pct < (o.threshold or 60) then return "top-up" end
    if endangered then return "in danger" end
    return nil
  end
  if (o.allies or 0) > 0 then
    if o.mp and pct < (o.threshold or 60) then return "top-up" end
    if endangered then return "covering an ally" end
  end
  return nil
end

-- What one action is expected to deal, for the press rule's "kill this
-- turn" test (#165), from numbers a person reads off the screen: the
-- per-hit damage this actor's last action landed (shielded-equivalent,
-- the damage watch's figure), how many hits the action makes, how many of
-- them chip, and how many shields stand.  The hits up to the break land
-- shielded; every hit past it lands broken, x4 shielded (Ot6ShieldedDmg
-- x0.5 then Ot6BrokenDmg x2).  A gauge already broken (need 0) puts every
-- hit in the window.  Returns the expected damage and the hit split, or
-- nil when the action cannot break (chips < need) or nothing has been
-- measured (per nil / 0).  Plain arithmetic, so battle_healpolicy can put
-- the Rizopas numbers through it without an emulator.
--
--   per     shielded-equivalent damage per landed hit, measured
--   hits    hits the action makes (M.fightSwings' sum; a tool's count)
--   chips   of those, how many chip (the chip model's count)
--   need    shields left to break; 0 when already broken
function M.killEstimate(o)
  local per, hits, chips, need = o.per or 0, o.hits or 0, o.chips or 0, o.need or 0
  if per <= 0 or hits <= 0 then return nil end
  if chips < need then return nil end
  -- hits until the last chip lands: with every hit chipping that is
  -- `need`; with only some (a Genji off-hand on the wrong class) the
  -- chipping hits are spread through the volley, so round up
  local toBreak = need == 0 and 0 or math.ceil(need * hits / chips)
  if toBreak > hits then return nil end
  local broken = hits - toBreak
  return per * toBreak + per * 4 * broken, toBreak, broken
end

-- Whether a raise is worth the Fenix Down (#165, refined by #168): the HP
-- it gives back against the smallest hit the living enemy has landed this
-- fight.  Fenix Down (item $F0: ItemProp +19 bit 7 "fraction of max HP",
-- +20 power 2; CalcDmgRatio -> CalcRatio: max HP * power >> 4) raises to
-- maxhp/8 -- CYAN's 358 -> 44, measured.  A hit at least that big lands
-- the member back at 0 before anyone can top them up: the item is spent
-- for nothing.  With no hit measured yet the raise stands.
--
-- The first cut refused on the hit alone, and against any enemy whose
-- smallest hit exceeds maxhp/8 -- most bosses at these levels -- it never
-- opened: battle 70 shipped SABIN dead through eight turns of a won fight
-- (63-HP raise, 68 hit).  So the re-kill is only a refusal when BOTH
-- outs are closed:
--   (a) nobody can top the raise up first: `topUpFirst` is whether another
--       party member's gauge fills before the lethal monster's (the ATB
--       read, M.atbEta), and `topUp` what their Potion gives; a raise
--       followed by that Potion is care, and the pair has to lift the
--       member clear of the hit (map 269: 55 + 250 = 305 under a 447
--       one-shot is still no raise, #171);
--   (b) no kill is in reach: `killInReach` is the last monster's HP
--       inside the party's measured window (the #156/#165 estimate); a
--       late raise in a fight being won costs nothing and means nobody
--       walks out dead.
--
--   maxhp        the fallen member's max HP
--   power        the item's power byte (M.itemPower; 2 for Fenix Down)
--   smallestHit  the living enemy's smallest observed hit, or nil
--   killInReach  (b) above, boolean
--   topUpFirst   (a) above, boolean;  topUp  the HP that top-up gives
--
-- Returns the raise HP, true to raise / false to refuse, and the reason.
function M.raiseDecision(o)
  local maxhp, power = o.maxhp or 0, o.power or 2
  local raiseHp = (maxhp * power) >> 4
  if raiseHp <= 0 then return raiseHp, false, "nothing to raise to" end
  local hit = o.smallestHit
  if hit == nil then return raiseHp, true, "no enemy hit measured yet" end
  if hit < raiseHp then
    return raiseHp, true, string.format("%d HP survives the smallest hit, %d", raiseHp, hit)
  end
  if o.killInReach then
    return raiseHp, true, string.format("%d HP would not survive the %d hit, but a "
      .. "kill is in reach: the raise is free", raiseHp, hit)
  end
  local topUp = o.topUp or 0
  if o.topUpFirst and raiseHp + topUp > hit then
    return raiseHp, true, string.format("%d HP alone would not survive the %d hit, "
      .. "but an ally tops up first: %d + %d = %d does", raiseHp, hit, raiseHp,
      topUp, raiseHp + topUp)
  end
  if o.topUpFirst then
    return raiseHp, false, string.format("%d HP, and even an ally's top-up first "
      .. "(%d + %d = %d) does not survive the %d hit", raiseHp, raiseHp, topUp,
      raiseHp + topUp, hit)
  end
  return raiseHp, false, string.format("%d HP does not survive the %d hit, no kill "
    .. "is in reach, and the enemy acts before anyone can top up", raiseHp, hit)
end

-- The keyed line's boost (#174): boost-Fight through randoms is the
-- default (half damage unbroken plus the swings a pip adds restores
-- vanilla kill speed), but where a member holds a key the formation's
-- shield row answers to -- a class the weapon or blitz matches, an
-- element it carries, read off the HUD's revealed cells -- the keyed
-- line goes first, and unboosted where it chips: pips spent into a
-- standing gauge buy half-damage swings, and the break is what the turn
-- is for.  So the boost is the SMALLEST that chips the gauge to zero
-- this turn (0 when the unboosted line already does: SABIN's Pummel is
-- two bludgeoning hits into Trapper's two shields; LOCKE's ThunderBlade
-- needs one pip for the second bolt swing), never more than the bank
-- allows, and all the bank allows when no boost within it reaches the
-- break (the surplus swings then land broken, x4).  Measured on the
-- map-269 trio: the keyed tactical line ends the fight in 3355 frames
-- against boost-Fight's 8515, 4/15 double kills against 7/15.
--
--   need     shields standing on the target (0 = broken: not this rule's turn)
--   chipsAt  chips the actor's best line lands at each boost 0..bank
--   bank     the most the bank lets this actor spend now
--
-- Returns the boost to use and the reason, or nil when no key is held
-- (nothing chips at 0 BP -- more swings of the same hands chip nothing)
-- or the gauge is already broken.
function M.keyBoost(o)
  local need, chipsAt, bank = o.need or 0, o.chipsAt or {}, o.bank or 0
  if need <= 0 then return nil, "the gauge is broken: the unload's turn, not the key's" end
  if (chipsAt[0] or 0) <= 0 then return nil, "no key held: nothing chips at 0 BP" end
  for b = 0, bank do
    if (chipsAt[b] or 0) >= need then
      return b, string.format("%d BP lands %d chip(s) on %d shield(s): the smallest "
        .. "boost that breaks this turn", b, chipsAt[b], need)
    end
  end
  return bank, string.format("no boost within the bank (%d) reaches %d shield(s); "
    .. "%d BP lands %d chip(s), the most the bank allows", bank, need, bank,
    chipsAt[bank] or 0)
end

-- Spend it before you die (#175): a member inside one round of death who
-- holds banked BP, and whom no heal in hand lifts clear of that round,
-- spends the pips now on their strongest line rather than take a heal
-- that only delays -- "a dead party with a bunch of unused boost pips
-- means we've not used the abilities of the characters to their fullest
-- extent."  Plain arithmetic so battle_healpolicy can put the Rizopas
-- and Nerapa numbers through it.
--
--   hp, maxhp   the member's HP
--   roundCost   what one enemy round takes off them, measured (0 = none yet)
--   bp          the pips they hold
--   heals       the heals on offer to them, each { what, restore } with
--               restore nil for a cast not yet measured this battle
--
-- Returns "spend" with the reason, or nil with why not: not inside a
-- round of death, no pips, or a heal that saves (hp + restore > cost);
-- an unmeasured cast is let through to be measured -- the driver's own
-- rule for a first cast -- since it may be the saving one.  The
-- kill-press keeps its priority above this (the caller asks it first).
function M.spendDecision(o)
  local hp, cost, bp = o.hp or 0, o.roundCost or 0, o.bp or 0
  if hp <= 0 or cost <= 0 or hp > cost then
    return nil, string.format("%d HP is not inside one round of death (%d)", hp, cost)
  end
  if bp < 1 then return nil, "no BP banked" end
  for _, h in ipairs(o.heals or {}) do
    if h.restore == nil then
      return nil, string.format("%s is not yet measured; it may save (measure it)", h.what)
    end
    if hp + h.restore > cost then
      return nil, string.format("%s saves: %d + %d = %d survives the %d round",
        h.what, hp, h.restore, hp + h.restore, cost)
    end
  end
  local tried = {}
  for _, h in ipairs(o.heals or {}) do
    tried[#tried + 1] = string.format("%s +%d = %d", h.what, h.restore, hp + h.restore)
  end
  return "spend", string.format("%d/%d is inside one round of death (%d) holding %d BP, "
    .. "and no heal saves it (%s)", hp, o.maxhp or 0, cost, bp,
    #tried > 0 and table.concat(tried, ", ") or "nothing to heal with")
end

-- How a wipe reads (#175), from its [death] records -- each { tick, from,
-- maxhp, bp, oneAction }.  The owner's two shapes: "it's totally normal to
-- sometimes be wiped with a one shot attack early in a battle -- that
-- means you're just under level and need more HP.  But when a party is
-- wiped with 3-4 pips each, it means we weren't trying our best."  So a
-- wipe is "one-shot early" when some member was killed by one action
-- from at least onePct of max HP inside the first `early` ticks, and
-- "died with BP banked" when some member fell holding at least `banked`
-- pips; both can hold, and neither is "no deaths recorded".  Returns the
-- class string the [wipe] line and tools/audit_boost.py print.
function M.wipeClass(deaths, o)
  o = o or {}
  local onePct, early, banked = o.onePct or 80, o.early or 1800, o.banked or 3
  local oneShot, held = false, 0
  for _, d in ipairs(deaths or {}) do
    if d.oneAction and d.tick <= early and (d.maxhp or 0) > 0
       and (d.from or 0) * 100 // d.maxhp >= onePct then
      oneShot = true
    end
    if (d.bp or 0) >= banked then held = math.max(held, d.bp) end
  end
  if #(deaths or {}) == 0 then return "no deaths recorded" end
  local parts = {}
  if oneShot then parts[#parts + 1] = "one-shot early" end
  if held > 0 then parts[#parts + 1] = string.format("died with %d BP banked", held) end
  if #parts == 0 then return "worn down (no one-shot, no pips banked)" end
  return table.concat(parts, " + ")
end

-- Which way the target cursor crosses, read off the battle rather than
-- assumed.  $201F is the type of battle the engine set at InitBattle
-- (battle-ram.txt:423, battle_main.asm:7820: 0 normal, 1 back, 2 pincer,
-- 3 side) and $7ACE is the target group the cursor sits in.  btlgfx's own
-- jump tables are one entry per type (btlgfx_main.asm, "move character
-- target left/right jump table (1 per battle type)"):
--
--   normal  chars: LEFT crosses (_c174bf), RIGHT is an rts -- nothing
--           mons:  RIGHT crosses back (_c175a3)
--   back    chars: RIGHT crosses (_c17439), LEFT is an rts -- nothing
--           mons:  LEFT crosses back (_c17669)
--   pincer  chars: both cross, to the left group (_c174bf) or the right
--           (_c17439); monsters stand on both sides
--   side    chars: LEFT unless the cursor is already the left character
--           group ($7ACE = 1, _c174ea returns), RIGHT unless it is the
--           rightmost ($7ACE = 3, _c17463 returns)
--
-- A back attack was what the J39-row fight drew on the dadaluma_entry
-- attempt (#176): the steer pressed LEFT from the party side, LEFT is
-- the rts, and the party idled in target select until the clock ran out.
--
-- Returns the layout: its type and name, the group read, and the
-- directions that cross toward the monsters and back to the party, best
-- first.  `o` overrides the reads for tests.
M.BATTLE_TYPES = { [0] = "normal", [1] = "back attack", [2] = "pincer",
                   [3] = "side attack" }
function M.battleLayout(o)
  o = o or {}
  local t = o.type or M.readByte(0x201F)
  local group = o.group or M.readByte(0x7ACE)
  -- The preemptive strike (#186): battle_main.asm @2eb5..@2ec0 `jsr Rand /
  -- cmp $ee / bcs / lda #$40 / tsb $b0` on a 1/8 roll (doubled by the Gale
  -- Hairpin, suppressed by $2F4B bit 2), which opens the party's gauges
  -- full and the monsters' empty
  -- -- a free round.  Read live with the type; a test passing `type`
  -- supplies it (default false) rather than reading the emulator.
  local pre
  if o.type ~= nil then pre = o.preemptive or false
  else pre = (M.readByte(0x00B0) & 0x40) ~= 0 end
  local L = { type = t, group = group, name = M.BATTLE_TYPES[t] or "unknown",
              preemptive = pre }
  if t == 0 then
    L.toMonsters, L.toChars = { "left" }, { "right" }
    L.where = "the monsters stand left of the party"
  elseif t == 1 then
    L.toMonsters, L.toChars = { "right" }, { "left" }
    L.where = "the monsters stand RIGHT of the party (back attack)"
  elseif t == 2 then
    L.toMonsters, L.toChars = { "left", "right" }, { "right", "left" }
    L.where = "the monsters stand on both sides (pincer)"
  elseif t == 3 then
    if group == 1 then
      L.toMonsters, L.toChars = { "right" }, { "left" }
    elseif group == 3 then
      L.toMonsters, L.toChars = { "left" }, { "right" }
    else
      L.toMonsters, L.toChars = { "right", "left" }, { "left", "right" }
    end
    L.where = "the party is split around the monsters (side attack)"
  else
    -- a type this table does not know: say so and offer both, rather than
    -- press one of them as if it were read
    L.toMonsters, L.toChars = { "left", "right" }, { "right", "left" }
    L.where = string.format("UNKNOWN battle type $%02X -- the crossing "
      .. "direction is not read, only guessed", t)
  end
  return L
end

function M.monsterAbsorb(species)
  return M.readRomByte((M.sym("MonsterProp") & 0x3FFFFF)
    + species * MON_REC + MON_ABSORB)
end
-- monster_prop +24, the elements the species NULLS: a cast of one of them
-- lands for 0.  The spell guards read it (a wasted turn); the weapon guard
-- above deliberately does not (see its header).
function M.monsterNull(species)
  return M.readRomByte((M.sym("MonsterProp") & 0x3FFFFF)
    + species * MON_REC + MON_ABSORB + 1)
end

-- The cast guards' decision (#99, #156, #172), with the stage handed in
-- so battle_healpolicy can put battle 70's bytes through it without an
-- emulator.  elem is the ability's element mask (0 for none),
-- reflectable its magic_prop reflect bit, and slots the monsters ON
-- STAGE -- alive and present -- each { slot, species, absorb, null,
-- reflect } read from the slot's live record (the fight driver's
-- stageSlots).  Returns the offending slot and why: "absorb" (any element
-- of the cast is drunk: a heal for the enemy), "reflect" (a reflectable
-- cast at a Reflect bearer lands on the party), or "null" (every element
-- of the cast is nulled: a wasted turn).  Absorb is judged across the
-- whole stage first, since it is the costliest.  nil when the cast may go.
function M.castVeto(elem, reflectable, slots)
  if elem ~= 0 then
    for _, s in ipairs(slots) do
      if (s.absorb & elem) ~= 0 then return s, "absorb" end
    end
  end
  for _, s in ipairs(slots) do
    if reflectable and s.reflect then return s, "reflect" end
    if elem ~= 0 and (s.null & elem) == elem then return s, "null" end
  end
  return nil
end

-- Spell +$03, attack flags 1 (battle-ram.txt $11A3); bit 1 is "ignore
-- reflect".  Clear on every attack spell the driver casts (Fire/Ice/Bolt
-- at every tier, Pearl, Flare: a Reflect-bearing target bounces them);
-- set on every esper, lore, blitz and tool.  Families share the byte, so
-- the base spell answers for every tier a boost folds it to.
function M.spellReflectable(id)
  if id == nil or id > 0xFF then return false end
  return (M.readRomByte((M.sym("MagicProp") & 0x3FFFFF) + id * 14 + 3)
          & 0x02) == 0
end

-- Item +$00 says weapon (type 1, record in use) -- weaponElement's own
-- test, exposed for the hand model below.
function M.isWeapon(item)
  if item == nil or item > 0xFF then return false end
  local t = M.readRomByte((M.sym("ItemProp") & 0x3FFFFF)
    + item * ITEM_REC + ITEM_TYPE)
  return (t & 0x80) == 0 and (t & 0x07) == 1
end

-- The class a Fight or Tools hit carries: Ot6WeapClassTbl[item]
-- (ot6_class.asm, one byte per item id, tools included; an empty hand
-- $FF is a bludgeoning fist).  Bit 7 is the null-break property, a hit
-- that chips nothing, so it reads as no class here.
function M.weaponClass(item)
  if item == nil or item > 0xFF then return 0 end
  local c = M.readRomByte((M.sym("Ot6WeapClassTbl") & 0x3FFFFF) + item)
  if (c & 0x80) ~= 0 then return 0 end
  return c & 0x0F
end

-- Swings a boosted Fight makes, (main hand, off hand): one per armed hand,
-- plus two per BP (Ot6FightBoost adds 2*BP to $3a70, ot6_boost.asm), and
-- with a weapon in each hand (a Genji Glove pair) the swings alternate
-- hands, so each hand gets half.  Plain arithmetic, kept out of the
-- driver so a test can check it without an emulator.
function M.fightSwings(twoWeapons, boost)
  if twoWeapons then return 1 + boost, 1 + boost end
  return 1 + 2 * boost, 0
end

-- Both hands of every party member, as { char = c, hand = "R"|"L",
-- item = id }.  The left hand is usually a shield and weaponElement()
-- returns 0 for one, but a Genji Glove really does put a second weapon
-- there, so both slots are read.  $1600 + 37*c + $1F/$20, the same record
-- audit_equipment.py and the equipment audits read.
function M.partyWeapons()
  local out = {}
  for c = 0, 15 do
    if (M.readByte(0x1850 + c) & 0x07) ~= 0 then
      for i, hand in ipairs({ "R", "L" }) do
        local item = M.readByte(0x1600 + 37 * c + 0x1E + i)
        if item ~= 0xFF then
          out[#out + 1] = { char = c, hand = hand, item = item }
        end
      end
    end
  end
  return out
end

-- The formation's species, from OT6's own per-slot stash (OT6_SPECIES,
-- $57c0, six words) rather than from vanilla's $3F46: OT6_SPECIES is
-- full-width (0..383) and carries a monster that is loaded but not on
-- stage, where $3F46 is only six bytes.
--
-- Which slots are real comes from the formation's occupied-slot mask: the
-- low six bits of $3F45.
--
-- OT6_SPECIES is not cleared between battles, so without the mask a short
-- formation would be checked against the tail of the previous one.
-- Formation 504 is legitimately empty, so a zero mask is "nothing to
-- check" rather than an error.
M.FORMATION_MASK = 0x3F45
function M.formationSpecies()
  local mask = M.readByte(M.FORMATION_MASK) & 0x3F
  local out = {}
  for slot = 0, 5 do
    if (mask >> slot) & 1 == 1 then
      out[#out + 1] = { slot = slot, species = M.readWord(M.FORMATION + slot * 2) }
    end
  end
  return out
end

-- The decision, with both inputs handed in, so a test can put a known
-- clash through the same ROM reads and the same masks that the live guard
-- uses.  Without that a green guard and a guard that never ran look the
-- same.
function M.absorbClashesFor(weapons, species)
  local out = {}
  for _, w in ipairs(weapons) do
    local elem = M.weaponElement(w.item)
    if elem ~= 0 then
      for _, s in ipairs(species) do
        local hit = M.monsterAbsorb(s.species) & elem
        if hit ~= 0 then
          out[#out + 1] = { char = w.char, hand = w.hand, item = w.item,
                            elem = elem, slot = s.slot,
                            species = s.species, absorbed = hit }
        end
      end
    end
  end
  return out
end

function M.clashStr(c)
  return string.format(
    "char %d's %s-hand item $%02X (%s) is ABSORBED by slot %d species $%04X",
    c.char, c.hand, c.item, M.elemStr(c.absorbed), c.slot, c.species)
end

function M.absorbClashes()
  return M.absorbClashesFor(M.partyWeapons(), M.formationSpecies())
end

-- Random encounters are excluded.  OT6_RANDBTL ($57bd) is a normalized
-- 0/1 flag latched in Ot6InitBP from the field trigger's marker and then
-- cleared, so an event battle always reads 0.  A clash in a random
-- encounter is logged instead of failing the run.
M.RANDBTL = 0x57BD

-- How long after M.battleLoadStarted() turns true before the formation is
-- read.  The gate watches the party HP table, which the battle module
-- fills near the end of its setup, so the species stash and the slot mask
-- are already written; the wait is slack, not a measured requirement.
local GUARD_SETTLE = 30
-- and how long it may keep reading nonsense before that becomes the
-- finding.  Ten seconds: far past any battle's setup, far short of the
-- shortest fight.
local GUARD_UNREADABLE = 600

M.absorbGuardBattles = 0        -- battles inspected; the positive control
M.absorbGuardClashes = 0
local guardArmed, guardSettle = true, 0

-- Returns an error message, or nil.  M.run calls this once per battle and
-- routes a message through its own FAIL path.
function M.absorbGuardTick()
  if not M.battleLoadStarted() then
    guardArmed, guardSettle = true, 0
    return nil
  end
  if not guardArmed then return nil end
  guardSettle = guardSettle + 1
  if guardSettle < GUARD_SETTLE then return nil end

  -- A species outside 0..383 means the slot mask and the species stash
  -- are not both filled yet.  Keep waiting rather than failing a run on a
  -- transient; if it never resolves, fail, because a guard that cannot
  -- read its data must not report the same green as one that read it and
  -- found nothing.
  local species = M.formationSpecies()
  local unreadable
  for _, s in ipairs(species) do
    if s.species >= 384 then unreadable = s end
  end
  if unreadable then
    if guardSettle < GUARD_UNREADABLE then return nil end
    guardArmed = false
    return string.format("absorb guard: %d frames into this battle slot %d "
      .. "of the formation still reads species $%04X, which is not a monster "
      .. "record (0..383), so the guard cannot say whether this fight "
      .. "absorbs anything.  $57c0 is written per entity by Ot6SeedShields "
      .. "and $3F45's low six bits say which slots are real; one of the two "
      .. "is not what this code thinks it is.",
      guardSettle, unreadable.slot, unreadable.species)
  end

  guardArmed = false
  M.absorbGuardBattles = M.absorbGuardBattles + 1
  local clashes = M.absorbClashesFor(M.partyWeapons(), species)
  M.absorbGuardClashes = M.absorbGuardClashes + #clashes
  if #clashes == 0 then return nil end

  local lines = {}
  for _, c in ipairs(clashes) do lines[#lines + 1] = "  " .. M.clashStr(c) end
  local body = table.concat(lines, "\n")

  if M.readByte(M.RANDBTL) ~= 0 then
    M.log("absorb guard: RANDOM encounter, not failed on:\n" .. body)
    return nil
  end
  return "absorb guard: someone entered this fight holding a weapon the "
    .. "formation ABSORBS, so every swing HEALS it:\n" .. body
    .. "\nThis is the Cranes bug (issue #81).  Pick the weapon deliberately "
    .. "for this fight with H.equipWeapon -- weigh class against the boss's "
    .. "break axis first and element second -- rather than leaving "
    .. "the game's power-greedy Optimum pick in place."
end

-- ------------------------------------------------------- the step runner --
-- A step is a table { tick = function(self) return "frame"|"done" end }.
-- "frame" = consumed this frame, call again next frame; "done" = advance.
-- Steps are built fresh per run; constructors below close over their state.
--
-- The reset protocol (#196).  A step may also carry
-- reset = function(self), which puts it back to the state it was built in.
-- repeatN calls its body's reset after every pass, driveUntil after every
-- body cycle, and seqStep forwards a reset to every child that has one --
-- so a step without a reset runs once, and every later pass finds it
-- already "done" (measured: battle_steal's three attempts scored one
-- steal three times; tools/tests/step_reset.lua pins the shapes).  Every
-- constructor here with closure state has one; a constructor elsewhere
-- (a navigator, a shop drive) names its own state through M.withReset.
-- What a TEST's own closures hold is the test's to clear, in the body's
-- first H.call.

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
-- byte.  Catches battle/effect art clobbering our claimed font cells; the
-- expected bytes come from the ROM itself, so glyph art edits never stale
-- the canary.
function M.glyphCanary()
  local vr, rom = emu.memType.snesVideoRam, emu.memType.snesPrgRom
  local function findSig(sig)
    -- scan the whole OT6 slice of bank F0
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
        -- A long wait is a step that MEANS to sit still; tell the
        -- no-progress watchdog so it does not read a declared pause as a
        -- hang (the segment runner, bottom of this file).
        if c == 0 and n >= 240 then M.watchQuiet(n + 120) end
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
-- A wait that runs out says "timeout after 600 frames waiting for main
-- menu", which often omits the real cause: the savestate may have been
-- generated against a different ROM than the one running, so the first
-- step needing a specific frame lands on a frame the fixture's timing no
-- longer has.  So every timeout appends what the run knows: which fixture
-- it booted, and whether composition already flagged that fixture as
-- generated from sources this tree no longer has (OT6_STALE, emitted by
-- lib/compose.py).
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
-- "Reached" means each fresh pass: reset() clears the choice so a replayed
-- cond (inside a driveUntil body) re-asks its predicate, and resets the
-- branch it had taken, so that branch's steps start over too (#196: the
-- branch's seqStep was rebuilt over the SAME child objects, which kept
-- their state -- a driveUntil under a cond under a repeatN ran on its
-- earlier passes' frame count).  Top-level steps tick once and are never
-- reset, so their behavior is unaffected.  The library's own list fold,
-- cond(function() return true end, steps), rides on this.
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
      if chosen then chosen:reset() end
      chosen = nil
    end,
  }
end

-- Repeat a step list n times.  Its own reset clears the pass count and
-- resets the body, so a repeatN(1, ...) fold nested in a replayed body
-- (a driveUntil's, or an outer repeatN's) runs on every pass rather than
-- reporting itself done after its first (#196).
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
    reset = function()
      done = 0
      body:reset()
    end,
  }
end

-- Run the body steps in a loop until pred() is truthy.  Raises after
-- maxFrames.  Completion releases the pad: pred can fire mid-body-cycle,
-- abandoning the body wherever it stands, and a button it was holding at
-- that instant must not stay held into the steps that follow (a stuck
-- d-pad auto-repeats the battle-menu cursor and a stuck A confirms into
-- target selection).
--
-- Its reset clears the frame count -- so a drive repeated by repeatN gets
-- its whole cap on every pass, not what the earlier passes left of it --
-- and resets the body, which pred may have abandoned mid-cycle (#196:
-- measured, a pass that began inside the body's waitFrames never ran the
-- body's first step again).
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
    reset = function()
      waited = 0
      body:reset()
    end,
  }
end

-- Chain a reset onto a step.  A constructor whose closures hold state its
-- children cannot clear (a navigator's plan and walk budget, a shop
-- drive's "bought" latch, an order screen's "done") names that state
-- here, and the step's existing reset (the driveUntil's, the cond's)
-- still runs first.  fn takes no arguments; it closes over the state.
function M.withReset(step, fn)
  local inner = step.reset
  step.reset = function(self)
    if inner then inner(self) end
    fn()
  end
  return step
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
-- Deliberately option-free: the constants are part of each test's
-- frame/RNG landing, since a different hold or wait changes which frame
-- the encounter fires on.  A test that needs a different entry keeps
-- writing its own drive.
--
-- In Wait mode a bystander's open command window FREEZES the battle
-- clock, so a queued action never reaches the top of the queue and the
-- test hangs.  flushMenus drives until the menu byte reads closed,
-- pulsing A with the shared list-cursor block ($895F..$896A) zeroed, so
-- every bystander takes row 0 and can never fire a second real action.
--   H.flushMenus()                    -- plain flush
--   H.flushMenus{ pin = fn }          -- fn runs every tick (fixture pins)
--   H.flushMenus{ maxFrames = n }     -- cap (default 1800; timeout raises)
function M.flushMenus(opts)
  opts = opts or {}
  local t = 0
  return M.driveUntil(function()
    return M.readByte(0x7BCA) == 0
  end, opts.maxFrames or 1800, {
    M.call(function()
      t = t + 1
      if opts.pin then opts.pin() end
      if M.readByte(0x7BCA) == 0 then M.setPad({}); return end
      for a = 0x895F, 0x896A do M.writeByte(a, 0) end
      M.setPad(t % 8 < 4 and { a = true } or {})
    end),
  }, "flush menus (#72)")
end

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
-- A battle's whole RNG stream hangs off one byte, seeded once at battle
-- init (InitBattle):
--
--     lda     $021e       ; low byte of game time (frames)
--     asl2
--     sta     $be         ; set random number seed
--
-- $021e is wGameTimeFrames, ticked 1..60 and wrapped once per vblank by the
-- field, world, battle and menu NMIs.  A is 8-bit at the store, so the seed
-- is (frames * 4) & $FF: 60 values, one per phase.  $be then indexes
-- RNGTbl (256 bytes), which every battle Rand/RandA/RandCarry walks.
--
-- newSeedLadder spaces attempts by holding until $021e has advanced to
-- each attempt's own target phase (as widely as 60 phases allow), rather
-- than by a fixed frame count, and reads the seed each attempt actually
-- drew off the store instruction, requiring it be distinct.  A ladder that
-- plays one fight twice fails the run instead of passing silently.
--
-- The hold counts $021e's own movement rather than waiting for it to equal
-- the target value, because $021e is ticked at the end of the owning
-- module's vblank handler, which can finish just inside a sampled frame or
-- just past it -- so an equality wait can miss a target phase every time it
-- is written and overwritten within the same sampled frame.  Summing
-- movement instead lands on the target when it is visible and one or two
-- phases past it otherwise, which the spacing below tolerates.
--
-- Spacing is as wide as the 60-phase cycle allows (not merely nonzero)
-- because $be indexes into the shared 256-byte RNGTbl: attempts one phase
-- apart share nearly all their draws, so distinct AND distant seeds are
-- what make attempts diverge early into genuinely different fights.

M.SEED_PHASE = 0x021E                   -- wGameTimeFrames
M.SEED_PERIOD = 60                      -- IncGameTime's 1..60 cycle

-- The live phase, and the seed a battle initialising right now would draw.
function M.seedPhase() return M.readByte(M.SEED_PHASE) end
function M.seedOf(phase) return (phase * 4) & 0xFF end

-- Address of the `sta $be` store, found by its bytes rather than a fixed
-- address: AD 1E 02 (lda abs $021e), 0A 0A (asl a, asl a), 85 BE (sta dp
-- $be), scanned forward from InitBattle.  Requiring exactly one match makes
-- a moved or rewritten seeder an error rather than a silent miss.
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

-- A varied-seed robustness helper, not a restriction on all testing.
-- docs/TESTING.md explicitly permits identical-state/seed replay for A/B
-- comparisons and local debugging. Use snapshot restoration directly for
-- those experiments; this helper intentionally checks seed diversity.
--
--   local L = H.newSeedLadder("battle 70")
--   H.run({...}, {
--     ...
--     L.watch(),                  -- once, before the first attempt
--     attempt(1), attempt(2), attempt(3),
--     L.report(),                 -- once, after the last
--   })
--
-- and inside attempt(n):
--
--     L.spread(n),
--
-- spread(n) latches attempt 1's phase and then holds each later attempt
-- until $021e has advanced to base + 20*(n-1), the widest even spacing
-- three attempts fit into the 60-phase cycle.  The seed each attempt
-- actually drew is captured at the store and checked by report(): distinct
-- across attempts, and present for every attempt that ran.
--
-- opts.attempts (default 3) only sets the spacing; it is not a licence to
-- widen the ladder.
--
-- opts.phaseSource replaces the live read of $021e, for callers that need
-- to drive the hold with a synthetic sampler instead of the counter.
function M.newSeedLadder(tag, opts)
  opts = opts or {}
  local attempts = opts.attempts or 3
  local gap = opts.gap or (M.SEED_PERIOD // attempts)
  local phaseOf = opts.phaseSource or M.seedPhase
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

  -- The spread, derived from the counter the seed is made of.
  -- sopts.forcePhase pins the target outright, for tests that want to force
  -- a specific (or colliding) phase; a generator does not pass it.
  L.spread = function(n, sopts)
    sopts = sopts or {}
    local target = nil
    return seqStep({
      M.call(function()
        assert(watching, L.tag .. ": L.watch() must run before L.spread()")
        cur = n
        L.spreads[n] = true     -- this attempt now owes report() a seed
        L.seeds[n] = nil        -- and it is the first fight after THIS spread
        local now = phaseOf()
        local forced = sopts.forcePhase
        if type(forced) == "function" then forced = forced() end
        if n == 1 and not forced then base = now end
        assert(base, L.tag .. ": spread(1) must run before spread(" .. n .. ")")
        target = forced or (((base - 1) + gap * (n - 1)) % M.SEED_PERIOD) + 1
        L.targets[n] = target
        M.log(string.format("[%s] attempt %d: phase %d -> target %d "
          .. "(seed $%02X), base %d gap %d%s",
          L.tag, n, now, target, M.seedOf(target), base, gap,
          forced and "  [forcePhase -- a control, not a route]" or ""))
      end),
      -- Not M.waitUntil: `target` is only known once the step above has run.
      -- Sums the counter's own movement rather than testing equality against
      -- the sampled phase, and releases once it has moved as far as the
      -- target was away (see the note above this function).  The budget is
      -- three cycles of the 60-phase period; running out means the counter
      -- is stopped or crawling.
      (function()
        local waited, moved, need, prev, still = 0, 0, nil, nil, 0
        return {
          tick = function()
            local now = phaseOf()
            if need == nil then
              need, prev = (target - now) % M.SEED_PERIOD, now
            else
              local step = (now - prev) % M.SEED_PERIOD
              prev, moved = now, moved + step
              still = step == 0 and still + 1 or 0
            end
            if moved >= need then
              M.log(string.format("[%s] attempt %d released on phase %d "
                .. "(target %d) after %d frames, %d of the %d phases asked for",
                L.tag, n, now, target, waited, moved, need))
              return "done"
            end
            waited = waited + 1
            if still >= M.SEED_PERIOD then
              error(string.format("%s: attempt %d asked the game-time frame "
                .. "counter for %d phases of movement and it has not moved at "
                .. "all in %d frames (phase %d throughout).  $021e is ticked "
                .. "from the vblank handler of whichever module owns the frame "
                .. "(field reset.asm:286, world interrupt.asm:33/320/584, "
                .. "battle btlgfx_main.asm:1763, menu menu_common.asm:3496); "
                .. "if none of those is running here, no wait of any length "
                .. "moves the battle seed and this attempt cannot be a "
                .. "different fight from the last one.  Put the spread "
                .. "somewhere in this step where the game is running -- before "
                .. "the reload, or after the drive that follows it -- rather "
                .. "than waiting longer here.",
                L.tag, n, need, still, now), 0)
            end
            if waited > M.SEED_PERIOD * 3 then
              error(string.format("%s: attempt %d asked the game-time frame "
                .. "counter for %d phases of movement and got %d in %d frames "
                .. "(phase %d now).  It is advancing, but far under the one "
                .. "tick per frame a running module gives it, so the spread "
                .. "cannot be taken here.  Move it to a point in the step where "
                .. "the game is running normally.",
                L.tag, n, need, moved, waited, now), 0)
            end
            return "frame"
          end,
          reset = function()
            waited, moved, need, prev, still = 0, 0, nil, nil, 0
          end,
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
      -- watcher missed.  Checked before the empty case below, as the more
      -- specific account of the same symptom.
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
      -- Go inert.  The exec callback cannot be removed from outside one
      -- (Mesen wants that on the CPU's own thread), so a finished ladder's
      -- watcher would otherwise keep charging later battles to its last
      -- attempt.
      cur = 0
    end)
  end

  return L
end

-- ------------------------------------------------------- field state --
-- Live reads of the field engine's party/story state.  These are shared,
-- so they live in the battle core: battle tests that boot on a field map
-- read them to step into their encounter, and the navigation stack in
-- lib/ot6_field.lua is built on top of them.  Addresses from the vendored
-- disassembly: party object pixel coords $086a/$086d via the $0803 leader
-- offset, map index $1f64, player-control gate $1eb9 bit7 + map-load $84
-- + menu-opening $59.

-- The active party's object record: $0803 holds the byte offset of the
-- party leader's object block (`ldy $0803; lda $086a,y`).  The leader is
-- not always character 0 (TERRA); every party-relative read must go
-- through this offset rather than an absolute address.
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
-- interpreter out of their RAM queue, and the PC reads $80xxxx (WRAM
-- mirror) for one frame at a time, every few frames, indefinitely on such
-- maps.  Those excursions do not mean an event is running.
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
-- NOTE: the low-level battle primitives (clearBattle, fightBattle,
-- fightBattleByMenu, fleeBattle) deliberately do NOT auto-care after the
-- battle.  They are the shared measurement primitives -- mechanism tests
-- (battle_naturalmp measures post-battle field MP to the point, etc.)
-- resolve a battle through them and then read exact state, and a care
-- stop that casts a cure would perturb the number under test.  The
-- heal-after-every-battle directive lives in the NAVIGATORS (navTo,
-- worldNavTo, advanceStory, phaseWalk), which model route traversal, and
-- in explicit M.careStop calls a generator places where it wants one.
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
-- Gameplay advances through human-executable inputs, without selective state
-- edits. Complete snapshot restore/branching and memory reads are permitted
-- experiment machinery (docs/TESTING.md). These helpers end battles by play;
-- clearBattle's flag writes belong only in isolated mechanism tests.
--
-- fightBattle: win by edge-tapped A (4 on / 4 off).  A on the top command
-- opens the actor's command list, A confirms its first entry, A accepts
-- the default target.  The same edge taps page through battle dialogs,
-- level-ups, and the victory text.  `spare` keeps clearBattle's
-- goal-formation contract.  Budget note: a played-out win costs real ATB
-- rounds, so budget thousands of frames where clearBattle needed hundreds.

-- ------------------------------------------------------- target cursor --
-- The battle target-select steering machine.  Facts it encodes:
--   * the live cursor mask ($7B7E monster / $7B7D character) blinks,
--     reading 0 on off-frames, so the mask is latched while target select
--     ($7BC2 == $38) is up, and the latch/age/press state resets as soon
--     as target select is down;
--   * a d-pad tap moves the cursor once; steering taps one direction per
--     16-frame press cycle (the caller's 4-on/4-off edge in the first
--     half, hands off in the second) and reads the cells back before the
--     next tap, so every tap's effect is observed, not assumed;
--   * the cursor grid follows the formation's screen layout, which the
--     script does not know in advance.  It learns it: each tap records
--     "from this window state, this direction lands here" (or "moves
--     nothing"), and the next tap is the first step of the shortest known
--     walk to the wanted slot, else an untried direction from where the
--     cursor stands, else a walk toward the nearest state with one.  A
--     2x2 needing up-then-right, a 3-wide row, or a side attack all come
--     out of the same rule.  (The "two presses per direction" rotation
--     this replaced cycled among three cells of a 2x2 for 30000 frames
--     while the party died -- battle_steal, 2026-09.)
--   * crossing to the other side is just another state.  From there the
--     battle layout's crossing direction (M.battleLayout) is tried first,
--     then the reverse of the press that crossed, so the party column is
--     not explored cell by cell before coming back.
-- Bail (fail fast, #176): when every direction from every state this
-- window can reach has been tried and the wanted slot never lit, or the
-- press budget (opts.maxPresses, default 40) is spent, steer raises with
-- the learned map in the message.  Spinning in target select until the
-- drive budget ran out is what this replaced; a caller whose target can
-- legitimately be anything passes nil and takes the default.
-- opts: mask = 0x7B7E (monster, default) or 0x7B7D (character); dirs = the
-- exploration order (default {left,down,right,up}; character-column
-- callers pass {down,up,left,right}); minAge = settled frames before
-- confirming (default 4); maxPresses = the bail budget (default 40).
-- Use: call observe() once per drive frame, in any menu state (it manages
-- its own reset); inside ST_TGT call steer(targetSlot, mf), which returns a
-- button name: "a" once the latched mask has settled on 1<<targetSlot for
-- minAge frames (or immediately when targetSlot is nil, which takes the
-- default), a direction to tap, or nil while the last tap settles.  mf is
-- the caller's drive-frame counter, the same one that paces its press
-- cadence.  T.mask/T.age/T.press stay readable for a caller's own logs.
function M.targetCursor(opts)
  opts = opts or {}
  local mask = opts.mask or 0x7B7E
  local other = (mask == 0x7B7E) and 0x7B7D or 0x7B7E
  local dirs = opts.dirs or { "left", "down", "right", "up" }
  local minAge = opts.minAge or 4
  local maxPresses = opts.maxPresses or 40
  local REVERSE = { left = "right", right = "left", up = "down", down = "up" }
  local T = { mask = nil, age = 0, press = 0, side = nil, dir = nil }
  -- the learned map: edges[state][dir] = the state that tap landed on
  -- (the same state for a tap that moved nothing)
  local edges, pending, lastCycle = {}, nil, nil
  -- A state is which side the cursor is on and what it lights there:
  -- "own" states carry the mask the caller steers (T.mask), "X" states
  -- the far side's, kept so a crossing is seen as a move and walked back.
  local function stateOf()
    if T.mask == nil then return nil end
    return (T.side == "own" and "" or "X") .. string.format("%02X", T.mask)
  end
  local function reset()
    T.mask, T.age, T.press, T.side, T.dir = nil, 0, 0, nil, nil
    edges, pending, lastCycle = {}, nil, nil
  end
  function T.observe()
    if M.readByte(0x7BC2) == 0x38 then
      local m, o = M.readByte(mask), M.readByte(other)
      local side = (m ~= 0 and "own") or (o ~= 0 and "other") or nil
      local v = (side == "own" and m) or (side == "other" and o) or nil
      if v ~= nil then
        if v == T.mask and side == T.side then T.age = T.age + 1
        else T.mask, T.side, T.age = v, side, 1 end
      end
    else
      reset()
    end
  end
  -- breadth-first over the learned map from `from`: the first direction
  -- of the shortest known walk to a state satisfying `goal`, or nil
  local function firstStepTo(from, goal)
    local prev, queue, head = { [from] = false }, { from }, 1
    while head <= #queue do
      local s = queue[head]; head = head + 1
      if s ~= from and goal(s) then
        local step = s
        while prev[step].from ~= from do step = prev[step].from end
        return prev[step].dir
      end
      for _, d in ipairs(dirs) do
        local to = edges[s] and edges[s][d]
        if to ~= nil and to ~= s and prev[to] == nil then
          prev[to] = { from = s, dir = d }
          queue[#queue + 1] = to
        end
      end
    end
    return nil
  end
  -- The exploration order from a state.  On the caller's side the
  -- layout's crossing direction goes last, so the grid is walked before
  -- the far side is visited at all; on the far side the layout's way
  -- back goes first, then the reverse of the press that crossed.
  local function untried(s)
    local L = M.battleLayout()
    local away = (mask == 0x7B7E) and L.toChars or L.toMonsters
    local back = (mask == 0x7B7E) and L.toMonsters or L.toChars
    local seen, order = {}, {}
    local function add(d)
      if d and not seen[d] then seen[d] = true; order[#order + 1] = d end
    end
    if s:sub(1, 1) == "X" then
      for _, d in ipairs(back) do add(d) end
      for _, es in pairs(edges) do
        for d, to in pairs(es) do if to == s then add(REVERSE[d]) end end
      end
      for _, d in ipairs(dirs) do add(d) end
    else
      local crossing = {}
      for _, d in ipairs(away) do crossing[d] = true end
      for _, d in ipairs(dirs) do if not crossing[d] then add(d) end end
      for _, d in ipairs(dirs) do add(d) end
    end
    for _, d in ipairs(order) do
      if not (edges[s] and edges[s][d] ~= nil) then return d end
    end
    return nil
  end
  local function mapText()
    local out = {}
    for s, es in pairs(edges) do
      local parts = {}
      for _, d in ipairs(dirs) do
        if es[d] ~= nil then
          parts[#parts + 1] = d .. ">" .. (es[d] == s and "-" or es[d])
        end
      end
      out[#out + 1] = s .. "{" .. table.concat(parts, " ") .. "}"
    end
    table.sort(out)
    return table.concat(out, " ")
  end
  local function bail(why, target)
    local msg = string.format("target cursor: %s -- slot %d (mask %02X) never "
      .. "lit in this target select; %d taps; learned map: %s", why, target,
      1 << target, T.press, mapText())
    M.log(msg)
    pcall(function() M.screenshot("targetcursor_bail") end)
    error(msg, 0)
  end
  function T.steer(target, mf)
    if target == nil then return "a" end
    if T.side == "own" and T.mask == (1 << target) and T.age >= minAge then
      return "a"
    end
    local cycle = (mf - 1) // 16
    local phase = (mf - 1) % 16
    -- second half of the cycle: hands off while the tap settles
    if phase >= 8 then return nil end
    if cycle ~= lastCycle then
      -- the first tap waits for a settled reading: a window that has not
      -- lit yet, or is still on its opening frames, gets no stray press
      if lastCycle == nil and T.age < minAge then return nil end
      lastCycle = cycle
      local here = stateOf()
      if here == nil then return nil end        -- the window has not lit yet
      if pending ~= nil then
        edges[pending.from] = edges[pending.from] or {}
        edges[pending.from][pending.dir] = here
        pending = nil
      end
      local wantState = string.format("%02X", 1 << target)
      local d = firstStepTo(here, function(s) return s == wantState end)
      if d == nil then d = untried(here) end
      if d == nil then
        d = firstStepTo(here, function(s) return untried(s) ~= nil end)
      end
      if d == nil then
        bail("every direction from every reachable state has been tried",
          target)
      end
      if T.press >= maxPresses then
        bail(string.format("%d taps without landing", T.press), target)
      end
      T.press = T.press + 1
      pending = { from = here, dir = d }
      T.dir = d
    end
    return T.dir
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
-- Healing prefers a cure spell to the bag, the way M.fieldCare does on the
-- field side; opts.cure=false is the item-only drive this had before.  Any
-- character whose live battle Magic list holds a cure can be the healer,
-- which in OT6 usually means whoever is wearing the stone that grants one.
--
-- Call frame() on every frame battleLoadStarted() is true and idle() on the
-- falling edge.  frame() sets the controller pad itself.
--
-- opts.tool names the Tool Edgar reaches for, defaulting to AutoCrossbow.
-- AutoCrossbow is pierce-class, and most of the route's shield rows carry
-- a class key; a formation without a class key (e.g. Zozo's four species,
-- all poison-weak) instead wants the Bio Blaster.
--
-- The tool has to BE in the bag: the Tools-menu steer looks the id up in
-- the live list and drops the plan when it is missing, re-planning on the
-- next frame with no progress.  A caller that names a tool should assert
-- H.invCountOf(id) > 0 first.
--
-- opts.nuke = { spellId, ... } and opts.nukeLore = { loreId, ... } give the
-- whole party an attack-magic repertoire: after the heal policy passes on
-- the turn, any actor casts the first entry it can pay for (lores gate on
-- the Lore command and the live offered table) instead of falling through
-- to Fight.  See the repertoire note in makePlan.
-- Recovery action evidence. Pure ledger first; CPU observers below only read.
-- A confirm press is an attempt, never proof of submission or resolution.
local actionTraceSerial = 0
function M.newRecoveryTrace(tag, emit)
  local T = { pending = {}, queued = {}, running = {} }
  local function event(p, stage, frame, fields)
    local e = { v = 1, id = p.id, tag = tag or "fight", actor = p.actor,
      kind = p.kind, requested = p.requested, target = p.target,
      all = p.all, boost = p.boost, event = stage, frame = frame,
      elapsed_frames = frame - p.frame }
    for k, v in pairs(fields or {}) do e[k] = v end
    emit(e)
  end
  function T.drop(actor, frame, reason)
    local p = T.pending[actor]
    if not p then return end
    event(p, p.stage == "plan" and "drop" or "unresolved", frame,
      { reason = reason, last_stage = p.stage })
    T.pending[actor] = nil
  end
  function T.plan(actor, plan, frame)
    -- A fresh turn supersedes any incomplete evidence for that actor.
    T.drop(actor, frame, "new_plan")
    -- Every plan that becomes a command is traced (the first version
    -- traced only heal/item; the Nerapa lab needed the attack lines in the
    -- same ledger, #156).  A switch, or a muddled actor's defer (#170),
    -- is a menu move, not a command.
    if plan.kind == "switch" or plan.kind == "defer" then return end
    actionTraceSerial = actionTraceSerial + 1
    local p = { id = actionTraceSerial, actor = actor, kind = plan.kind,
      requested = plan.spell or plan.item or plan.skill or plan.lore or 0,
      target = plan.target,
      all = plan.all or false, boost = plan.boostLeft or 0,
      frame = frame, stage = "plan" }
    T.pending[actor] = p
    event(p, "plan", frame, { reason = plan.reason or "recovery" })
  end
  function T.confirm(actor, frame, chars, mons)
    local p = T.pending[actor]
    if p and p.stage == "plan" then
      event(p, "confirm", frame, { chars = chars, mons = mons })
    end
  end
  function T.submit(actor, frame, cmd, attack, targets)
    local p = T.pending[actor]
    if not p or p.stage ~= "plan" then return end
    p.stage, p.submitted = "submit", frame
    p.accepted_command = cmd
    T.pending[actor] = nil
    T.queued[actor] = T.queued[actor] or {}
    table.insert(T.queued[actor], p)
    event(p, "submit", frame, { command = cmd, attack = attack,
      targets = targets, navigation_frames = frame - p.frame })
  end
  function T.start(actor, frame, cmd, attack, targets, hp, mp, bp)
    local queue = T.queued[actor] or {}
    local p = queue[1]
    if not p or p.accepted_command ~= cmd then return end
    table.remove(queue, 1)
    T.running[actor] = p
    p.stage, p.started = "start", frame
    p.command, p.attack, p.targets = cmd, attack, targets
    p.hp, p.mp, p.bp = hp, mp, bp
    event(p, "start", frame, { command = cmd, attack = attack,
      targets = targets, queue_frames = frame - p.submitted })
  end
  function T.resolve(actor, frame, hp, mp, bp)
    local p = T.running[actor]
    if not p then return end
    local deltas = {}
    for i = 1, 4 do deltas[i] = hp[i] - p.hp[i] end
    -- Net HP across the command, not an attributed healing amount (Runic,
    -- counters, misses and caps can change the outcome). Preserve raw facts.
    event(p, "resolve", frame, { command = p.command, attack = p.attack,
      targets = p.targets, hp_net = table.concat(deltas, ","),
      mp_net = mp - p.mp, bp_net = bp - p.bp,
      execution_frames = frame - p.started })
    T.running[actor] = nil
  end
  -- A party death (#175), outside the per-plan lifecycle: the member,
  -- the HP the killing action found them at, the pips they held and the
  -- party's, and the killer's slot/command/attack.  action_trace.py
  -- skips it when folding plans; the boost audit reads it.
  function T.death(frame, fields)
    local e = { v = 1, tag = tag or "fight", event = "death", frame = frame }
    for k, v in pairs(fields or {}) do e[k] = v end
    emit(e)
  end
  function T.close(frame, reason)
    for actor = 0, 3 do
      T.drop(actor, frame, reason)
      for _, p in ipairs(T.queued[actor] or {}) do
        event(p, "unresolved", frame, { reason = reason, last_stage = p.stage })
      end
      local p = T.running[actor]
      if p then event(p, "unresolved", frame,
        { reason = reason, last_stage = p.stage }) end
    end
    T.queued, T.running = {}, {}
  end
  return T
end

local recoveryObserver, recoveryHooks, recoveryEvents = nil, false, {}
local function recoveryFlush()
  local function json(v)
    if type(v) ~= "string" then return tostring(v) end
    return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
      return string.format('\\u%04x', c:byte())
    end) .. '"'
  end
  for _, e in ipairs(recoveryEvents) do
    local keys, fields = {}, {}
    for k in pairs(e) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do fields[#fields + 1] = json(k) .. ':' .. json(e[k]) end
    -- Print once, outside CPU callbacks. M.log duplicates notes in live streams.
    print('[ot6action] ' .. '{' .. table.concat(fields, ',') .. '}')
  end
  recoveryEvents = {}
end
local function recoveryHP()
  local hp = {}
  for e = 0, 3 do hp[e + 1] = M.readWord(0x3BF4 + e * 2) end
  return hp
end
local function recoveryActivate(trace)
  if recoveryObserver ~= trace then
    if recoveryObserver then recoveryObserver.close(M.frame, "driver_changed") end
    recoveryObserver = trace
  end
  if recoveryHooks then return end
  recoveryHooks = true
  local function hook(addr, fn)
    emu.addMemoryCallback(function()
      if recoveryObserver then fn(recoveryObserver, emu.getState()) end
    end, emu.callbackType.exec, addr, addr)
  end
  -- GetPlayerAction has consumed the user queue entry before calling this;
  -- X is entity offset, Y is queue offset. Read the accepted raw command.
  hook(M.sym("GetPlayerTargets"), function(t, cpu)
    local x, y = cpu["cpu.x"] & 0xffff, cpu["cpu.y"] & 0xffff
    if x < 8 and x % 2 == 0 then
      t.submit(x // 2, M.frame, M.readByte(0x2BAF + y),
        M.readByte(0x2BB0 + y), M.readWord(0x2BB1 + y))
    end
  end)
  -- ExecAction calls ExecCmd with X restored to the acting entity. $b5/$b6
  -- now contain the command/attack after queue-time spell folding.
  hook(M.sym("ExecCmd@battle_code"), function(t, cpu)
    local x = cpu["cpu.x"] & 0xffff
    if x < 8 and x % 2 == 0 then
      t.start(x // 2, M.frame, M.readByte(0xB5), M.readByte(0xB6),
        M.readWord(0xB8), recoveryHP(), M.readWord(0x3C08 + x),
        M.readByte(0x3E9C + x))
    end
  end)
  -- Immediately after ExecCmd returns to the normal-action path, including
  -- graphics/status processing. This is not a menu-close or an HP heuristic.
  hook(M.sym("SaveForMimic"), function(t, cpu)
    local x = cpu["cpu.x"] & 0xffff
    if x < 8 and x % 2 == 0 then
      t.resolve(x // 2, M.frame, recoveryHP(), M.readWord(0x3C08 + x),
        M.readByte(0x3E9C + x))
    end
  end)
end
function M.finishRecoveryTrace(reason)
  if recoveryObserver then
    recoveryObserver.close(M.frame, reason or "run_ended")
    recoveryObserver = nil
  end
  recoveryFlush()
end

-- Which party entity's normal command the engine is executing right now:
-- set at ExecCmd (X = the acting entity's offset, battle_code) and moved
-- to execDone at SaveForMimic, the same two exec observers the action
-- trace reads, installed once and always on (the trace's are behind its
-- flag).  The fight driver's damage watch credits monster HP drops to
-- this entity.  Measured on the Nerapa lab (2026-09-07): the party's
-- first commands sat queued 1200-1500 frames behind the boss's four
-- Condemned casts, past a FIFO watch's 900-tick expiry, so CELES's Fight
-- was credited to TERRA's summon on one seed and EDGAR's crossbow on
-- another.  Read-only.
-- Only a menu command counts (#207): the engine runs its own actions
-- through ExecCmd with the character's X too -- command $22, the dot
-- tick of Poison / Regen / Seize (battle_main.asm Cmd_22), and the other
-- engine commands from $1E up (SaveForMimic's own "command >= $1e" line)
-- -- and a Seized TERRA's drain tick at t=874/1560 settled her pending
-- Fire 2's watch at 0 before the cast ran at t=1582 for 483 (Air Force
-- lab terrafire_i0).  Those land in execParty (any party X executing,
-- which the hit ledger reads as "nobody's") and execSkipped (for the
-- driver's log), never in execActor / execDone.
local EXEC_MENU_CMDS = 0x1E           -- commands below this are the menu's
local execActor = nil                 -- entity 0..3 whose menu command ExecCmd entered
local execActorCmd = nil              -- { cmd, atk } that command
local execDone = {}                   -- { actor, frame, cmd, atk } per SaveForMimic, oldest first
local execParty = nil                 -- entity 0..3 executing anything (menu or engine command)
local execSkipped = {}                -- { actor, frame, cmd, atk } engine commands run under a party X
-- and the monster half of the same two observers (#165): the slot 0..5
-- (X = 8 + slot*2) whose command is executing, and the last one to
-- return with its frame.  The fight driver's hit ledger credits party HP
-- drops to this slot -- the number a person reads off the damage
-- numeral over their own character.
local execMon = nil                   -- slot whose command ExecCmd entered
local execMonDone = nil               -- { slot, frame } of the last to return
-- and WHAT that slot is doing: $b5/$b6 are the command and attack after
-- queue-time folding, the bytes the labs' [act] lines print (ExecCmd runs
-- with them set; battle_main.asm).  The hit ledger tells a level spell
-- from a swing by them (#174) and the [death] line names the killer.
local execMonCmd, execMonAtk = nil, nil
local execHooks = false
local function execActivate()
  if execHooks then return end
  execHooks = true
  local a = M.sym("ExecCmd@battle_code")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if x < 8 and x % 2 == 0 then
      execParty = x // 2
      local cmd, atk = M.readByte(0xB5), M.readByte(0xB6)
      if cmd < EXEC_MENU_CMDS then
        execActor, execActorCmd = x // 2, { cmd = cmd, atk = atk }
      elseif #execSkipped < 32 then        -- drained by a driver's frame; bounded without one
        execSkipped[#execSkipped + 1] = { actor = x // 2, frame = M.frame, cmd = cmd, atk = atk }
      end
    elseif x < 20 and x % 2 == 0 then
      execMon = x // 2 - 4
      execMonCmd, execMonAtk = M.readByte(0xB5), M.readByte(0xB6)
    end
  end, emu.callbackType.exec, a, a)
  local b = M.sym("SaveForMimic")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if x < 8 and x % 2 == 0 then
      if execParty == x // 2 then execParty = nil end
      if execActor == x // 2 then
        execDone[#execDone + 1] = { actor = x // 2, frame = M.frame,
          cmd = execActorCmd and execActorCmd.cmd, atk = execActorCmd and execActorCmd.atk }
        execActor, execActorCmd = nil, nil
      end
    elseif x < 20 and x % 2 == 0 then
      execMonDone = { slot = x // 2 - 4, frame = M.frame }
      if execMon == x // 2 - 4 then execMon = nil end
    end
  end, emu.callbackType.exec, b, b)
end

-- The unknown-menu guard's ledger (#188), one per run and bucketed by the
-- $7BC2 state, so the driver's KNOWN_ST table is a measurement rather
-- than a guess: `seen` counts every pulse a fight driver's button()
-- sampled at a menu state it does not know, `drops` every time the guard
-- fired (dropPlan("unknown_menu") and a B out).  Every driver in the run
-- adds to the same ledger; watchReport prints it beside the verdict as
-- the `[watch] unknown-menu` line, and the driver logs each state's
-- first sighting in a battle with the actor, the command row and a
-- screenshot (the `[unknown-menu]` lines).  Per the standing rule, every
-- state that shows up here is a verb the driver has yet to learn.
M.unknownMenu = { seen = {}, drops = {}, order = {} }
local function unknownMenuNote(kind, st)
  local T = M.unknownMenu
  if T.seen[st] == nil and T.drops[st] == nil then T.order[#T.order + 1] = st end
  T[kind][st] = (T[kind][st] or 0) + 1
end
function M.unknownMenuReport()
  local T = M.unknownMenu
  if #T.order == 0 then
    return "unknown-menu drops by $7BC2 state: none (no unknown state sampled)"
  end
  table.sort(T.order)
  local drops, seen, nd, ns = {}, {}, 0, 0
  for _, st in ipairs(T.order) do
    drops[#drops + 1] = string.format("$%02X=%d", st, T.drops[st] or 0)
    seen[#seen + 1] = string.format("$%02X=%d", st, T.seen[st] or 0)
    nd, ns = nd + (T.drops[st] or 0), ns + (T.seen[st] or 0)
  end
  return string.format("unknown-menu drops by $7BC2 state: %s (%d drop(s)); "
    .. "pulses sampled there: %s (%d); the [unknown-menu] lines name each "
    .. "state's first sighting per battle", table.concat(drops, " "), nd,
    table.concat(seen, " "), ns)
end

function M.newFightDriver(tag, opts)
  opts = opts or {}
  local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
  local CMDTBL, CMDROW, BCHID, BP, CURMP =
    0x202E, 0x890F, 0x3ED8, 0x3E9C, 0x3C08
  local CMD_FIGHT, CMD_ITEM, CMD_MAGIC, CMD_TOOLS, CMD_BLITZ =
    0x00, 0x01, 0x02, 0x09, 0x0A
  local ST_CMD, ST_ITEM, ST_MAGIC, ST_TGT, ST_TOOLS, ST_ESPER =
    0x05, 0x0A, 0x0E, 0x38, 0x30, 0x16
  -- the Lore command and its window's two states (the transitional DMA
  -- fill, then the list itself), and the window's cursor pair: absolute
  -- row = scroll ($891f) + in-window row ($8927), the item window's shape
  -- (UpdateMenuState_1b / _c183f7, btlgfx_main.asm)
  local CMD_LORE, ST_LORE_OPEN, ST_LORE = 0x0C, 0x19, 0x1B
  -- SHADOW's Throw: cmd $08 -> $2B (OpenThrowWindow builds wItemList) ->
  -- $2D (item select) -> ST_TGT (probe_throw.lua; btlgfx
  -- UpdateMenuState_2b/2d).  The skeans and their element bits:
  -- Fire Skean $AB=fire($01), Water Edge $AC=water($80), Bolt Edge
  -- $AD=bolt($04) (bosses-wob.md's element byte convention).
  local CMD_THROW, ST_THROW_OPEN, ST_THROW = 0x08, 0x2B, 0x2D
  local SKEAN_ELEM = { [0xAB] = 0x01, [0xAC] = 0x80, [0xAD] = 0x04 }
  -- The command window's two side windows (probe_rowdef.lua, #188): LEFT
  -- at command select opens Row ($05 -> $01 -> $24) and RIGHT opens Def.
  -- ($05 -> $01 -> $27).  Inside either, A commits the row change or the
  -- defend as the turn's command, B or the opposite direction closes it
  -- ($01 -> $05, the command cursor where it was), and the direction that
  -- opened it is not read at all: LEFT held 120 frames in $24 moved
  -- nothing (UpdateMenuState_24 @7e81 reads only A, B and RIGHT).  That
  -- is the v0.17 train_done attempt-1 no-effect trip: a LEFT held from
  -- the field walk into the battle opened Row, and the driver, not
  -- knowing $24, sat there until the watchdog tripped.  This driver never
  -- means to be in either; it backs out with B and keeps its plan.
  local ST_ROW, ST_DEF = 0x24, 0x27
  -- EDGAR's Tools family (probe_tools.lua, #188): A on the Tools row ->
  -- $2E (OpenToolsWindow builds wItemList, ~7 frames) -> $01 -> $30 (the
  -- list, ST_TOOLS); B from the list -> $01 -> $05 directly
  -- (CloseToolsWindow is a subroutine there, so $2F is not written); A on
  -- a tool -> $38 target select, B -> $30.  $2F is the force-close state
  -- the engine walks through after a commit ($7BCB set: $30 -> $2F ->
  -- $01 -> $05), and OT6's Blitz, Bushido and Steal ladders reuse this
  -- shell ($6168 mode byte), so every Sabin and Cyan fight passes here
  -- too.  Both are transitional: the plan waits them out.
  local ST_TOOLS_OPEN, ST_TOOLS_CLOSE = 0x2E, 0x2F
  local LSCROLL, LROW = 0x891F, 0x8927
  local MAXMP = 0x3C30
  local ITEMSCR, ITEMROW, BATTINV, ITEMLIST = 0x8947, 0x894F, 0x2686, 0x4005
  local BLCOL, BLROW = 0x8963, 0x8967
  -- the magic list's cursor triple: scroll+row is the absolute grid row,
  -- col the column; grid cell N sits at row N//2, column N%2.
  local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B
  -- $302C,entity is the engine's own pointer at that character's compacted
  -- battle Magic list.  Record 0 is the esper row and record n+1 is grid
  -- cell n.
  local MLISTPTR = 0x302C
  local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
  -- The battle's layout, read not assumed (M.battleLayout, #176): which
  -- type of battle the engine set and therefore which way the target
  -- cursor crosses between the party and the monsters.  Read once per
  -- battle and logged; a side attack's group can move, so the crossing
  -- direction is re-read each time it is needed.
  local layout = nil
  -- Every steer press and whether it moved anything: a direction that
  -- twice changed no cell in the target window is not a direction here
  -- (in a back attack LEFT is an rts), and the driver says so rather than
  -- pressing it until the fight is lost.
  local steerLast = nil                -- { dir, sig, kind }
  local steerDead = {}                 -- dir -> presses with no effect
  -- multi-target latch: one R press on a MULTI_TARGET spell's target screen
  -- sets this to 1 and widens the side mask to every valid ally/monster
  -- (probe_targetall.lua measured it; btlgfx_main.asm @6e9a sets it)
  local TGTALL = 0x7B7F
  -- folded cure MP by tier (magic_prop_en.dat +$05: $2D/5, $2E/25, $2F/40);
  -- the fold charges the folded tier's real cost (mp-economy.md)
  local CURE_MP = { [0x2D] = 5, [0x2E] = 25, [0x2F] = 40 }
  local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
  local AUTOCROSSBOW, PUMMEL = M.AUTOCROSSBOW, 0x5D
  -- The cures, cheapest first: the loop simply casts again if the target
  -- is still short, so overshoot is only wasted MP.  Under OT6 the upper
  -- tiers are folds of the base spell rather than separate grants, so in
  -- practice only the first of these is ever found in the list.
  local CURES = { 0x2D, 0x2E, 0x2F }
  local F = {}
  local recovery = (opts.actionTrace or OT6_ACTION_TRACE) and
    M.newRecoveryTrace(tag, function(e) recoveryEvents[#recoveryEvents + 1] = e end)
  local menuStreak, tick, battleTick = 0, 0, 0
  local plan, planActor, held = nil, nil, {}
  local heldFast = false            -- the live steer asked for 3 presses/pulse
  local tgtSpin = 0                    -- frames spent undecided in ST_TGT
  local unknownSt, unknownN = nil, 0   -- unknown-menu-state stall guard
  local unknownSeen = {}               -- st -> true once logged this battle (#188)
  local sideWindowN = 0                -- Row/Def. windows backed out of this battle
  local parkSt, parkN = nil, 0         -- parked-KNOWN-window watchdog
  local idleSt, idleN = nil, 0         -- plan-less open-window back-out
  -- The two numbers the heal policy weighs against each other, both measured
  -- in the fight rather than assumed.  See the policy note in makePlan.
  local roundCost = {}                 -- entity -> worst HP lost per own turn
  local turnSnap = {}                  -- actor -> party HP at its last turn
  local itemRestore = {}               -- item  -> HP a landed use put back
  local castRestore = {}               -- spell -> HP a landed cast put back
  -- The two ledgers the #165 rules read, both measured in the fight:
  -- what this actor's last action landed PER HIT (the kill-this-turn
  -- estimate), and what each monster's actions have taken off each party
  -- member (the raise rule's smallest hit).
  local dmgHit = {}                    -- actor -> { kind, skill, per, n }
  local hitLedger = {}                 -- slot -> { min, minE, on = { [e] = smallest },
                                       --          max, maxOn = { [e] = largest one action } }
  local partyHpLast = {}               -- entity -> HP last frame (hit ledger baseline)
  local monHpLast = {}                 -- slot -> HP last frame (damage watch baseline)
  -- The monster action in progress, for the ledger and the death lines
  -- (#175, #174): which slot, its command/attack bytes, each member's HP
  -- as it began (so a kill can be read as "from 447/447 in one action"),
  -- and how many it has killed from full so far.
  local monAct = nil                   -- { slot, cmd, atk, tick, hp0 = {}, kills, fullKills }
  -- Boost left on the table (#175): every party death logged once with
  -- the member's banked BP, and one [wipe] line per battle.  A person
  -- watching sees the pips over the dead portrait; this writes them down.
  local deathSaid = {}                 -- entity -> true while it lies dead
  local battleDeaths = {}              -- the [death] records this battle, for the [wipe] line
  local wipeSaid = false
  local ONE_SHOT_PCT = 80              -- killed from at least this much of max HP by one action
  local EARLY_TICKS = 1800             -- ...inside this many battle ticks is "one-shot early"
  local BANKED_BP = 3                  -- dying with this many pips is "died with BP banked"
  -- The raise-then-top-up pair (#168): a Fenix Down confirmed by one actor
  -- (raisePending, until the target's HP moves or RAISE_WAIT ticks pass)
  -- holds the next actor's plan at the command window so their Potion
  -- finds a living target; once it lands, the raised member is owed a
  -- top-up (topUpOwed) that the one-care-per-round budget lets through.
  local raisePending = nil             -- { e, by, tick }
  local topUpOwed = {}                 -- entity -> battleTick the raise landed
  local RAISE_WAIT = 240               -- ticks a pending raise holds a plan
  -- Every confirmed Fenix Down not yet landed, by target (raisePending
  -- holds only the latest, and its window hold lapses at RAISE_WAIT while
  -- the item can still sit in the queue behind the enemy's animations).
  -- A second actor's raise on the same corpse is a wasted Fenix: measured
  -- on map 269, two Fenix Downs confirmed on one member 240+ ticks apart
  -- both executed (branch_boostfight_s48: f4322 and f4734, tgt $0008).
  local raiseQueued = {}               -- e -> { by, tick }
  -- and every confirmed status cure not yet landed, by target (#187):
  -- measured on mrf_263 (probe_statuses, 2026-09-16), actor 3's Green
  -- Cherry on entity 1 was confirmed, actor 0 planned a second on the
  -- same entity 480 frames later while the first sat in the queue, and
  -- both were spent (4 -> 2 in the bag) on one Imp.
  local cureQueued = {}                -- e -> { by, tick, item }
  -- and the Muddle rule's own pending hit (#170): one ally's Fight on the
  -- muddled member is in the air, so the next actor plans normally rather
  -- than land a second hit on a member the first one already cleared
  -- (measured from n024_entry: LOCKE's hit at f1143 on a SABIN CELES had
  -- cleared at f886).
  local unmuddlePending = nil          -- { e, by, tick }
  -- the ATB words per entity (X = entity*2): the 16-bit gauge and the
  -- constant added to it each tick (M.atbEta), and STATUS2 ($3ee5)
  local ATB, ATB_CONST, ST2 = 0x3218, 0x3AC8, 0x3EE5
  -- and STATUS1 ($3ee4) / STATUS3 ($3ef8) for the turn-denying statuses
  -- and Imp (#187, M.turnDenied / M.statusCure)
  local ST1, ST3 = 0x3EE4, 0x3EF8
  local statusSaid = {}                -- "e:name" -> true once said this battle
  local cureSaid = nil                 -- the last cure refusal logged, once
  local freeRoundSaid = false          -- the preemptive free-round line, once
  local healWatch = nil                -- a confirmed heal, awaiting its effect
  local healSaid = nil                 -- last refusal logged, to log it once
  local priceSaid = {}                 -- entity -> the last [round] price line said
  local finisherSaid = nil             -- the finisher window yielding (#204), once per reason
  local inertSaid = {}                 -- "actor:spell" -> true once an unknown config spell is said (#182)
  local summonWhyN = 0                 -- summon-refusal diagnostics, capped
  local parkDropN = 0                  -- watchdog fires this battle (see below)
  local careActor = nil                -- who took this round's one care turn
  -- A plan dropped before it lands (park, pulse cap, a cell the steer
  -- cannot find) must not have spent the round's care budget: the actor
  -- backs out to a fresh window and plans again, so the budget it claimed
  -- at creation is refunded here.
  local function traceDrop(reason)
    if recovery and planActor then
      local pending = recovery.pending[planActor]
      if pending and pending.stage == "plan" then
        recovery.drop(planActor, M.frame, reason)
      end
    end
  end
  local function dropPlan(reason)
    if reason ~= "confirm_attempt" then traceDrop(reason or "back_out") end
    if careActor ~= nil and careActor == planActor then careActor = nil end
    plan, planActor = nil, nil
  end
  local startSnap = nil                -- party HP when the battle opened
  local planPulses = 0                 -- pulses the live plan has consumed
  local steerTrail = {}                -- the list steer's last samples (see the cap drop)
  local loreSpinN = 0                  -- frames spent on live lore plans
                                       -- since the last landed lore cast
  local loreDead = false               -- the stall guard fired this battle

  -- A command row the cursor can actually land on.  Each $202E row is
  -- three bytes -- id, flags, targeting -- and flags bit 7 is the engine's
  -- own "disabled" mark (UpdateCmdList, battle_main.asm: `ror $0001,x`
  -- writes each updater's carry there; btlgfx check_command reads it and
  -- the command cursor SKIPS such a row).  A row that reads as present
  -- but disabled is therefore unreachable: the steer's down/up hops over
  -- it, cur oscillates 1 <-> 3 and the plan parks in ST_CMD until the
  -- pulse cap drops it (#153: LOCKE, Muted by a Naughty on the FC escape,
  -- Magic row flags $80, "consumed 41 pulses in state $05 without
  -- landing" ten times over while the party bled out).  So a disabled
  -- row is reported as absent, and the plan falls through to a line the
  -- cursor can reach, the way a person reads a greyed command.
  local function cmdDisabled(actor, row)
    return (M.readByte(CMDTBL + actor * 12 + row * 3 + 1) & 0x80) ~= 0
  end
  local function cmdRow(actor, cmd)
    for row = 0, 3 do
      if M.readByte(CMDTBL + actor * 12 + row * 3) == cmd
         and not cmdDisabled(actor, row) then
        return row
      end
    end
    return nil
  end

  -- opts.reserve = { [itemId] = n }: never spend the last n.  The bag is
  -- shared across scenarios, so a party that spends the last Potion
  -- whenever the HP gap is large enough is not playing the way a player
  -- does.
  local function battInvIdx(id)
    local floor = (opts.reserve or {})[id] or 0
    for i = 0, 251 do
      if M.readByte(BATTINV + i * 5) == id
         and M.readByte(BATTINV + i * 5 + 3) > floor then return i end
    end
    return nil
  end

  -- What one use of an item gives back.  The prior is M.itemPower, the
  -- +$14 power byte; it is a prior and not the answer, because power is an
  -- input to the engine's heal routine rather than its output.  The first
  -- use that lands replaces it with the HP that actually came back
  -- (F.frame's healWatch).
  local function itemRestoreOf(item)
    return itemRestore[item] or M.itemPower(item)
  end

  -- Where a spell sits in this actor's live battle Magic list, and what the
  -- engine has priced it at.  Returns the grid cell (the number the cursor
  -- walk below steers to) and the MP cost, or nil if the actor cannot cast
  -- it right now.
  --
  -- Read live, per actor, rather than taken from the caller: the list is
  -- compacted to the union of what the party knows plus each equipped
  -- esper's spells, so the same spell sits at different cells for
  -- different loadouts.  Row layout: +0 id, +1 flags (bit 7 = greyed), +2
  -- targeting, +3 MP cost.  The price is read here rather than out of
  -- magic_prop_en.dat because the engine's copy is the one it charges.
  --
  -- `strict` picks how hard to refuse.  Deciding what to do (strict) asks
  -- the game's own greyed bit as well, the authority on castability.
  -- Steering a list that is already open (not strict) asks only the live
  -- MP, because the greyed bit is refreshed on the action boundary and a
  -- bit that has gone stale under an open window would drop a plan that
  -- was fine, spending the healer's turn on a B press.
  local function spellCell(actor, id, strict)
    local base = M.readWord(MLISTPTR + actor * 2)
    if base < 0x2000 or base > 0x2600 then return nil end
    for cell = 0, 53 do
      local a = base + (cell + 1) * 4
      if M.readByte(a) == id then
        local cost = M.readByte(a + 3)
        if M.readWord(CURMP + actor * 2) < cost then return nil end
        if strict and (M.readByte(a + 1) & 0x80) ~= 0 then return nil end
        return cell, cost
      end
    end
    return nil
  end
  -- Whether `id` is in the actor's compacted list at all, MP and the
  -- greyed bit aside (#182).  spellCell's nil is "cannot pay or greyed"
  -- or "does not know it", and the second is a config bug worth a line:
  -- gen_fc_alcove's Bolt line was inert for 13 of 13 TERRA turns with
  -- nothing in the log saying so.  With no list to read (the pointer
  -- outside the list area) this is not the rule's call and answers true.
  local function spellKnown(actor, id)
    local base = M.readWord(MLISTPTR + actor * 2)
    if base < 0x2000 or base > 0x2600 then return true end
    for cell = 0, 53 do
      if M.readByte(base + (cell + 1) * 4) == id then return true end
    end
    return false
  end

  -- OT6's per-monster state, slot-indexed: monsters are entities 4..9 at a
  -- 2-byte stride, so slot s sits 8 bytes past the ot6_memory.inc base.
  local MON_HP, MON_PRESENT = 0x3BFC, 0x3AA8
  local SH_CUR, BRK_TICKS = 0x3E40, 0x3E90         -- OT6_SHIELD_CUR/BROKEN_TICKS + 8
  local RV_ELEM, RV_CLASS = 0x3E91, 0x3EA5         -- OT6_REVEALED_ELEM/BOOST_REVEALED + 8
  local MON_ST3 = 0x3F00                           -- current status 3 ($3EF8) + 8
  -- the live element record: $3bcc,x is the entity's absorbed (low byte)
  -- and nullified (high byte) elements, seeded from MonsterProp +23/+24 by
  -- LoadMonsterProp (battle_main.asm `lda f:MonsterProp+23,x / ora $3bcc,y`)
  local MON_ELEM = 0x3BCC + 8

  -- What is on stage right now, slot by slot, with the LIVE record's
  -- bytes: the slots whose presence bit ($3AA8) is set and whose HP is up,
  -- each with its species word, its absorb/null bytes and its Reflect bit.
  -- This is what the cast guards below judge (#172).
  --
  -- Two things this deliberately does NOT read.  The formation's
  -- present mask ($3F45, M.formationSpecies): that byte is the
  -- formation record's opening line-up, copied once at load and never
  -- updated, so a monster the script materialises later is not in it --
  -- battle 70 reads $01 while Shiva stands on stage in slot 1, and a
  -- guard enumerating that mask never saw her (CELES's Ice "took 0 off
  -- the monsters" three times a fight while she drank it).  And the ROM's
  -- species record: the slot's own $3bcc bytes are the engine's truth
  -- for whatever occupies it, seeded from the same record and robust to
  -- a slot being reloaded.  Only a slot that is alive AND on the field
  -- can drink a cast: a tag-team sibling waiting off-stage is
  -- untargetable, and counting it vetoed the element for the whole fight
  -- (Ifrit & Shiva: Shiva's ice absorb blocked the Ice casts the fight's
  -- own design doc prescribes against Ifrit).  With the presence filter
  -- the guard doubles as the tag-fight strategy: the element flows while
  -- its absorber is off-stage and yields to the sword the moment she
  -- steps on.
  local function stageSlots()
    local out = {}
    for slot = 0, 5 do
      if M.readWord(MON_HP + slot * 2) > 0
         and (M.readByte(MON_PRESENT + slot * 2) & 1) == 1 then
        out[#out + 1] = {
          slot = slot, species = M.readWord(M.FORMATION + slot * 2),
          absorb = M.readByte(MON_ELEM + slot * 2),
          null = M.readByte(MON_ELEM + 1 + slot * 2),
          reflect = (M.readByte(MON_ST3 + slot * 2) & 0x80) ~= 0 }
      end
    end
    return out
  end

  -- The cast guards, shared by every attack-cast line (M.castVeto holds
  -- the decision; this is its log line).  A spell whose element something
  -- on stage ABSORBS is a heal for the enemy (#99); a reflectable spell
  -- (magic_prop +3 bit 1 clear) cast at a monster under Reflect -- status
  -- 3 bit 7 -- deals it nothing and lands its full damage on a party
  -- member (#156: measured on Nerapa, every Bolt/Ice at every tier dealt
  -- 0 to Nerapa, and a 2-BP Bolt 3 killed LOCKE for 1400); a spell whose
  -- every element the target NULLS is the same wasted turn without the
  -- self-inflicted hit.  Any of the three refuses the plan and the actor
  -- falls through (usually to Fight).  Folding never changes a family's
  -- element, so the base ability's element answers for every tier a
  -- pending boost could fold to.  Reading the status byte is what a
  -- person does by looking: the engine draws the Reflect bubble around
  -- the monster ($2E60, the reflect graphics buffer), so the byte is on
  -- screen and blind-player-legitimate, the way the revealed-weakness
  -- bytes are; an absorbed or nulled element shows itself the first time
  -- it lands.  Summons, lores, blitzes, tools, throws and Fights all
  -- carry ignore-reflect or no spell record at all, and pass the Reflect
  -- half.  True means the cast is off the table this turn.
  local function castVetoed(abilityId, what)
    local elem = M.spellElement(abilityId)
    local s, why = M.castVeto(elem, M.spellReflectable(abilityId), stageSlots())
    if not s then return false end
    if why == "absorb" then
      M.log(string.format(
        "[%s] %s $%02X refused: %s is ABSORBED by slot %d species $%04X "
        .. "(live absorb byte $%02X; #99, #172) -- falling through",
        tag or "fight", what, abilityId, M.elemStr(elem), s.slot, s.species,
        s.absorb))
    else
      M.log(string.format(
        "[%s] %s $%02X refused: slot %d species $%04X %s (#156) -- falling "
        .. "through to an unreflectable line", tag or "fight", what,
        abilityId, s.slot, s.species,
        why == "reflect" and "is under REFLECT"
          or ("NULLS " .. M.elemStr(elem) .. string.format(" (live null byte $%02X)", s.null))))
    end
    return true
  end

  -- ---- the chip model (#156) -------------------------------------------
  -- What a person counts off the HUD before pressing: the target's shield
  -- pips, and the weakness icons the fight has REVEALED (RV_CLASS /
  -- RV_ELEM, the bytes the HUD draws; the codex pre-reveals what earlier
  -- fights taught).  An unrevealed axis is a '?' and counts for nothing
  -- here, the same rule SHADOW's throw plays by.  Each landed hit chips
  -- one shield per matched axis (Ot6ClassChip, Ot6Chip; ot6_break.asm);
  -- a hit that matches both is counted once, so the model only ever
  -- under-promises.
  local function hitChips(slot, class, elem)
    if class ~= 0 and (M.readByte(RV_CLASS + slot * 2) & class) ~= 0 then
      return 1
    end
    if elem ~= 0 and (M.readByte(RV_ELEM + slot * 2) & elem) ~= 0 then
      return 1
    end
    return 0
  end
  -- The actor's hands ($1600 + 37*char + $1F/$20, the record partyWeapons
  -- reads): main hand, and the off hand only when it holds a weapon (a
  -- Genji Glove pair); a shield swings nothing.  An empty main hand is a
  -- fist, which Ot6WeapClassTbl classes as bludgeoning.
  local function handsOf(actor)
    local c = M.readByte(BCHID + actor * 2)
    local r = M.readByte(0x1600 + 37 * c + 0x1F)
    local l = M.readByte(0x1600 + 37 * c + 0x20)
    if not M.isWeapon(r) and M.isWeapon(l) then return l, nil end
    return r, (M.isWeapon(l) and l or nil)
  end
  -- Chips a Fight at `boost` lands on `slot`: swings per hand times that
  -- hand's chips per hit.  LOCKE's Genji pair of ThunderBlade (slash,
  -- bolt) and Assassin (pierce) at 2 BP is 3 + 3 swings, six chips on a
  -- slash|pierce-weak gauge -- Nerapa's five, in one action.
  local function fightChips(actor, slot, boost)
    local r, l = handsOf(actor)
    local mainSw, offSw = M.fightSwings(l ~= nil, boost)
    local n = mainSw * hitChips(slot, M.weaponClass(r), M.weaponElement(r))
    if l then
      n = n + offSw * hitChips(slot, M.weaponClass(l), M.weaponElement(l))
    end
    return n
  end
  -- A tool is one hit (Ot6HitCountTbl: the Drill x2); boost multiplies
  -- its damage, not its swings (Ot6FightBoost lives in FightAttack).
  local TOOL_HITS = { [0xA8] = 2 }
  local function toolChips(slot, tool)
    return (TOOL_HITS[tool] or 1) * hitChips(slot, M.weaponClass(tool), 0)
  end
  -- The one monster an untargeted attack lands on: the focus list's first
  -- living entry, else the only living monster on the field.  With
  -- several and no focus the engine's default cursor decides, and the
  -- model does not guess.
  local function soleTarget()
    local only = nil
    for s = 0, 5 do
      if M.readWord(MON_HP + s * 2) > 0
         and (M.readByte(MON_PRESENT + s * 2) & 1) == 1 then
        if only ~= nil then return nil end
        only = s
      end
    end
    return only
  end
  local function pressTarget()
    if opts.focus then
      local ids = M.monsterIds()
      for _, e in ipairs(opts.focus) do
        if ids[e.slot + 1] ~= 0xFFFF
           and M.readWord(MON_HP + e.slot * 2) > 0 then return e.slot end
      end
    end
    return soleTarget()
  end
  local function livingMonsters()
    local n = 0
    for s = 0, 5 do
      if M.readWord(MON_HP + s * 2) > 0
         and (M.readByte(MON_PRESENT + s * 2) & 1) == 1 then n = n + 1 end
    end
    return n
  end
  -- What the party's attacks have been landing, measured the way a person
  -- reads the numerals: at a damage plan's confirm a watch joins the
  -- list; monster HP falling while that actor's command executes (the
  -- execActor observer above) is credited to the actor's oldest watch,
  -- and a beat after the command returns the figure is settled and
  -- normalized to shielded-equivalent damage (Ot6ShieldedDmg x0.5 then
  -- Ot6BrokenDmg x2: broken is x4 shielded, weak or not, so a hit that
  -- lands on a broken target is /4).  A command that moved nothing (a
  -- reflected cast, a miss) settles at 0; a counter's damage outside
  -- that beat, with no party command executing, is nobody's.  The press
  -- rule that consumes
  -- it only ever asks "does the window cover the HP", where an error is
  -- one more heal turn, not a lost fight.
  local dmgWatch = {}                  -- { actor, kind, skill, seen, norm, n, until_ }, confirm order
  local dmgSeen = {}                   -- entity -> shielded-equivalent HP its last action took
  local DMG_SETTLE = 45                -- frames after SaveForMimic before the figure is read
  local DMG_EXPIRE = 3600              -- a confirmed plan that never executed (hygiene)
  local function dmgWatchOf(e)
    for i, w in ipairs(dmgWatch) do if w.actor == e then return i, w end end
    return nil
  end
  local function monAlive(s)
    return M.readWord(MON_HP + s * 2) > 0
       and (M.readByte(MON_PRESENT + s * 2) & 1) == 1
  end
  -- ticks until entity X's gauge fills (X = e*2 for the party, 8 + s*2
  -- for a monster slot), and its high byte for the log (0 = full)
  local function etaOf(x)
    local g = M.readWord(ATB + x)
    return M.atbEta(g, M.readWord(ATB_CONST + x)), g >> 8
  end
  -- The four status bytes' verdict on a party entity (#187): the name of
  -- the status denying its turn, or nil; and whether it is an imp.
  local function statusOf(e)
    return M.readByte(ST1 + e * 2), M.readByte(ST2 + e * 2), M.readByte(ST3 + e * 2)
  end
  local function denied(e)
    local s1, s2, s3 = statusOf(e)
    return M.turnDenied({ s1 = s1, s2 = s2, s3 = s3 })
  end
  local function isImp(e)
    return (M.readByte(ST1 + e * 2) & M.ST1_IMP) ~= 0
  end
  local function bagCount(id)
    local n = 0
    for i = 0, 251 do
      if M.readByte(BATTINV + i * 5) == id then n = n + M.readByte(BATTINV + i * 5 + 3) end
    end
    return n
  end
  -- The cure the bag holds for entity e's Imp (Green Cherry, then Remedy)
  -- or Berserk (nothing in this ROM), through M.statusCure and the
  -- reserve-aware battInvIdx.
  local function cureFor(e)
    if isImp(e) then
      return M.statusCure({ byte = 1, bit = M.ST1_IMP,
        has = function(item) return battInvIdx(item) ~= nil end }), "Imp"
    end
    if (M.readByte(ST2 + e * 2) & M.ST2_BERSERK) ~= 0 then
      return M.statusCure({ byte = 2, bit = M.ST2_BERSERK, items = { M.REMEDY },
        has = function(item) return battInvIdx(item) ~= nil end }), "Berserk"
    end
    return nil, nil
  end
  -- The party's measured window on one slot, the press rule's sum with
  -- the deciding actor left out (they are spending the turn elsewhere):
  -- each living member's last action in shielded-equivalent HP, x4 when
  -- the target is broken.
  local function partyWindow(actor, slot)
    local broken = M.readByte(BRK_TICKS + slot * 2) ~= 0
    local window, parts = 0, {}
    for e2 = 0, 3 do
      if e2 ~= actor and M.readWord(0x3BF4 + e2 * 2) > 0
         and M.readWord(0x3C1C + e2 * 2) > 0 and dmgSeen[e2] then
        local mult = broken and 4 or 1
        window = window + dmgSeen[e2] * mult
        parts[#parts + 1] = string.format("e%d:%dx%d", e2, dmgSeen[e2], mult)
      end
    end
    return window, table.concat(parts, " "), broken
  end
  -- The raise rule's question (#165, #168), read off the hit ledger and
  -- the gauges: over the living monsters, the smallest hit each has
  -- landed on this member -- or, with none on them yet, on anybody --
  -- and whether a Fenix Down's maxhp/8 survives it (M.raiseDecision),
  -- with the two outs the refinement added measured here: (b) the last
  -- monster inside the party's window (partyWindow), and (a) another
  -- member's gauge filling before the earliest-acting lethal slot's,
  -- with the bag's Potion (else Tonic) as the top-up.  A broken slot
  -- takes no turns (Ot6Gate skips them) and is not due to act.  Returns
  -- ok, the raise HP, the hit with its slot and victim (nil when nothing
  -- is measured), and the reason with every number in it.
  -- A closed monster action's drops go into the hit ledger here (#165):
  -- every hit is the floor, a level spell's included.  The #174 exemption
  -- (a level spell's kill is not a per-turn floor) was tried and measured
  -- on the map-269 trio, 15 seeds, main's gate against it: 20 Fenix Downs
  -- against 12 and no frames gained (8127 vs 8126), because the 55-HP
  -- raise never survives the next Flare either.  main's gate stands.
  local function commitMonAct(act)
    if #act.drops == 0 then return end
    local L = hitLedger[act.slot] or { on = {} }
    hitLedger[act.slot] = L
    -- the largest ONE action on each member (a two-hit Battle is one
    -- action): what the round price (M.roundCost) charges per action
    L.maxOn = L.maxOn or {}
    local per = {}
    for _, d in ipairs(act.drops) do per[d.e] = (per[d.e] or 0) + d.drop end
    for e, v in pairs(per) do
      if L.maxOn[e] == nil or v > L.maxOn[e] then L.maxOn[e] = v end
      if L.max == nil or v > L.max then L.max = v end
    end
    for _, d in ipairs(act.drops) do
      if L.on[d.e] == nil or d.drop < L.on[d.e] then L.on[d.e] = d.drop end
      if L.min == nil or d.drop < L.min then
        L.min, L.minE = d.drop, d.e
        M.log(string.format("[%s] slot %d's smallest hit this fight so far: "
          .. "%d, on entity %d (%d -> %d)", tag or "fight", act.slot, d.drop, d.e,
          d.last, d.hp))
      end
    end
  end

  local function raiseOk(e, actor)
    local maxhp = M.readWord(0x3C1C + e * 2)
    local raiseHp = (maxhp * M.itemPower(FENIX_DOWN)) >> 4
    local hit, hitSlot, hitOn = nil, nil, nil
    local lethalEta, lethalSlot, lethalPct = nil, nil, nil
    local brokenLethal = nil
    -- The action still open (its drops are committed when it closes) is
    -- read provisionally: a raise planned inside that window otherwise
    -- sees "no enemy hit measured yet" for a hit that just landed.
    -- Measured on map 269 (fix1_boostfight_s36): the recurring Flare took
    -- the pair from 405/424 at f+9681, two raises were planned at f+9993
    -- against an empty ledger, and the floor was only committed after.
    local openL = nil
    if monAct ~= nil and #monAct.drops > 0 then
      local base = hitLedger[monAct.slot] or { on = {} }
      openL = { on = {}, min = base.min, minE = base.minE }
      for k, v in pairs(base.on) do openL.on[k] = v end
      for _, d in ipairs(monAct.drops) do
        if openL.on[d.e] == nil or d.drop < openL.on[d.e] then openL.on[d.e] = d.drop end
        if openL.min == nil or d.drop < openL.min then openL.min, openL.minE = d.drop, d.e end
      end
    end
    for s = 0, 5 do
      local L = hitLedger[s]
      if openL ~= nil and s == monAct.slot then L = openL end
      if L and monAlive(s) then
        local v, on = L.on[e], e
        if v == nil then v, on = L.min, L.minE end
        if v ~= nil then
          if hit == nil or v < hit then hit, hitSlot, hitOn = v, s, on end
          if v >= raiseHp then
            if M.readByte(BRK_TICKS + s * 2) ~= 0 then
              brokenLethal = s
            else
              local eta, pct = etaOf(8 + s * 2)
              if eta ~= nil and (lethalEta == nil or eta < lethalEta) then
                lethalEta, lethalSlot, lethalPct = eta, s, pct
              end
            end
          end
        end
      end
    end
    local o = { maxhp = maxhp, power = M.itemPower(FENIX_DOWN), smallestHit = hit }
    local detail = ""
    if hit ~= nil and hit >= raiseHp then
      -- (b) a kill in reach: the last monster against the party's window
      local slot = soleTarget()
      if slot ~= nil then
        local mhp = M.readWord(MON_HP + slot * 2)
        local window, parts, broken = partyWindow(actor, slot)
        o.killInReach = window >= mhp
        detail = string.format("; kill: the last monster slot %d has %d HP%s "
          .. "against the party's window %d (%s)", slot, mhp,
          broken and ", BROKEN" or "", window, parts ~= "" and parts or "nothing measured")
      else
        detail = "; kill: not the last monster"
      end
      -- (a) a top-up first: the other members' gauges against the lethal slot's
      local topUp = (battInvIdx(POTION) and itemRestoreOf(POTION))
                 or (battInvIdx(TONIC) and itemRestoreOf(TONIC)) or 0
      local first, firstEta, firstPct = nil, nil, nil
      for p = 0, 3 do
        -- a Stopped, asleep or berserk member's gauge is not a turn the
        -- party can plan on (#187): it is left out of the top-up race
        if p ~= actor and p ~= e and M.readWord(0x3BF4 + p * 2) > 0
           and M.readWord(0x3C1C + p * 2) > 0 and denied(p) == nil then
          local eta, pct = etaOf(p * 2)
          if eta ~= nil and (first == nil or eta < firstEta) then
            first, firstEta, firstPct = p, eta, pct
          end
        end
      end
      o.topUp = topUp
      if lethalEta == nil then
        o.topUpFirst = true
        detail = detail .. string.format("; gauges: no lethal slot is due to act%s",
          brokenLethal and string.format(" (slot %d is BROKEN and skips its turns)",
            brokenLethal) or "")
      elseif first ~= nil then
        o.topUpFirst = firstEta < lethalEta
        detail = detail .. string.format("; gauges: entity %d's is %d/256 (%d ticks "
          .. "to full) against slot %d's %d/256 (%d ticks), top-up +%d", first,
          firstPct, firstEta, lethalSlot, lethalPct, lethalEta, topUp)
      else
        o.topUpFirst = false
        detail = detail .. string.format("; gauges: nobody else standing to top up "
          .. "(slot %d is %d ticks from acting)", lethalSlot, lethalEta)
      end
    end
    local _, ok, why = M.raiseDecision(o)
    return ok, raiseHp, hit, hitSlot, hitOn, why .. detail
  end

  -- battle_lore.lua's own tested fact: $306A+id reads id+$8B iff that lore
  -- id passed Ot6LoreMask's live walk this battle; otherwise whatever
  -- InitBattle's own clear left there.  id+$8B is also the lore's ability
  -- id (vanilla lore abilities are $8B..$A2), which names it in the live
  -- list below and answers for its element in the absorb guard.
  local function loreOffered(id) return M.readByte(0x306A + id) == id + 0x8B end
  -- Where a lore sits in this actor's live battle Lore list, and what the
  -- engine has priced it at -- spellCell's exact shape, one segment along.
  -- The window is NOT a compacted list: the burning-house campaign's first
  -- driver modeled a lore's row as "how many lower ids are offered", held
  -- the cursor on the wrong row, and A-tapped ~61k frames against the
  -- confirm's silent greyed-entry refusal (2026-08-27, the owner watching
  -- the reproduced stall: empty rows on screen with Aqua Rake a few rows
  -- down; scratchpad thamasa_stall_run.log ~line 4756).  The row is read
  -- from the engine instead: the lore window indexes the same per-actor
  -- spell list spellCell walks -- record 0 the esper, 1..54 the magic
  -- grid, 55..78 the lore segment the window draws in record order
  -- (DrawLoreListText / _c183f7: entry = list base + $DC + row*4) -- so
  -- the row is wherever the lore actually sits in that segment, whatever
  -- the layout.  A lore's +0 byte is its LORE id, not its ability id:
  -- InitSpellList strips the $8B ability base before the store
  -- (battle_main.asm @5651, `sbc #$8b`).  Same +1 flags (bit 7 greyed) /
  -- +3 MP record shape, same `strict` semantics as spellCell.
  local function loreCell(actor, id, strict)
    local base = M.readWord(MLISTPTR + actor * 2)
    if base < 0x2000 or base > 0x2600 then return nil end
    for row = 0, 23 do
      local a = base + (55 + row) * 4
      if M.readByte(a) == id then
        local cost = M.readByte(a + 3)
        if M.readWord(CURMP + actor * 2) < cost then return nil end
        if strict and (M.readByte(a + 1) & 0x80) ~= 0 then return nil end
        return row, cost
      end
    end
    return nil
  end
  local LORE_STALL = 600               -- pursuit frames with no landed lore
  local function loreDiagnose(actor, want)
    loreDead = true
    local sig, load, bits, seg = {}, {}, {}, {}
    for id = 0, 23 do sig[#sig + 1] = string.format("%02X", M.readByte(0x306A + id)) end
    for i = 0, 4 do load[#load + 1] = string.format("%02X", M.readByte(0x1E27 + i)) end
    for i = 0, 2 do bits[#bits + 1] = string.format("%02X", M.readByte(0x1D29 + i)) end
    local base = M.readWord(MLISTPTR + actor * 2)
    for row = 0, 23 do
      seg[#seg + 1] = string.format("%02X/%02X",
        M.readByte(base + (55 + row) * 4), M.readByte(base + (55 + row) * 4 + 1))
    end
    M.log(string.format("[%s] LORE STALLED %d frames with no landed cast -- "
      .. "dumping the lore state and falling through to Fight: count $3A87=%d "
      .. "sig $306A+0..23=%s loadout $1E27+0..4=%s learned $1D29-2B=%s "
      .. "cursor $891F+$8927(+%d)=%d+%d want-row=%s segment(id/flags)=%s",
      tag or "fight", loreSpinN,
      M.readByte(0x3A87), table.concat(sig, " "), table.concat(load, " "),
      table.concat(bits, " "), actor, M.readByte(LSCROLL + actor),
      M.readByte(LROW + actor), tostring(want), table.concat(seg, " ")))
  end

  -- The nuke MP floor: a nuke is refused when paying for it would leave
  -- the caster under a quarter of max MP (opts.nukeFloor overrides, in
  -- absolute MP).  The tail of the bar is owed to the cure line, which
  -- runs first every turn but only spends when somebody is hurt; a
  -- repertoire that drained to zero would take the healer's MP with it.
  local function nukeFloor(actor)
    return opts.nukeFloor or (M.readWord(MAXMP + actor * 2) // 4)
  end

  local function makePlan(actor)
    -- What a round costs this party, measured rather than assumed.  For each
    -- entity, the most HP it has lost between two consecutive turns of the
    -- actor now deciding: that is the damage that will land before this actor
    -- can act again, which is the number any heal has to beat.  It is zero
    -- until the enemy has actually taken a round, which is what makes the
    -- opening turn fall through to the fraction rule below.
    local hpNow = {}
    for e = 0, 3 do hpNow[e] = M.readWord(0x3BF4 + e * 2) end
    if turnSnap[actor] then
      for e = 0, 3 do
        local lost = turnSnap[actor][e] - hpNow[e]
        if lost > (roundCost[e] or 0) then roundCost[e] = lost end
      end
    end
    -- Before this actor's second turn there is no per-turn sample, but the
    -- HP lost since the battle opened is a floor on what a round costs:
    -- the dadaluma wipe priced a Potion at 'a round costs 0 (top-up)' on
    -- turn two while every ally had already lost ~250 to the opening move.
    if startSnap ~= nil and not turnSnap[actor] then
      for e = 0, 3 do
        local lost = startSnap[e] - hpNow[e]
        if lost > (roundCost[e] or 0) then roundCost[e] = lost end
      end
    end
    turnSnap[actor] = hpNow
    -- The price every care line below reads (#206, #194): what one enemy
    -- round costs each member before their next turn, off the gauges and
    -- the hit ledger (M.roundCost).  The measured inter-turn loss above
    -- stays the price only while the ledger has nothing attributed yet
    -- (the opening move, damage no monster action owns).
    local price, priceWhy, priceRate = {}, {}, {}
    do
      local fallback, any = nil, false
      for s2 = 0, 5 do
        local L = hitLedger[s2]
        if L and L.max then
          any = true
          if fallback == nil or L.max > fallback then fallback = L.max end
        end
      end
      -- the action still open is read provisionally, as the raise gate does
      local open = {}
      if monAct ~= nil then
        for _, d in ipairs(monAct.drops) do open[d.e] = (open[d.e] or 0) + d.drop end
        for _, v in pairs(open) do
          any = true
          if fallback == nil or v > fallback then fallback = v end
        end
      end
      for e = 0, 3 do
        if hpNow[e] > 0 and hpNow[e] ~= 0xFFFF and M.readWord(0x3C1C + e * 2) > 0 then
          if not any then
            price[e] = roundCost[e] or 0
            priceWhy[e] = "no enemy action attributed yet: the measured inter-turn loss"
          else
            local const = M.readWord(ATB_CONST + e * 2)
            local eta = etaOf(e * 2)
            local period = const > 0 and math.ceil(0xFF00 / const) or nil
            local window = (eta == 0 or eta == nil) and period or eta
            local enemies = {}
            for s2 = 0, 5 do
              if monAlive(s2) then
                local L = hitLedger[s2]
                local worst = L and L.maxOn and L.maxOn[e] or (L and L.max) or nil
                if monAct ~= nil and monAct.slot == s2 then
                  local v = open[e]
                  if v == nil then for _, w in pairs(open) do if v == nil or w > v then v = w end end end
                  if v ~= nil and (worst == nil or v > worst) then worst = v end
                end
                local mconst = M.readWord(ATB_CONST + 8 + s2 * 2)
                enemies[#enemies + 1] = { slot = s2, eta = etaOf(8 + s2 * 2),
                  period = mconst > 0 and math.ceil(0xFF00 / mconst) or nil, worst = worst }
              end
            end
            if window == nil then
              price[e], priceWhy[e] = roundCost[e] or 0,
                "the member's gauge cannot fill: the measured inter-turn loss"
            else
              local c, _, why, rate = M.roundCost({ window = window, enemies = enemies,
                fallback = fallback })
              price[e], priceWhy[e], priceRate[e] = c, why, rate
            end
          end
        else
          price[e], priceWhy[e] = 0, "down"
        end
      end
    end
    -- said once per change, beside the old measured figure, for the log
    for e = 0, 3 do
      if price[e] > 0 or (roundCost[e] or 0) > 0 then
        local said = string.format("entity %d: a round costs %d (%s; measured "
          .. "inter-turn worst %d)", e, price[e], priceWhy[e], roundCost[e] or 0)
        local key = (said:gsub(" inside %d+ ticks", ""):gsub(" %[[^%]]*%]", ""))
        if priceSaid[e] ~= key then
          priceSaid[e] = key
          M.log(string.format("[%s] [round] actor=%d deciding: %s", tag or "fight", actor, said))
        end
      end
    end
    -- The Muddle rule (#170, M.muddleRule), before every other line: a
    -- muddled actor defers (X) rather than confirm a command the engine
    -- will re-aim -- measured from n024_entry, muddled SABIN's own
    -- Fights, Suplex and Fire Dance all landed on the party and wiped it
    -- -- and a muddled living ally gets a plain unboosted Fight, which
    -- clears the status (CalcMaxDmg strips it from a physically damaged
    -- target; a Remedy does not carry the bit, M.itemStatus2).
    do
      local s2, mx = {}, {}
      for e = 0, 3 do
        s2[e] = M.readByte(ST2 + e * 2)
        mx[e] = M.readWord(0x3C1C + e * 2)
      end
      local r = M.muddleRule({ actor = actor, status2 = s2, hp = hpNow, maxhp = mx })
      if r == "defer" then
        local said = string.format("[%s] actor=%d is MUDDLED (STATUS2 $%02X) -- "
          .. "not planning: its command would be re-aimed by the engine; "
          .. "deferring the window (X)", tag or "fight", actor, s2[actor])
        if said ~= healSaid then healSaid = said; M.log(said) end
        return { kind = "defer" }
      end
      if r ~= nil and r ~= "defer" and unmuddlePending and unmuddlePending.e == r
         and battleTick - unmuddlePending.tick <= RAISE_WAIT then
        local said = string.format("[%s] actor=%d: entity %d is MUDDLED but actor %d's "
          .. "hit on it (confirmed at tick %d) is still in the air -- planning "
          .. "normally rather than land a second one", tag or "fight", actor, r,
          unmuddlePending.by, unmuddlePending.tick)
        if said ~= healSaid then healSaid = said; M.log(said) end
        r = nil
      end
      local fight = r ~= nil and cmdRow(actor, CMD_FIGHT) or nil
      if fight ~= nil then
        healSaid = nil
        M.log(string.format("[%s] actor=%d: entity %d (%d/%d) is MUDDLED (STATUS2 "
          .. "$%02X) -- a plain unboosted Fight on the ally clears it; before "
          .. "any other plan", tag or "fight", actor, r, hpNow[r], mx[r], s2[r]))
        return { kind = "fight", row = fight, boostLeft = 0, target = r,
                 ally = true, reason = "unmuddle" }
      end
    end
    -- The status cure line (#187), after the Muddle rule and before any
    -- heal: an imp's Fight lands for 0 and its Magic keeps only Imp, so
    -- a turn that cures it is worth more than the turn it spends -- the
    -- imp's own first (its attack is worthless anyway, and an imp keeps
    -- its Item row: BattleCmdProp $01 carries the IMP flag), then a
    -- living ally's.  The item comes from the ROM's records through
    -- M.statusCure (Green Cherry, then Remedy); with nothing in the bag
    -- that carries the bit the refusal is said once and the actor plans
    -- on.  Berserk goes through the same gate and, in this ROM, always
    -- lands on "none in the bag" (Remedy's STATUS2 byte is $48).  A cure
    -- is care: it takes the round's care turn when the budget is open,
    -- and the imp's self-cure goes regardless, since the alternative is
    -- a zero.
    if parkDropN < 3 and cmdRow(actor, CMD_ITEM) ~= nil and opts.items ~= false then
      local order = { actor }
      for e = 0, 3 do if e ~= actor then order[#order + 1] = e end end
      for _, e in ipairs(order) do
        if hpNow[e] > 0 and M.readWord(0x3C1C + e * 2) > 0 then
          local item, what = cureFor(e)
          local queued = cureQueued[e]
          if what ~= nil and queued ~= nil then
            local said = string.format("[%s] actor=%d no cure on entity %d: actor %d's "
              .. "$%02X on them is confirmed (tick %d) and has not landed",
              tag or "fight", actor, e, queued.by, queued.item, queued.tick)
            if said ~= cureSaid then cureSaid = said; M.log(said) end
          elseif what ~= nil then
            local open = e == actor or careActor == nil or careActor == actor
                      or hpNow[careActor] == 0 or denied(careActor) ~= nil
            if item ~= nil and open then
              M.log(string.format("[%s] actor=%d cure entity %d's %s with $%02X "
                .. "(%d in the bag): %s", tag or "fight", actor, e, what, item,
                bagCount(item), e == actor and "its own turn is worth nothing as "
                .. "it stands" or "an ally's turn is worth nothing as it stands"))
              return { kind = "item", item = item, target = e,
                       row = cmdRow(actor, CMD_ITEM), idx = battInvIdx(item),
                       reason = "cure " .. what }
            end
            local said = item == nil
              and string.format("[%s] actor=%d: entity %d is %s and nothing in "
                .. "the bag carries the bit (Green Cherry %d, Remedy %d) -- no "
                .. "cure to plan; planning on", tag or "fight", actor, e,
                what == "Imp" and "an IMP" or "BERSERK", bagCount(M.GREEN_CHERRY),
                bagCount(M.REMEDY))
              or string.format("[%s] actor=%d: entity %d's %s cure ($%02X) waits for "
                .. "the round's care turn (actor %d's)", tag or "fight", actor, e,
                what, item, careActor)
            if said ~= cureSaid then cureSaid = said; M.log(said) end
          end
        end
      end
    end
    -- opts.healer = <battle chid>: only that character runs the item
    -- healing line; everyone else attacks.  Without this, a party whose
    -- only damage-dealer also heals can heal-lock: it never attacks, the
    -- monster never dies, and the bag drains to a wipe.
    local mayHeal = opts.healer == nil
        or M.readByte(BCHID + actor * 2) == opts.healer
    -- A dead healer must not lock the party out of its own bag.  When the
    -- healer is down -- or not in this fight at all -- whoever holds the
    -- row inherits the job; the revive loop below raises the dead in
    -- entity order (the healer among them), and the role returns to its
    -- owner on their next living turn.
    if not mayHeal then
      local healerAlive = false
      for e = 0, 3 do
        if M.readByte(BCHID + e * 2) == opts.healer
           and M.readWord(0x3BF4 + e * 2) > 0 then
          healerAlive = true
          break
        end
      end
      if not healerAlive then mayHeal = true end
    end
    local row = (opts.items and mayHeal) and cmdRow(actor, CMD_ITEM) or nil
    -- opts.cure = false turns the cast line off and leaves healing to the
    -- bag.  Anything else is the list of cure spells to try, cheapest
    -- first, defaulting to CURES.
    --
    -- Casting comes first: OT6 refunds MP in full at every level up and
    -- never refunds a Tonic, and a segment can run several fights with no
    -- field access between them, so the bag is a fixed supply while MP is
    -- only bounded per fight.
    --
    -- The option is named `cure` rather than `magic` only because this
    -- driver already spends `opts.magic` on the attack line below.
    local cureRow = mayHeal and opts.cure ~= false
        and cmdRow(actor, CMD_MAGIC) or nil
    -- The finisher rule: with the fight one poke from over, healing is
    -- the wrong verb no matter how hurt anyone is.  The Sealed-Gate wipe
    -- died with the last Ninja at 61 HP while three straight turns went
    -- to item menus and its parting move erased the party; any attack
    -- would have ended the danger instead.
    local totalMon = 0
    for s = 0, 5 do totalMon = totalMon + M.readWord(0x3BFC + s * 2) end
    -- The park ratchet: three watchdog drops in one battle means the
    -- steer cannot land its plans (a greyed confirm, a moved row), and
    -- replanning the same care loops forever -- the plains grind hung
    -- 37000 frames in a park->drop->replan cycle.  A person whose item
    -- confirm keeps buzzing stops shopping and Fights; so does this.
    if parkDropN >= 3 and healSaid ~= "parked-out" then
      healSaid = "parked-out"
      M.log(string.format("[%s] %d park-drops this battle -- care and "
        .. "skill plans are off for the rest of the fight; Fighting instead",
        tag or "fight", parkDropN))
    end
    -- One care action per round (owner guideline: one healer inside, and
    -- the strong form once).  The caring actor's next turn delimits the
    -- round; until then everyone else attacks, because the fastest way to
    -- stop the damage is to end the fight.  The dadaluma wipe spent all
    -- four turns of every round on heals, revives and item parks against
    -- a 392-HP monster that one attacking round would have killed, and it
    -- never landed a single blow.  A caring actor who has since died
    -- reopens the budget.
    -- A caring actor who has since been Stopped, put to sleep or
    -- berserked (#187) has no next turn to delimit the round with, so the
    -- budget reopens for them too, the way it does for a dead one.
    local careOpen = careActor == nil or careActor == actor
                  or hpNow[careActor] == 0 or denied(careActor) ~= nil
    -- A raise followed by another actor's Potion in the same window is
    -- care, not two care turns (#168): a member the raise just put at
    -- maxhp/8 (topUpOwed) reopens the budget for their top-up.
    if not careOpen then
      for e = 0, 3 do
        local maxhp = M.readWord(0x3C1C + e * 2)
        if topUpOwed[e] and hpNow[e] > 0 and maxhp > 0
           and hpNow[e] * 100 // maxhp < (opts.healPercent or 60) then
          careOpen = true
          local said = string.format("[%s] actor=%d: entity %d was raised to %d/%d "
            .. "at tick %d and is owed its top-up -- the round's care budget "
            .. "(actor %d's) reopens for it", tag or "fight", actor, e, hpNow[e],
            maxhp, topUpOwed[e], careActor)
          if said ~= healSaid then healSaid = said; M.log(said) end
          break
        end
      end
    end
    if (row ~= nil or cureRow ~= nil) and totalMon > 200 and parkDropN < 3
       and not careOpen then
      local said = string.format("[%s] actor=%d: this round's care turn "
        .. "went to actor %d -- attacking", tag or "fight", actor, careActor)
      if said ~= healSaid then healSaid = said; M.log(said) end
    end
    -- The boost bank, read here because the press rule spends it.  Spending
    -- one BP as soon as it is available plays OT6's economy badly: damage
    -- while a monster still has shields is halved, with ratios
    -- broken:weak:unweak = 4:2:1, so the intended play is to boost until
    -- the shield breaks and then hit.  opts.bank means: act unboosted,
    -- which regenerates BP, until the bank reads at least this value,
    -- then spend.
    local have = M.readByte(BP + actor * 2)
    local boost = 0
    if opts.boost then
      if opts.bank and have < opts.bank then boost = 0
      else boost = math.min(have, 3) end
    end
    -- This actor's strongest unreflectable line against `slot` by the
    -- chip model, at `bp` boost: the tool first so a tie keeps the
    -- driver's own order, then the blitz, then the Fight.  Shared by the
    -- press rule (#156, #165) and the spend rule (#175) below.
    local function bestLine(actor, slot, bp)
      local id = M.readByte(BCHID + actor * 2)
      local best = nil
      local function offer(p) if best == nil or p.chips > best.chips then best = p end end
      local tool = opts.tool or AUTOCROSSBOW
      if opts.tactical and opts.tools ~= false and id == 4
         and M.readWord(CURMP + actor * 2) >= 4 and cmdRow(actor, CMD_TOOLS)
         and battInvIdx(tool) then
        offer({ kind = "skill", cmd = CMD_TOOLS, skill = tool,
                row = cmdRow(actor, CMD_TOOLS), boostLeft = bp,
                chips = toolChips(slot, tool), hits = TOOL_HITS[tool] or 1,
                what = string.format("Tools $%02X", tool) })
      end
      if opts.tactical and id == 5 and (opts.blitz or PUMMEL) == PUMMEL
         and M.readWord(CURMP + actor * 2) >= 4 and cmdRow(actor, CMD_BLITZ) then
        offer({ kind = "skill", cmd = CMD_BLITZ, skill = PUMMEL,
                row = cmdRow(actor, CMD_BLITZ), boostLeft = bp,
                chips = 2 * hitChips(slot, 0x04, 0), hits = 2, what = "Pummel" })
      end
      local fight = cmdRow(actor, CMD_FIGHT)
      if fight ~= nil then
        local _, l = handsOf(actor)
        local mainSw, offSw = M.fightSwings(l ~= nil, bp)
        offer({ kind = "fight", row = fight, boostLeft = bp,
                chips = fightChips(actor, slot, bp), hits = mainSw + offSw,
                what = string.format("Fight at %d BP", bp) })
      end
      return best
    end
    -- The spend rule (#175): this actor inside one round of death, holding
    -- BP, with no heal in hand that lifts them clear of the round, spends
    -- every pip now on their strongest line instead of a heal that only
    -- delays (M.spendDecision).  Asked after the press rule (a kill this
    -- turn is better still) and before the raise and the heals, and again
    -- ahead of the attack lines when the care block is closed to this
    -- actor, so a bank policy cannot hold the pips either.  The line is
    -- the chip model's (bestLine); with nothing to chip, the once-a-battle
    -- summon is the strongest unreflectable, unabsorbed line and goes
    -- first when it is available.  Measured on Rizopas care_i50 (#162):
    -- SABIN at 82/363 under a 244 round spent eleven turns on care while
    -- one 1-BP Fight ended the fight.
    local function spendPlan(where)
      if opts.spend == false or livingMonsters() == 0 then return nil end
      local hp, maxhp = hpNow[actor], M.readWord(0x3C1C + actor * 2)
      local cost = price[actor] or 0
      if hp <= 0 or cost <= 0 or hp > cost or have < 1 then return nil end
      -- the heals this actor could give themself right now, priced the
      -- way the care lines below price them.  Only a heal those lines
      -- would TAKE can save (#206): the Potion that "saves: 17 + 250 = 267
      -- survives the 262 round" was the same Potion the heal policy
      -- refused as "buys back less than it spends", so LOCKE did neither
      -- and died holding 3 BP.  From the attack lines (the care block
      -- closed to this actor, or it declined every heal) no heal is
      -- coming this turn at all.
      local heals = {}
      if where == "care" then
        local allies = 0
        for e = 0, 3 do
          if e ~= actor and hpNow[e] > 0 and M.readWord(0x3C1C + e * 2) > 0 then
            allies = allies + 1
          end
        end
        local function taken(restore, mp)
          return restore == nil or M.healDecision({ hp = hp, maxhp = maxhp,
            restore = restore, roundCost = cost, allies = allies,
            threshold = opts.healPercent or 60, mp = mp }) ~= nil
        end
        if cureRow ~= nil then
          for _, spell in ipairs(type(opts.cure) == "table" and opts.cure or CURES) do
            if spellCell(actor, spell, true) and taken(castRestore[spell], true) then
              heals[#heals + 1] = { what = string.format("cure $%02X", spell),
                                    restore = castRestore[spell] }
            end
          end
        end
        if row ~= nil then
          local item = (battInvIdx(POTION) and POTION) or (battInvIdx(TONIC) and TONIC)
          if item and taken(itemRestoreOf(item), false) then
            heals[#heals + 1] = { what = string.format("item $%02X", item),
                                  restore = itemRestoreOf(item) }
          end
        end
      end
      local verdict, why = M.spendDecision({ hp = hp, maxhp = maxhp, roundCost = cost,
                                             bp = have, heals = heals })
      if verdict ~= "spend" then
        local said = string.format("[%s] actor=%d no spend (%s): %s", tag or "fight",
          actor, where, why)
        if said ~= healSaid then healSaid = said; M.log(said) end
        return nil
      end
      local slot = pressTarget()
      if slot == nil then
        for s = 0, 5 do if monAlive(s) then slot = s; break end end
      end
      local best = slot ~= nil and bestLine(actor, slot, have) or nil
      -- the summon: unreflectable and unabsorbed by construction (the
      -- summon line's own gates), and the strongest thing a caster with
      -- nothing to chip can do with the turn
      local id = M.readByte(BCHID + actor * 2)
      local sm = opts.summon and opts.summon[id]
      if sm and (best == nil or best.chips == 0) then
        local mrow = cmdRow(actor, CMD_MAGIC)
        local used = M.readWord(0x3f2e) & M.readWord(0x3018 + actor * 2)
        local stone = M.readByte(0x3344 + actor * 2)
        if M.readWord(CURMP + actor * 2) >= (sm.mp or 50) and used == 0 and mrow
           and stone ~= 0xFF then
          healSaid = nil
          M.log(string.format("[%s] actor=%d SPEND (%s): %s -- the summon (esper $%02X) "
            .. "rather than die holding boost (#175)", tag or "fight", actor, where, why, stone))
          return { kind = "summon", row = mrow, reason = "spend" }
        end
      end
      if best == nil then
        local fight = cmdRow(actor, CMD_FIGHT)
        if fight == nil then return nil end
        best = { kind = "fight", row = fight, boostLeft = have, chips = 0,
                 what = string.format("Fight at %d BP", have) }
      end
      best.reason = "spend"
      healSaid = nil
      M.log(string.format("[%s] actor=%d SPEND (%s): %s -- %s (%d chip(s) on slot %s) "
        .. "rather than die holding boost (#175)", tag or "fight", actor, where, why,
        best.what, best.chips or 0, tostring(slot)))
      return best
    end
    -- The finisher gate yields to the enemy's arithmetic (#204).  "Under
    -- 200 total, attack" was written for a party one poke from ending a
    -- fight; for solo L12 LOCKE against the 495-HP gate soldier, whose
    -- shields re-seed to 3 inside that window, the last 200 HP was three
    -- chips and an unload away -- four more enemy actions -- and every
    -- baseline loss (docs/design/sfigaro-gate.md; the 15-seed lab, seeds
    -- 24/40/52) was him at 134-142/279 planning a 0-BP chip with a Potion
    -- in the bag, killed by the fight's first TekLaser.  The measured
    -- round cost there read 58-110: not "inside one round", but inside
    -- the four the kill still needed.  So the window closes the care block
    -- only while the fight ends before the damage does: it stays closed
    -- when no member is inside the rounds the kill still needs, priced by
    -- the press rule's own arithmetic (this actor's chips against the
    -- shields up, the party's measured broken window against the HP
    -- left, or this actor chipping it down at the per-hit figure) at the
    -- round cost measured on that member -- and opens otherwise, handing
    -- the press rule the kill-this-turn decision it already makes ahead
    -- of the care (#165).  A member inside one measured round is the
    -- one-round case of the same rule and opens it whatever the estimate.
    -- Nothing here reads hidden state: shields, HP and the damage watch
    -- are what the screen shows.
    local function finisherYields()
      local rounds, arith = nil, nil
      local slot = pressTarget()
      if slot ~= nil then
        local left = livingMonsters() > 1 and totalMon or M.readWord(MON_HP + slot * 2)
        local sh = M.readByte(SH_CUR + slot * 2)
        local broken = M.readByte(BRK_TICKS + slot * 2) ~= 0
        local need = broken and 0 or sh
        local best = bestLine(actor, slot, have)
        local chips = best and best.chips or 0
        local window = 0
        for e = 0, 3 do
          if hpNow[e] > 0 and dmgSeen[e] then window = window + dmgSeen[e] * 4 end
        end
        if need == 0 or chips > 0 then
          local toBreak = need == 0 and 0 or math.ceil(need / chips)
          if window > 0 then
            local unload = math.ceil(left / window)
            rounds = toBreak + unload
            arith = string.format("%d to chip %d shield(s) at %d a turn + %d to "
              .. "unload %d HP at %d a broken round", toBreak, need, chips, unload,
              left, window)
          end
          local dh = dmgHit[actor]
          if best ~= nil and dh ~= nil and dh.kind == best.kind
             and (best.kind ~= "skill" or dh.skill == best.skill) and dh.per > 0 then
            local perTurn = dh.per * (best.hits or 1)
            local chipRounds = math.ceil(left / perTurn)
            if rounds == nil or chipRounds < rounds then
              rounds = chipRounds
              arith = string.format("%d chipping %d HP down at %d a turn (%s)",
                chipRounds, left, perTurn, best.what)
            end
          end
        end
      end
      for e = 0, 3 do
        local hp, maxhp = hpNow[e], M.readWord(0x3C1C + e * 2)
        local cost = price[e] or 0
        if hp > 0 and maxhp > 0 and hp < maxhp and (cost > 0 or (priceRate[e] or 0) > 0) then
          if cost > 0 and hp <= cost then
            return string.format("entity %d (%d/%d) is inside one round of death "
              .. "(%d)", e, hp, maxhp, cost)
          end
          -- several rounds are priced at the steady rate, the next one
          -- at the window price (M.roundCost)
          local each = math.max(cost, priceRate[e] or 0)
          if rounds ~= nil and rounds > 1 and hp <= rounds * each then
            return string.format("entity %d (%d/%d) is inside the %d round(s) the "
              .. "kill still needs (%s) at %d a round = %d", e, hp, maxhp, rounds,
              arith, each, rounds * each)
          end
        end
      end
      return nil
    end
    local finisher = totalMon <= 200
    local yieldWhy = nil
    if finisher and (row ~= nil or cureRow ~= nil) and parkDropN < 3 and careOpen then
      yieldWhy = finisherYields()
      if yieldWhy ~= nil then
        local said = string.format("[%s] actor=%d: the finisher window (monsters at "
          .. "%d HP <= 200) yields -- %s; the care block opens and the press rule "
          .. "decides a kill this turn against the care (#204)", tag or "fight",
          actor, totalMon, yieldWhy)
        if said ~= finisherSaid then finisherSaid = said; M.log(said) end
      end
    end
    if (row ~= nil or cureRow ~= nil) and (not finisher or yieldWhy ~= nil)
       and parkDropN < 3 and careOpen then
      -- The press rule (#156), the finisher rule's sibling: when this
      -- actor's best unreflectable action chips the target's remaining
      -- shields to zero this turn AND the party's measured damage in the
      -- broken window covers the HP left, the fight is one break from
      -- over and the actor attacks rather than heals -- unless somebody is
      -- inside one round of death, when the lethal-next-round heal rule
      -- still comes first.  The cure-MP reserve is untouched; a press
      -- spends BP, not MP.  The chips come from the revealed weaknesses
      -- and the pips (the HUD); the HP left is read the way the finisher
      -- rule reads totalMon.  Measured on Nerapa: with the party at
      -- Potion-and-Fenix turns against a 3-pip, 1653-HP gauge, every care
      -- turn bought less than a round cost while LOCKE's six-chip Fight
      -- would have opened the window.
      local press, pressWhy = (function()
        if opts.press == false then return nil end
        -- A press is the heal-or-attack choice, so it is only asked when
        -- there is a heal to skip: a downed member the bag can raise (and
        -- the raise rule below would let stand), or a candidate the
        -- fraction / one-round-of-death rules below would offer a heal
        -- to.  With nobody to care for, the attack lines below (summon,
        -- nuke, tool, the boost bank) keep their own order.
        local needsCare = false
        local threshold = opts.healPercent or 60
        for e = 0, 3 do
          local hp, maxhp = hpNow[e], M.readWord(0x3C1C + e * 2)
          if maxhp > 0 and hp == 0 and row ~= nil and battInvIdx(FENIX_DOWN)
             and raiseOk(e, actor) then
            needsCare = true
          elseif hp > 0 and maxhp > 0 and hp < maxhp
             and (hp * 100 // maxhp < threshold or hp <= (price[e] or 0)) then
            needsCare = true
          end
        end
        if not needsCare then return nil end
        local slot = pressTarget()
        if slot == nil then return nil end
        -- Somebody inside one round of death: the lethal-next-round heal
        -- rule keeps its priority over a press that merely opens the
        -- window -- UNLESS the press ends the fight this turn (#165,
        -- below): the kill removes the threat now, a heal only delays it.
        local lethal = nil
        for e = 0, 3 do
          local hp, maxhp = hpNow[e], M.readWord(0x3C1C + e * 2)
          if hp > 0 and hp < maxhp and hp <= (price[e] or 0) then
            lethal = e
            break
          end
        end
        local sh = M.readByte(SH_CUR + slot * 2)
        local broken = M.readByte(BRK_TICKS + slot * 2) ~= 0
        local need = broken and 0 or sh
        -- the strongest unreflectable line by chips, at full boost (the
        -- swings past the break land x4): the tool first so a tie keeps
        -- the driver's own order, then the blitz, then the Fight
        local best = bestLine(actor, slot, have)
        if best == nil then return nil end
        if best.chips < need then
          if lethal ~= nil then
            return nil, string.format("[%s] actor=%d no press: entity %d "
              .. "(%d/%d) is inside one round of death (%d) and %s lands %d "
              .. "chip(s) against %d shield(s) on slot %d -- caring first",
              tag or "fight", actor, lethal, hpNow[lethal],
              M.readWord(0x3C1C + lethal * 2), price[lethal], best.what,
              best.chips, need, slot)
          end
          return nil, string.format("[%s] actor=%d no press: %s lands %d "
            .. "chip(s) against %d shield(s) on slot %d -- caring",
            tag or "fight", actor, best.what, best.chips, need, slot)
        end
        local hp = M.readWord(MON_HP + slot * 2)
        -- The kill-this-turn estimate (#165): this actor's own action,
        -- priced per hit from what its last action of the same kind
        -- landed (dmgHit), the hits up to the last chip shielded and the
        -- rest broken (M.killEstimate).  It ends the fight only when the
        -- target is the last monster standing.
        local dh = dmgHit[actor]
        local est, toBreak, brokenN, estWhy = nil, 0, 0, nil
        if dh == nil or dh.kind ~= best.kind
           or (best.kind == "skill" and dh.skill ~= best.skill) then
          estWhy = string.format("%s has no per-hit figure yet", best.what)
        else
          est, toBreak, brokenN = M.killEstimate({ per = dh.per, hits = best.hits,
                                                    chips = best.chips, need = need })
          if est == nil then
            estWhy = string.format("%s cannot be priced (%d a hit, %d hit(s))",
              best.what, dh.per, best.hits)
          else
            estWhy = string.format("%s is expected to deal %d (%d hit(s): %d "
              .. "shielded then %d broken at %d a hit)", best.what, est,
              best.hits, toBreak, brokenN, dh.per)
          end
        end
        local last = livingMonsters() == 1
        if est ~= nil and est >= hp and last then
          best.reason = "press"
          M.log(string.format("[%s] actor=%d PRESS: slot %d (%d HP, %s) is the "
            .. "last monster and %s -- a kill this turn%s; attacking instead "
            .. "of caring (ending the fight is the strongest heal)",
            tag or "fight", actor, slot, hp,
            broken and "BROKEN" or (sh .. " shield(s) up"), estWhy,
            lethal ~= nil and string.format(", with entity %d (%d/%d) inside "
              .. "one round of death (%d)", lethal, hpNow[lethal],
              M.readWord(0x3C1C + lethal * 2), price[lethal]) or ""))
          return best
        end
        if lethal ~= nil then
          return nil, string.format("[%s] actor=%d no press: entity %d "
            .. "(%d/%d) is inside one round of death (%d) and %s would %s "
            .. "slot %d but not kill it (%s%s) -- caring first",
            tag or "fight", actor, lethal, hpNow[lethal],
            M.readWord(0x3C1C + lethal * 2), price[lethal], best.what,
            broken and "hit broken" or ("chip " .. best.chips .. " of " .. need),
            slot, estWhy, last and "" or "; not the last monster")
        end
        local window, parts = 0, {}
        for e = 0, 3 do
          if hpNow[e] > 0 and dmgSeen[e] then
            -- the breaker's own swings land shielded until the last chip;
            -- everyone else's turn in the window is x4 shielded
            local mult = (e == actor and not broken) and 1 or 4
            window = window + dmgSeen[e] * mult
            parts[#parts + 1] = string.format("e%d:%dx%d", e, dmgSeen[e], mult)
          end
        end
        if window < hp then
          return nil, string.format("[%s] actor=%d no press: %s would %s "
            .. "slot %d but the window's damage %d (%s) is short of its %d HP "
            .. "-- caring", tag or "fight", actor, best.what,
            broken and "hit broken" or ("chip " .. best.chips .. " of " .. need),
            slot, window, table.concat(parts, " "), hp)
        end
        best.reason = "press"
        M.log(string.format("[%s] actor=%d PRESS: slot %d %s, %s lands %d "
          .. "chip(s); the window's damage %d (%s) covers its %d HP -- "
          .. "attacking instead of caring", tag or "fight", actor, slot,
          broken and "is BROKEN" or (sh .. " shield(s) up"), best.what,
          best.chips, window, table.concat(parts, " "), hp))
        return best
      end)()
      if press then
        healSaid = nil
        return press
      end
      if pressWhy and pressWhy ~= healSaid then healSaid = pressWhy; M.log(pressWhy) end
      -- no kill this turn: a dying actor with pips spends them before any
      -- raise or heal that only delays (#175)
      local spend = spendPlan("care")
      if spend then return spend end
      -- Revival stays item-only.  Life ($33) is not on any route this
      -- library drives yet: no esper in the WoB grants it (genju_prop.asm)
      -- and only Terra and Celes learn it innately, so a cast branch here
      -- would be a branch nothing has ever taken.
      --
      -- No raise into a certain re-kill (#165, refined #168): the Fenix
      -- Down puts the member at maxhp/8, and if the living enemy's
      -- smallest hit this fight is at least that, the next action lands
      -- them back at 0 (Rizopas seed $64: four Fenix Downs to 44 HP, four
      -- Battles of -44) -- UNLESS an ally's gauge fills first and their
      -- Potion lifts the raise clear of the hit, or the kill is in reach
      -- (raiseOk measures both; M.raiseDecision decides).  Otherwise the
      -- kill line, or a heal on the living, is preferred and the fallen
      -- are raised when the enemy is dead (fieldCare).
      if row ~= nil then
        for e = 0, 3 do
          local queued = raiseQueued[e]
          if queued and queued.by ~= actor then
            local said = string.format("[%s] actor=%d no raise on entity %d: actor %d's "
              .. "Fenix Down on them is confirmed (tick %d) and has not landed", tag or "fight",
              actor, e, queued.by, queued.tick)
            if said ~= healSaid then healSaid = said; M.log(said) end
          elseif M.readWord(0x3C1C + e * 2) > 0 and M.readWord(0x3BF4 + e * 2) == 0
             and battInvIdx(FENIX_DOWN) then
            local ok, raiseHp, hit, hitSlot, hitOn, why = raiseOk(e, actor)
            local hitStr = hit and string.format("%d (slot %d on entity %d)", hit, hitSlot, hitOn)
              or "none measured"
            if ok then
              M.log(string.format("[%s] actor=%d revive entity %d with Fenix Down: "
                .. "raise to %d HP (1/8 of %d), the living enemy's smallest hit %s "
                .. "-- %s", tag or "fight", actor, e, raiseHp,
                M.readWord(0x3C1C + e * 2), hitStr, why))
              return { kind = "item", item = FENIX_DOWN, target = e, row = row,
                       idx = battInvIdx(FENIX_DOWN), reason = "revive" }
            end
            local said = string.format("[%s] actor=%d no raise: Fenix Down would put "
              .. "entity %d at %d HP (1/8 of %d), the living enemy's smallest hit %s "
              .. "-- %s; killing first, caring for the living instead",
              tag or "fight", actor, e, raiseHp, M.readWord(0x3C1C + e * 2),
              hitStr, why)
            if said ~= healSaid then healSaid = said; M.log(said) end
          end
        end
      end
      -- Whom to heal, with what, and whether it is worth the turn it costs.
      -- M.healDecision is the policy and carries its reasoning; this is the
      -- part that reads the fight.  A candidate is anyone hurt enough to top
      -- up or standing inside one round of death, neediest first, and each is
      -- offered a cast before the bag for the reasons at opts.cure above.
      -- The first offer the policy says yes to gets the turn.
      local threshold = opts.healPercent or 60
      local cands = {}
      -- The free round (#186): under a preemptive strike the party's
      -- gauges opened full and the monsters' empty, so until the first
      -- monster action closes nobody can be hit back, and a round cost
      -- of 0 is the free round's arithmetic rather than "the enemy is
      -- harmless".  The raises above stand (a Fenix Down nobody can
      -- answer is the best one there is); a top-up on somebody standing
      -- is deferred one turn for an attack that shortens the fight,
      -- since the heal costs the same turn after the free round and the
      -- damage the enemy will do is unmeasured either way.  A lever, not
      -- a law: opts.freeRound = "care" keeps the top-ups.
      -- "no monster has acted" is the exec observer's word (no monster
      -- command has entered ExecCmd or returned), not the hit ledger's: a
      -- first action that misses would leave the ledger empty
      local freeRound = layout ~= nil and layout.preemptive
                    and execMon == nil and execMonDone == nil
                    and opts.freeRound ~= "care"
      if freeRound and not freeRoundSaid then
        freeRoundSaid = true
        M.log(string.format("[%s] actor=%d: the preemptive strike's free round -- "
          .. "no monster has acted yet, so top-ups wait one turn for an attack "
          .. "(raises still go; opts.freeRound=\"care\" keeps the top-ups)",
          tag or "fight", actor))
      end
      for e = 0, 3 do
        local hp, maxhp = hpNow[e], M.readWord(0x3C1C + e * 2)
        if freeRound then hp = 0 end
        -- hp < maxhp: a FULL character is never a patient.  Without it,
        -- the one-round-of-death rule (hp <= roundCost) deadlocked a
        -- Trapper fight for 85k frames: a measured roundCost equal to max
        -- HP made every full-health character an eternal candidate, and
        -- all four turns went to Tonics that restored nothing.
        if hp > 0 and maxhp > 0 and hp < maxhp then
          local pct = hp * 100 // maxhp
          if pct < threshold or hp <= (price[e] or 0) then
            cands[#cands + 1] = { e = e, pct = pct, hp = hp, maxhp = maxhp }
          end
        end
      end
      -- neediest first: a member inside their priced round (#194) before
      -- anyone merely under the threshold, the thinnest margin first --
      -- the Air Force lab's EDGAR at 393/1048 (two Tek Lasers queued) was
      -- passed over for LOCKE at 363/1129 by percentage and died first
      for _, c in ipairs(cands) do c.margin = c.hp - (price[c.e] or 0) end
      table.sort(cands, function(a, b)
        local la, lb = a.margin <= 0 and (price[a.e] or 0) > 0,
                       b.margin <= 0 and (price[b.e] or 0) > 0
        if la ~= lb then return la end
        if la then return a.margin < b.margin end
        return a.pct < b.pct
      end)
      local allies = 0
      for e = 0, 3 do
        if e ~= actor and hpNow[e] > 0 and M.readWord(0x3C1C + e * 2) > 0 then
          allies = allies + 1
        end
      end
      -- Two or more hurt and a cure known: one boosted, party-wide cure
      -- outheals any single-target turn (owner guideline: use the STRONG
      -- form of the effect once -- Cure2/Cure3 the whole party -- rather
      -- than spending a turn per head).  Boost folds the tier (1 BP ->
      -- Cure2, 2 BP -> Cure3) and one R press on the target screen latches
      -- all allies (TGTALL -- probe_targetall.lua).  Unboosted party Cure
      -- is NOT offered: vanilla halves a spread spell, so tier-0-all heals
      -- less per head than the single cast, and the single line below
      -- already owns that case.
      if cureRow ~= nil and #cands >= 2 then
        local spell = (type(opts.cure) == "table" and opts.cure or CURES)[1]
        local cell = spellCell(actor, spell, true)
        local bank = M.readByte(BP + actor * 2)
        if cell ~= nil and bank >= 1 then
          local deep = cands[1].pct < 35 or #cands >= 3
          local boost = math.min(bank, deep and 2 or 1)
          local mpc = CURE_MP[spell + boost] or 99
          local floorMp = M.readWord(MAXMP + actor * 2) // 4
          local pool = M.readWord(CURMP + actor * 2)
          if pool >= mpc and (deep or pool - mpc >= floorMp) then
            M.log(string.format("[%s] actor=%d party cure: %d hurt "
              .. "(worst %d%%), boost %d folds $%02X -> $%02X (%d MP), "
              .. "all allies", tag or "fight", actor, #cands, cands[1].pct,
              boost, spell, spell + boost, mpc))
            return { kind = "heal", spell = spell, target = cands[1].e,
                     row = cureRow, all = true, boostLeft = boost, reason = "party_hurt" }
          end
        end
      end
      for _, c in ipairs(cands) do
        local cost = price[c.e] or 0
        -- The cast, offered first.  A cure's magic_prop power scales with
        -- the caster's magic power and level, so unlike an item's +$14
        -- power byte there is no honest prior for what it restores.  The
        -- first cast of a spell in a battle is offered unconditionally so
        -- healWatch can measure what it put back; every later cast that
        -- battle is weighed against the real figure.
        if cureRow ~= nil then
          for _, spell in ipairs(type(opts.cure) == "table" and opts.cure
                                 or CURES) do
            local cell, mpCost = spellCell(actor, spell, true)
            -- The cure-MP reserve: the care budget concentrates every
            -- round's heal on the Cure-caster, and cast-before-bag then
            -- drained CELES to 1 MP across the Magitek factory (the
            -- regenerated n024_entry).  A person keeps a quarter of the
            -- pool for the fight ahead and reaches for a Potion; only a
            -- patient inside one round of death may spend past it.
            local floorMp = M.readWord(MAXMP + actor * 2) // 4
            if cell ~= nil and c.hp > cost
               and M.readWord(CURMP + actor * 2) - (mpCost or 0) < floorMp then
              local said = string.format("[%s] actor=%d keeps the cure-MP reserve "
                .. "(%d of %d, floor %d): $%02X would breach it -- the bag instead",
                tag or "fight", actor, M.readWord(CURMP + actor * 2),
                M.readWord(MAXMP + actor * 2), floorMp, spell)
              if said ~= healSaid then healSaid = said; M.log(said) end
              cell = nil
            end
            if cell ~= nil then
              local gain = castRestore[spell]
              local why = gain == nil and "not yet measured"
                or M.healDecision({ hp = c.hp, maxhp = c.maxhp, restore = gain,
                     roundCost = cost, allies = allies, threshold = threshold,
                     mp = true })
              if why then
                healSaid = nil
                M.log(string.format("[%s] actor=%d cure entity %d (%d/%d) with "
                  .. "$%02X, cell %d, %d MP of %d -- restores %s, a round "
                  .. "costs %d (%s)", tag or "fight", actor, c.e, c.hp,
                  c.maxhp, spell, cell, mpCost, M.readWord(CURMP + actor * 2),
                  gain and tostring(gain) or "?", cost, why))
                return { kind = "heal", spell = spell, target = c.e,
                         row = cureRow, reason = why }
              end
              local said = string.format("[%s] actor=%d not curing entity %d "
                .. "(%d/%d): $%02X restores %d and a round costs %d, so the "
                .. "turn buys back less than it spends -- acting instead",
                tag or "fight", actor, c.e, c.hp, c.maxhp, spell, gain, cost)
              if said ~= healSaid then healSaid = said; M.log(said) end
            end
          end
        end
        -- then the bag.  In combat the bag heals with POTIONS: a turn must
        -- buy a real heal (owner guideline -- Tonics are the field
        -- resource), so the Tonic is only ever the last item standing.
        local item = row ~= nil
                 and (battInvIdx(POTION) and POTION
                   or battInvIdx(TONIC) and TONIC) or nil
        if item then
          local gain = itemRestoreOf(item)
          local why = M.healDecision({ hp = c.hp, maxhp = c.maxhp,
            restore = gain, roundCost = cost, allies = allies,
            threshold = threshold })
          if why then
            healSaid = nil
            M.log(string.format("[%s] actor=%d heal entity %d (%d/%d) with " ..
              "$%02X -- restores %d, a round costs %d (%s)", tag or "fight",
              actor, c.e, c.hp, c.maxhp, item, gain, cost, why))
            return { kind = "item", item = item, target = c.e, row = row,
                     idx = battInvIdx(item), reason = why }
          end
          local said = string.format("[%s] actor=%d not healing entity %d " ..
            "(%d/%d): $%02X restores %d and a round costs %d, so the turn "
            .. "buys back less than it spends -- acting instead",
            tag or "fight", actor, c.e, c.hp, c.maxhp, item, gain, cost)
          if said ~= healSaid then healSaid = said; M.log(said) end
        end
      end
    end
    local id = M.readByte(BCHID + actor * 2)
    -- (the boost bank `have`/`boost` was read above the care block)
    -- The spend rule again (#175), for an actor the care block did not
    -- take (the round's care turn is another's, or there is nothing to
    -- care with): dying with pips banked overrides the bank.
    do
      local spend = spendPlan("attack")
      if spend then return spend end
    end
    -- The park ratchet covers the tactical lines as well as care: a
    -- skill whose window keeps getting dropped and re-planned is the
    -- same buzzing confirm, and measured with only the back-out in place
    -- the Zozo Bio Blaster turn cycled park -> B -> re-plan six times
    -- while the party burned down (probeB, 2026-09-04).  Three drops and
    -- this actor Fights for the rest of the battle.
    if parkDropN >= 3 then
      local fight = cmdRow(actor, CMD_FIGHT)
      if fight ~= nil then
        return { kind = "fight", row = fight, boostLeft = boost }
      end
    end
    -- opts.summon = { [charId] = { mp = cost } }: the once-per-battle
    -- genju.  From the magic list scrolled to the top, UP runs
    -- CheckHasGenju and opens the esper window ($7BC2 = $16), A commits,
    -- and A confirms the default target.  The engine's latch is the gate:
    -- the caster's entity bit in $3f2e, which once set makes
    -- UpdateEnabledMagic grey the row, so the plan is offered only while
    -- that bit is clear and the character can pay.  The Magic command row
    -- only exists while the stone is worn, so an unequipped caller falls
    -- through to the branches below the same way a mage out of MP does.
    local sm = opts.summon and opts.summon[id]
    if sm then
      local mp = M.readWord(CURMP + actor * 2)
      local used = M.readWord(0x3f2e) & M.readWord(0x3018 + actor * 2)
      local row = cmdRow(actor, CMD_MAGIC)
      -- $3344 + actor*2 is the worn esper ($ff = none), the same cell
      -- FixPlayerAttack substitutes on a summon.  Terra and Celes carry
      -- the Magic row innately, so without this conjunct a stone-less
      -- caster plans a summon whose esper window can never open and
      -- parks in the magic list.
      local stone = M.readByte(0x3344 + actor * 2)
      if mp >= (sm.mp or 50) and used == 0 and row and stone ~= 0xFF then
        return { kind = "summon", row = row }
      elseif summonWhyN < 8 then
        -- the summon line has historically never fired: say why, per refusal
        summonWhyN = summonWhyN + 1
        M.log(string.format(
          "[%s] summon refused for char %d: mp=%d (need %d) used=$%04x "
          .. "row=%s stone=$%02X",
          tag or "fight", id, mp, sm.mp or 50, used, tostring(row), stone))
      end
    end
    -- opts.magic = { [charId] = { spell = id, boost = false } }: the
    -- attack-magic line, the same shape as the tactical skills.  Open the
    -- Magic list through the $7BC2 state machine, steer to the spell's own
    -- cell against the live cursor cells, and confirm on the enemy the focus
    -- list picks (or the default enemy target when there is no focus list).
    --
    -- The caller names a spell id, not a grid row: the compacted list's
    -- rows move with the party's loadout, and OT6 prices a folded cast at
    -- the tier it folds to, so a caller-supplied row and MP price would be
    -- wrong to hand in.  spellCell answers both from the engine.  A
    -- character who cannot pay falls through to the branches below, so a
    -- mage out of MP Fights instead of wedging the menu.
    --
    -- opts.magic[id].boost = false keeps the cast at its base tier, which is
    -- what a caller wants when the point is the element rather than the
    -- damage and the BP is owed to somebody's break.
    local mg = opts.magic and opts.magic[id]
    if mg and cmdRow(actor, CMD_MAGIC) then
      -- The absorb and Reflect guards, at plan time, for the ability's
      -- element and reflectability (castVetoed above).
      if castVetoed(mg.spell, "cast") then mg = nil end
    end
    if mg and cmdRow(actor, CMD_MAGIC) then
      local cell, cost = spellCell(actor, mg.spell, true)
      if cell ~= nil then
        M.log(string.format("[%s] actor=%d cast $%02X, cell %d, %d MP of %d",
          tag or "fight", actor, mg.spell, cell, cost,
          M.readWord(CURMP + actor * 2)))
        return { kind = "magic", spell = mg.spell,
                 row = cmdRow(actor, CMD_MAGIC),
                 boostLeft = mg.boost == false and 0 or boost }
      elseif not spellKnown(actor, mg.spell) then
        -- an inert line is said once per fight per actor (#182), not
        -- skipped in silence
        local key = actor .. ":" .. mg.spell
        if not inertSaid[key] then
          inertSaid[key] = true
          M.log(string.format("[%s] actor=%d: config spell $%02X is not in char "
            .. "%d's learned table -- inert line", tag or "fight", actor,
            mg.spell, id))
        end
      end
    end
    -- opts.nuke = { spellId, ... } and opts.nukeLore = { loreId, ... }: the
    -- party-wide attack repertoire, tried in order, first castable wins
    -- (owner guideline: a party without Edgar or Sabin should nuke, not
    -- plain-Fight -- a boosted base cast folds to its next tier, the AoE
    -- hit, and a lore is the itemless multi-target line).  Where opts.magic
    -- names one cast for one character, these apply to ANY actor who can
    -- pay: spells gate on spellCell (the live list, MP, and the greyed
    -- bit), lores on the Lore command being in the actor's command table,
    -- the $306A offered signature, and loreCell's own live-list row, and
    -- both on the absorb guard and the nukeFloor MP reserve.  Lores come
    -- first: only a Lore-command
    -- character passes that gate, and for that character the lore is the
    -- point.  Boost rides the same bank machinery as Fight (opts.boost /
    -- opts.bank); a lore is never boosted, matching the ambush driver's
    -- measured play (Aqua Rake multi-targets unboosted).
    if opts.nukeLore and not loreDead and cmdRow(actor, CMD_LORE) then
      if loreSpinN > LORE_STALL then
        loreDiagnose(actor, loreCell(actor, opts.nukeLore[1], false))
      else
        for _, lid in ipairs(opts.nukeLore) do
          if loreOffered(lid) then
            local cell, cost = loreCell(actor, lid, true)
            local mp = M.readWord(CURMP + actor * 2)
            if castVetoed(0x8B + lid, "lore") then
              -- refused and logged; the next lore, then the lines below
            elseif cell ~= nil and mp - cost >= nukeFloor(actor) then
              M.log(string.format(
                "[%s] actor=%d nuke lore $%02X, row %d, %d MP of %d",
                tag or "fight", actor, lid, cell, cost, mp))
              return { kind = "lore", lore = lid,
                       row = cmdRow(actor, CMD_LORE) }
            end
          end
        end
      end
    end
    if opts.nuke and cmdRow(actor, CMD_MAGIC) then
      for _, spell in ipairs(opts.nuke) do
        local cell, cost = spellCell(actor, spell, true)
        if cell == nil and not spellKnown(actor, spell) then
          -- the repertoire is party-wide, so a Magic-row actor without
          -- this one is not a bug by itself; it is still said once per
          -- fight per actor (#182) so a repertoire nobody knows is visible
          local key = actor .. ":" .. spell
          if not inertSaid[key] then
            inertSaid[key] = true
            M.log(string.format("[%s] actor=%d: config spell $%02X (nuke) is not "
              .. "in char %d's learned table -- inert line for this actor",
              tag or "fight", actor, spell, id))
          end
        end
        if cell ~= nil
           and M.readWord(CURMP + actor * 2) - cost >= nukeFloor(actor) then
          if not castVetoed(spell, "nuke") then
            M.log(string.format(
              "[%s] actor=%d nuke $%02X, cell %d, %d MP of %d",
              tag or "fight", actor, spell, cell, cost,
              M.readWord(CURMP + actor * 2)))
            return { kind = "magic", spell = spell,
                     row = cmdRow(actor, CMD_MAGIC), boostLeft = boost }
          end
        end
      end
    end
    -- The keyed line (#174): where this actor holds a key the target's
    -- shield row answers to, that line goes first -- ahead of the tool,
    -- the blitz and the boosted Fight below, which stay the default where
    -- no key is held -- at the smallest boost that breaks this turn
    -- (M.keyBoost; opts.keyBoost = true spends the bank's boost on it
    -- instead, the A/B lever).  The chips are the HUD's revealed cells,
    -- so an unrevealed axis holds no key; a broken gauge is the unload's
    -- turn and falls through to the lines below.  opts.keyed = false
    -- turns the rule off.
    if opts.keyed ~= false then
      local slot = pressTarget()
      if slot == nil then
        for s = 0, 5 do if monAlive(s) then slot = s; break end end
      end
      local sh = slot ~= nil and M.readByte(SH_CUR + slot * 2) or 0
      local broken = slot ~= nil and M.readByte(BRK_TICKS + slot * 2) ~= 0
      if slot ~= nil and sh > 0 and not broken then
        local chipsAt, lines = {}, {}
        for b = 0, boost do
          lines[b] = bestLine(actor, slot, b)
          chipsAt[b] = lines[b] and lines[b].chips or 0
        end
        local useBp, why = M.keyBoost({ need = sh, chipsAt = chipsAt, bank = boost })
        if useBp ~= nil then
          if opts.keyBoost == true then useBp = boost end
          local line = lines[useBp]
          line.reason = "keyed"
          M.log(string.format("[%s] actor=%d KEYED: %s lands %d chip(s) on slot %d's %d "
            .. "shield(s) -- %s%s (#174)", tag or "fight", actor, line.what, line.chips,
            slot, sh, opts.keyBoost == true and "the bank's boost (keyBoost)" or why,
            useBp == 0 and "; unboosted, the pip banks" or ""))
          return line
        end
      end
    end
    -- opts.tools = false disables the Tools line while keeping the rest of
    -- the tactical kit.  Against a formation where a multi-target attack
    -- (AutoCrossbow hits all targets) heals the enemy, Edgar's
    -- single-target pierce Fight removes the same class-weak shields
    -- without triggering that heal.
    -- The tool has to be in the bag (a Tool is an item; the Tools list is
    -- MakeToolsList's walk of the battle inventory): a plan for a tool
    -- that is not there opens the list, finds no row, backs out and plans
    -- the same thing again, forever.  Without the tool Edgar Fights.
    if opts.tactical and opts.tools ~= false and id == 4
       and M.readWord(CURMP + actor * 2) >= 4
       and cmdRow(actor, CMD_TOOLS)
       and battInvIdx(opts.tool or AUTOCROSSBOW) then
      -- The chip model picks between the tool and the sword (#156): against
      -- a lone monster whose revealed classes EDGAR's blade matches, a
      -- boosted Fight's 1 + 2*BP swings chip more than the tool's one hit
      -- (five to one at 2 BP), and chips are the point of the turn.  A
      -- formation of several keeps the tool, which hits them all; a tie
      -- keeps it too.
      local tool = opts.tool or AUTOCROSSBOW
      local slot = soleTarget()
      local fight = cmdRow(actor, CMD_FIGHT)
      if slot ~= nil and fight ~= nil then
        local fc, tc = fightChips(actor, slot, boost), toolChips(slot, tool)
        if fc > tc then
          M.log(string.format("[%s] actor=%d Fight at %d BP chips %d against "
            .. "slot %d, Tools $%02X %d -- Fighting (#156)", tag or "fight",
            actor, boost, fc, slot, tool, tc))
          return { kind = "fight", row = fight, boostLeft = boost }
        end
      end
      return { kind = "skill", cmd = CMD_TOOLS, skill = tool,
               row = cmdRow(actor, CMD_TOOLS), boostLeft = boost }
    end
    if opts.tactical and id == 5 and M.readWord(CURMP + actor * 2) >= 4
       and cmdRow(actor, CMD_BLITZ) then
      return { kind = "skill", cmd = CMD_BLITZ, skill = opts.blitz or PUMMEL,
               row = cmdRow(actor, CMD_BLITZ), boostLeft = boost }
    end
    -- SHADOW throws an elemental skean when a present monster's REVEALED
    -- weakness matches it (owner: unknown menus are missed opportunities --
    -- "Shadow's throw can be useful").  Revealed-only keeps it honest (a
    -- person acts on what the fight has shown); the skeans are bought for
    -- exactly this (Fire Skean $AB, Water Edge $AC, Bolt Edge $AD -> fire/
    -- water/bolt), and boost multiplies a thrown skean like any damage
    -- verb.  Flow measured by probe_throw.lua: cmd $08 -> $2B builds
    -- wItemList -> $2D selects -> ST_TGT.
    if opts.tactical and opts.throw ~= false and id == 3
       and cmdRow(actor, CMD_THROW) then
      for item, elem in pairs(SKEAN_ELEM) do
        if battInvIdx(item) then
          for s = 0, 5 do
            if M.readWord(0x3BFC + s * 2) > 0
               and (M.readByte(0x3E91 + s * 2) & elem) ~= 0 then
              M.log(string.format("[%s] SHADOW throws $%02X at slot %d "
                .. "(revealed elem mask %02X)", tag or "fight", item, s, elem))
              return { kind = "throw", item = item,
                       row = cmdRow(actor, CMD_THROW), boostLeft = boost }
            end
          end
        end
      end
    end
    local fight = cmdRow(actor, CMD_FIGHT)
    if fight == nil then return { kind = "switch" } end
    return { kind = "fight", row = fight, boostLeft = boost }
  end

  local KNOWN_ST = { [ST_CMD] = true, [ST_TGT] = true, [ST_ITEM] = true,
                     [ST_MAGIC] = true, [ST_ESPER] = true, [ST_TOOLS] = true,
                     [ST_LORE] = true, [ST_LORE_OPEN] = true, [0x01] = true,
                     -- the Throw family (probe_throw.lua; btlgfx
                     -- UpdateMenuState_2b/2c/2d): open, close, item select
                     [ST_THROW_OPEN] = true, [0x2C] = true, [ST_THROW] = true,
                     -- the command window's side windows (probe_rowdef.lua)
                     -- and the Tools shell's open and force-close states
                     -- (probe_tools.lua); see the constants
                     [ST_ROW] = true, [ST_DEF] = true,
                     [ST_TOOLS_OPEN] = true, [ST_TOOLS_CLOSE] = true }
  -- The selection windows a plan-less driver backs out of (see the
  -- plan-nil head of button()): every list that waits on A or B.  The
  -- transitional states ($19 lore fill, $2B/$2C throw open/close) are
  -- left out; they pass on their own.
  local IDLE_ST = { [ST_ITEM] = true, [ST_TOOLS] = true, [ST_MAGIC] = true,
                    [ST_ESPER] = true, [ST_LORE] = true, [ST_THROW] = true }
  -- The layout, read once per battle and said out loud (#176): a person
  -- sees at a glance which side the monsters are on, and every direction
  -- the target steer presses below is derived from this reading rather
  -- than from a fixed idea of where they stand.
  local layoutUnreadSaid = false
  local function layoutOf()
    if layout == nil then
      local L = M.battleLayout()
      if L.type > 3 then
        -- InitBattle has not written $201F yet (it reads $FF while the
        -- battle loads: measured at battle f+1, menu=82 state=88).  Not a
        -- reading; nothing is cached and the next call reads again.
        if not layoutUnreadSaid then
          layoutUnreadSaid = true
          M.log(string.format("[%s] [layout] not readable yet ($201F=%02X): the "
            .. "battle is still loading; reading again once the menu is up",
            tag or "fight", L.type))
        end
        return L
      end
      layout = L
      M.log(string.format("[%s] [layout] battle type $%02X (%s): %s; from the "
        .. "party side the cursor crosses with %s, and back with %s "
        .. "($201F=%02X $7ACE=%02X)%s", tag or "fight", layout.type, layout.name,
        layout.where, table.concat(layout.toMonsters, "/"),
        table.concat(layout.toChars, "/"), layout.type, layout.group,
        layout.preemptive and " preemptive ($b0 bit 6: the party's gauges "
          .. "opened full, the monsters' empty -- a free round)" or ""))
    end
    -- a side attack's crossing depends on the group the cursor sits in,
    -- which moves during the fight: re-read that part every time
    if layout.type == 3 then
      local live = M.battleLayout()
      layout.group, layout.toMonsters, layout.toChars =
        live.group, live.toMonsters, live.toChars
    end
    return layout
  end
  -- Fail fast (#176): an input that does nothing, or a plan dropped in
  -- the same window over and over, is a driver defect, and the run says
  -- so with the state in hand instead of idling until the party dies.
  local function failFast(what)
    local said = string.format("[%s] FIGHT DRIVER STUCK: %s", tag or "fight", what)
    M.log(said)
    pcall(function() M.screenshot("fightdriver_stuck") end)
    error(said, 0)
  end
  -- What the target window shows: both side masks, the all-latch and the
  -- target group.  A steer press that leaves every one of them unchanged
  -- moved nothing.
  local function tgtSig()
    return string.format("%02X:%02X:%02X:%02X", M.readByte(TGTCHARS),
      M.readByte(TGTMONS), M.readByte(TGTALL), M.readByte(0x7ACE))
  end
  local function steerWatch()
    if steerLast == nil then return end
    local sig = tgtSig()
    if steerLast.sig ~= sig then steerDead, steerLast = {}, nil; return end
    local n = (steerDead[steerLast.dir] or 0) + 1
    steerDead[steerLast.dir] = n
    -- said for a crossing press (the layout's claim was wrong or unread);
    -- a row walk reaching the end of the row is ordinary and only skips
    if n == 2 and steerLast.kind == "cross" then
      M.log(string.format("[%s] %s pressed twice in target select with no "
        .. "effect (window %s, layout %s): that direction does nothing here",
        tag or "fight", steerLast.dir, sig, layout and layout.name or "unread"))
    end
    steerLast = nil
  end
  local function steer(dir, kind)
    steerLast = { dir = dir, sig = tgtSig(), kind = kind or "walk" }
    return { dir }
  end
  -- Cross the cursor toward the monsters ("monsters") or back to the
  -- party ("chars"), by the layout's reading, skipping a direction this
  -- window has already shown to do nothing.
  local function cross(toward)
    local L = layoutOf()
    local dirs = toward == "monsters" and L.toMonsters or L.toChars
    for _, d in ipairs(dirs) do
      if (steerDead[d] or 0) < 2 then return steer(d, "cross") end
    end
    failFast(string.format("crossing to the %s in a %s: %s did nothing twice "
      .. "each in target select (state $%02X, window %s)", toward, L.name,
      table.concat(dirs, " and "), M.readByte(MSTATE), tgtSig()))
  end

  local function button(actor)
    local st = M.readByte(MSTATE)
    if st == ST_TGT then steerWatch() else steerDead, steerLast = {}, nil end
    if st == ST_CMD then tgtSpin = 0 end
    -- Unknown-menu-state stall guard, on EVERY path (plan or no plan): the
    -- Phantom Train wipe was SHADOW's Throw list ($24), a state this driver
    -- does not know, holding its menu open while the ghosts chipped the
    -- party down.  A person mashes B out of a menu they did not mean to
    -- open: after ~90 frames stuck in one unknown state, drop any plan and
    -- back out.  Transitional states pass through in far fewer frames.
    -- Parked-window watchdog: a KNOWN window whose steer stops making
    -- progress gets dropped like an unknown one.  The Sealed-Gate wipe
    -- sat 900+ frames in the item window at one cursor row while the
    -- fight burned down around it; no legitimate steer takes 300 frames.
    if M.readByte(MENU) ~= 0 and KNOWN_ST[st] and plan ~= nil then
      -- A cap beneath the signature watch: a steer whose cursor keeps
      -- moving without ever landing (the dadaluma wipe scrolled for a
      -- Potion the bag no longer held, 600+ frames, twice) never repeats a
      -- signature, so it needs a budget that ignores progress.  The budget
      -- scales with the row the steer is walking to: the first cut was a
      -- flat 40 ("no steer needs 40 pulses"), and the IAF gauntlet found
      -- the Potion at bag row 43 -- every heal was dropped at 40, re-planned
      -- and dropped again while the party burned down (attempt 10, waves
      -- 5-6).  A deep row costs a press per row; the slack on top is the
      -- open/confirm overhead and the dadaluma no-such-row case.
      planPulses = planPulses + 1
      -- (the fast steer walks ~3 rows a pulse, so even the last bag row
      -- needs well under the ceiling; the ceiling keeps a runaway bounded)
      local budget = math.min(140, 40 + (plan.kind == "item" and plan.idx or 0))
      if planPulses > budget then
        parkDropN = parkDropN + 1
        M.log(string.format("[%s] plan %s (item=%s idx=%s) consumed %d pulses "
          .. "in state $%02X without landing (drop #%d this battle) -- "
          .. "dropping it and backing out%s", tag or "fight", plan.kind,
          tostring(plan.item), tostring(plan.idx), planPulses, st, parkDropN,
          #steerTrail > 0 and ("; list steer trail (scroll,row/col>want row,col): " .. table.concat(steerTrail, " ")) or ""))
        steerTrail = {}
        parkSt, parkN, planPulses = nil, 0, 0
        M.recoveryCount(tag or "fight", string.format("budget:%s/%02X", plan.kind, st))
        dropPlan("pulse_budget")
        return { "b" }
      end
      -- "Parked" means NOTHING is moving: the signature folds in every
      -- window's live cursor cells, so a steer legitimately scrolling a
      -- deep list resets the count each press.  Keying on state alone
      -- fired at exactly 13 pulses while the Potion steer was 21 rows
      -- into a scroll to slot 25, cancelling real heals mid-flight.
      -- The target window's cursor cells are its two side masks and the
      -- group latch: without them every target steer read as parked at
      -- 13 pulses no matter how the cursor moved, so the steers' own
      -- give-ups (24 and 40 pulses, which confirm on whoever is lit)
      -- could never fire first (the Zozo Bio Blaster wipe, 2026-09-04).
      local sig = string.format("%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d",
        st, actor,
        M.readByte(CMDROW + actor), M.readByte(ITEMSCR + actor),
        M.readByte(ITEMROW + actor), M.readByte(MSCROLL + actor),
        M.readByte(MROW + actor), M.readByte(MCOL + actor),
        M.readByte(LSCROLL + actor), M.readByte(LROW + actor),
        M.readByte(TGTCHARS), M.readByte(TGTMONS), M.readByte(TGTALL))
      if sig == parkSt then parkN = parkN + 1
      else parkSt, parkN = sig, 0 end
      if parkN > 12 then          -- ~360 real frames: button() runs per cadence PULSE
        parkDropN = parkDropN + 1
        M.log(string.format("[%s] parked %d pulses in known state $%02X "
          .. "(plan %s item=%s idx=%s, drop #%d this battle) "
          .. "-- dropping the plan and backing out", tag or "fight",
          parkN, st, plan.kind, tostring(plan.item), tostring(plan.idx),
          parkDropN))
        parkSt, parkN = nil, 0
        -- Re-planning into the same window that just parked is how a stuck
        -- steer became a lost fight (#176: the J39 back attack dropped the
        -- plan every 13 pulses until the clock ran out).  The lib's
        -- recovery cap (M.recoveryCount, #185) counts the drops of this
        -- plan in this state and fails fast, with the screenshot and the
        -- ring, past three of them.
        M.recoveryCount(tag or "fight", string.format("%s/%02X", plan.kind, st))
        dropPlan("cursor_stalled")
        return { "b" }
      end
    else
      parkSt, parkN = nil, 0
    end
    if M.readByte(MENU) ~= 0 and not KNOWN_ST[st] then
      if st == unknownSt then unknownN = unknownN + 1
      else unknownSt, unknownN = st, 1 end
      -- The ledger (#188): every pulse sampled here is counted by state,
      -- and the first sighting of each state in a battle is written down
      -- with who held the window, where the command cursor sat and what
      -- the screen showed, so the KNOWN_ST table grows from evidence.
      unknownMenuNote("seen", st)
      if not unknownSeen[st] then
        unknownSeen[st] = true
        local shot = string.format("unknown_menu_%02X_f%d", st, M.frame)
        pcall(M.screenshot, shot)
        local cmds = {}
        for row = 0, 3 do
          cmds[#cmds + 1] = string.format("%02X", M.readByte(CMDTBL + actor * 12 + row * 3))
        end
        M.log(string.format("[%s] [unknown-menu] state $%02X first seen this "
          .. "battle at f%d: actor=%d char=%d cmd row=%d cmds=%s plan=%s "
          .. "screenshot=%s.png", tag or "fight", st, M.frame, actor,
          M.readByte(BCHID + actor * 2), M.readByte(CMDROW + actor) & 3,
          table.concat(cmds, ","), plan and plan.kind or "-", shot))
      end
      if unknownN > 8 then        -- pulses, not frames (the cadence)
        M.log(string.format("[%s] unknown menu state $%02X held %d pulses "
          .. "-- backing out (B)", tag or "fight", st, unknownN))
        unknownSt, unknownN = nil, 0
        unknownMenuNote("drops", st)
        dropPlan("unknown_menu")
        return { "b" }
      end
    else
      unknownSt, unknownN = nil, 0
    end
    -- Row / Def. (see ST_ROW): a side window is open only because a LEFT
    -- or RIGHT reached the command window, which this driver never
    -- presses there -- a direction held from the field into the battle
    -- (train_done, v0.17), or a target-select steer whose window closed
    -- under it.  Back out with B now, on every path; the plan (a row to
    -- walk to at $05) is still good once the window is gone.
    if st == ST_ROW or st == ST_DEF then
      sideWindowN = sideWindowN + 1
      M.log(string.format("[%s] [side-window] %s ($%02X) open at f%d (actor=%d "
        .. "char=%d cmd row=%d plan=%s, #%d this battle) -- not this driver's "
        .. "press; B out", tag or "fight", st == ST_ROW and "Row" or "Def.",
        st, M.frame, actor, M.readByte(BCHID + actor * 2),
        M.readByte(CMDROW + actor) & 3, plan and plan.kind or "-", sideWindowN))
      return { "b" }
    end
    -- A denied actor's window (#187): Stop, Sleep or Berserk on the
    -- entity whose window this is.  The engine is about to take the
    -- window away (measured: Berserk landing at $7BC2=01 -> the window
    -- gone within the pulse) or never meant to open one, so nothing here
    -- is a stall: the park, idle and target-spin counters are stood
    -- down, a plan for this actor is dropped without a recovery count,
    -- and no button is pressed at the command window.  A selection list
    -- or the target screen left open under it is closed with B, because
    -- in Wait mode an open list holds the battle clock and the status
    -- would never run out.
    do
      local den = M.readByte(MENU) ~= 0 and denied(actor) or nil
      if den ~= nil then
        parkSt, parkN, idleSt, idleN, tgtSpin = nil, 0, nil, 0, 0
        if plan ~= nil and planActor == actor then
          M.log(string.format("[%s] actor=%d is under %s with its window at "
            .. "state $%02X -- the engine takes this turn; dropping plan %s "
            .. "without a recovery count", tag or "fight", actor, den, st, plan.kind))
          dropPlan("denied_" .. den)
        end
        if IDLE_ST[st] or st == ST_TGT then return { "b" } end
        return nil
      end
    end
    -- The lore stall guard, checked wherever a lore plan is live rather
    -- than only at plan time: a pursuit wedged inside the window (the
    -- wrong-row failure mode) never returns to makePlan on its own.
    if plan ~= nil and planActor == actor and plan.kind == "lore"
       and loreSpinN > LORE_STALL and not loreDead then
      loreDiagnose(actor, loreCell(actor, plan.lore, false))
      dropPlan()
      return { "b" }
    end
    if plan == nil or planActor ~= actor then
      if st == ST_TGT then
        -- Backstop for a refused confirm: a confirm clears the plan
        -- optimistically and presses A, and when the A is REFUSED (e.g.
        -- the target cursor's rest mask sits on a corpse) the state stays
        -- ST_TGT with no plan.  Below the threshold this waits silently,
        -- since a landed confirm's tail also passes through here for a
        -- tick or two.  tgtSpin resets only at ST_CMD (a genuine menu
        -- restart), not on any off-ST_TGT flicker.  Past the threshold:
        -- walk the cursor (the focus steer's own rotation) between
        -- confirms until any live target lets the A land.
        tgtSpin = tgtSpin + 1
        if tgtSpin < 8 then return nil end
        if tgtSpin == 8 then
          M.log(string.format("[%s] tgt confirm is being refused " ..
            "(chars=%02X mons=%02X) -- walking the cursor to a live " ..
            "target", tag or "fight",
            M.readByte(TGTCHARS), M.readByte(TGTMONS)))
        end
        local dirs = { "left", "right", "down", "up" }
        if (tgtSpin % 6) < 3 then
          return { dirs[1 + ((tgtSpin // 6) % 4)] }
        end
        return { "a" }
      end
      -- No plan, but a selection window is open: a dropped plan's B out
      -- of target select lands in the window that opened it (btlgfx
      -- UpdateMenuState_38 restores $7A83, the Tools list for a tool),
      -- and this driver only plans at the command state.  Left alone
      -- that window stayed open for 4400 frames while the Zozo street
      -- wiped the party (2026-09-04).  A person backs out again; so
      -- does this, after two pulses of the same window, since a landed
      -- confirm's closing tail also passes through here for a tick.
      if IDLE_ST[st] then
        if st == idleSt then idleN = idleN + 1 else idleSt, idleN = st, 1 end
        if idleN > 2 then
          M.log(string.format("[%s] no plan and window $%02X still open "
            .. "after %d pulses -- backing out to re-plan", tag or "fight",
            st, idleN))
          idleSt, idleN = nil, 0
          return { "b" }
        end
        return nil
      end
      idleSt, idleN = nil, 0
      if st ~= ST_CMD then return nil end
      -- Another actor's Fenix Down is in the air (#168): hold this window
      -- until it lands, so the plan made here sees the raised member
      -- alive and can top them up -- a Potion's target cursor cannot land
      -- on a corpse, and a plan made a beat too early attacks instead.  A
      -- person waits for the animation the same way.  Bounded: a raise
      -- the engine refused or a slow queue releases the hold at
      -- RAISE_WAIT ticks.
      if raisePending and raisePending.by ~= actor
         and M.readWord(0x3BF4 + raisePending.e * 2) == 0
         and battleTick - raisePending.tick <= RAISE_WAIT then
        if not raisePending.heldSaid then
          raisePending.heldSaid = true
          M.log(string.format("[%s] actor=%d holds its command window: actor %d's "
            .. "Fenix Down on entity %d (confirmed at tick %d) has not landed yet; "
            .. "planning once it does (or after %d ticks)", tag or "fight", actor,
            raisePending.by, raisePending.e, raisePending.tick, RAISE_WAIT))
        end
        return nil
      end
      plan, planActor, tgtSpin = makePlan(actor), actor, 0
      if recovery then recovery.plan(actor, plan, M.frame) end
      planPulses, steerTrail = 0, {}
      if plan.kind == "heal" or plan.kind == "item" then careActor = actor end
      M.log(string.format("[%s] actor=%d char=%d plan=%s",
        tag or "fight", actor, M.readByte(BCHID + actor * 2), plan.kind))
      return nil
    end
    if st == ST_CMD then
      -- "switch" (no Fight row) and "defer" (a muddled actor, #170) both
      -- hand the window on with X; the plan stays until the actor changes
      if plan.kind == "switch" or plan.kind == "defer" then return { "x" } end
      if plan.boostLeft and plan.boostLeft > 0 then
        plan.boostLeft = plan.boostLeft - 1
        return { "r" }
      end
      -- The row can go grey between the plan and the press (a status that
      -- lands while the window is open: Mute greys Magic); the cursor
      -- would then hop over it forever.  Re-plan instead of chasing it.
      if plan.row ~= nil and cmdDisabled(actor, plan.row) then
        M.log(string.format("[%s] plan %s: command row %d is DISABLED "
          .. "(flags $%02X) -- the cursor cannot land there; re-planning",
          tag or "fight", plan.kind, plan.row,
          M.readByte(CMDTBL + actor * 12 + plan.row * 3 + 1)))
        dropPlan("command_disabled")
        return nil
      end
      local cur = M.readByte(CMDROW + actor) & 3
      if cur == plan.row then return { "a" } end
      return { cur < plan.row and "down" or "up" }
    end
    if st == ST_ITEM and plan.kind == "item" then
      -- Use the index resolved when the plan was made rather than a fresh
      -- read: mid-menu inventory reads return wrong values, and a wrong
      -- read here returns nil, drops the plan, presses B, and re-plans,
      -- without end.
      local want = plan.idx or battInvIdx(plan.item)
      if want == nil then traceDrop("item_unavailable"); plan, planActor = nil, nil; return { "b" } end
      local cur = M.readByte(ITEMSCR + actor) + M.readByte(ITEMROW + actor)
      -- A far row is walked at three presses per pulse rather than one
      -- (the frame loop's `fast`): one press per 30-frame pulse put the
      -- IAF's row-43 Potion 1300 frames of active-time menu away, and two
      -- of three died while the steer walked (attempts 10-11).  Within two
      -- rows the steer taps once per pulse again, so an overshoot is at
      -- most two rows and the next pulse corrects it.
      local far = math.abs(want - cur) > 2
      if far and not plan.fastLogged then
        plan.fastLogged = true
        M.log(string.format("[%s] item steer: row %d -> %d, walking fast (3 presses a pulse)", tag or "fight", cur, want))
      end
      if cur < want then return { "down", fast = far } end
      if cur > want then return { "up", fast = far } end
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
    if st == ST_MAGIC and (plan.kind == "magic" or plan.kind == "heal") then
      -- The same two-column walk for both magic lines.  The cell was
      -- resolved at plan time, but the list is rebuilt when the window
      -- opens, so it is re-read here: a cell that has moved (or a spell the
      -- engine has since greyed) drops the plan rather than steering to
      -- whatever now occupies the old row.
      local cell = spellCell(actor, plan.spell, false)
      if cell == nil then traceDrop("spell_unavailable"); plan, planActor = nil, nil; return { "b" } end
      local wr, wc = cell // 2, cell % 2
      local ar = M.readByte(MSCROLL + actor) + M.readByte(MROW + actor)
      local col = M.readByte(MCOL + actor)
      -- the steer's trail, printed if the plan is dropped at the pulse cap:
      -- a list steer that never lands is either oscillating (a press moving
      -- two rows) or chasing a cell that moves (a list re-fold under it)
      steerTrail[#steerTrail + 1] = string.format("%d,%d/%d>%d,%d", M.readByte(MSCROLL + actor), M.readByte(MROW + actor), col, wr, wc)
      if #steerTrail > 12 then table.remove(steerTrail, 1) end
      if ar < wr then return { "down" } end
      if ar > wr then return { "up" } end
      if col < wc then return { "right" } end
      if col > wc then return { "left" } end
      return { "a" }
    end
    if st == ST_LORE_OPEN and plan.kind == "lore" then
      return nil                       -- transitional DMA fill, just wait
    end
    if st == ST_LORE and plan.kind == "lore" then
      -- The item-window steer shape: the absolute row is scroll + cursor,
      -- and the wanted row is re-read from the live segment (not strict,
      -- for spellCell's stale-greyed-bit reason) rather than trusted from
      -- plan time.  A lore the engine no longer offers a row for drops
      -- the plan instead of steering to whatever holds the old row.
      local want = loreCell(actor, plan.lore, false)
      if want == nil then plan, planActor = nil, nil; return { "b" } end
      local cur = M.readByte(LSCROLL + actor) + M.readByte(LROW + actor)
      if cur < want then return { "down" } end
      if cur > want then return { "up" } end
      return { "a" }
    end
    if st == ST_THROW_OPEN and plan.kind == "throw" then
      return nil                       -- the window is building; wait
    end
    if st == ST_THROW and plan.kind == "throw" then
      -- the throw list is the tools shell's shape: wItemList $4005,
      -- 3-byte rows, id $FF terminates.  Steer the tools cursor cells
      -- toward the wanted row; if it cannot be reached, drop the plan
      -- and back out rather than throw whatever sits under the cursor
      -- (a wrong confirm here throws a WEAPON).
      local want
      for i = 0, 15 do
        local rid = M.readByte(ITEMLIST + i * 3)
        if rid == plan.item then want = i; break end
        if rid == 0xFF then break end
      end
      if want == nil then plan, planActor = nil, nil; return { "b" } end
      local wc, wr = want % 2, want // 2
      local cc, cr = M.readByte(BLCOL + actor), M.readByte(BLROW + actor)
      if cc == wc and cr == wr then return { "a" } end
      tgtSpin = tgtSpin + 1
      if tgtSpin >= 40 then
        M.log(string.format("[%s] throw steer gave up (row %d,%d vs want "
          .. "%d,%d) -- backing out, not throwing blind", tag or "fight",
          cr, cc, wr, wc))
        plan, planActor, tgtSpin = nil, nil, 0
        return { "b" }
      end
      if cc ~= wc then return { wc > cc and "right" or "left" } end
      return { wr > cr and "down" or "up" }
    end
    if (st == ST_TOOLS_OPEN or st == ST_TOOLS_CLOSE) and plan.kind == "skill" then
      return nil                       -- the shell is building / closing; wait
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
      -- Every ally-targeted line steers the same way: an item and a cure
      -- differ only in which window chose them, and the Muddle rule's
      -- Fight on an ally (plan.ally, #170) crosses to the party column
      -- with the same RIGHT (battle_magicite measured the monsters on the
      -- left and a LEFT parking the cursor) and walks the same mask.
      if plan.kind == "item" or plan.kind == "heal" or plan.ally then
        local chars, mons = M.readByte(TGTCHARS), M.readByte(TGTMONS)
        if mons ~= 0 then return cross("chars") end
        -- Neither side is selected: falling into the steer below with
        -- chars = 0 would set cur = 0 and, for target 0, spin forever
        -- pressing UP.
        if chars == 0 then return cross("chars") end
        if plan.all then
          -- one R press latches all-allies (TGTALL=1 -- probe_targetall);
          -- confirm once the latch reads back.  If it never takes (a spell
          -- without MULTI_TARGET), drop to the single-target steer.
          if M.readByte(TGTALL) ~= 0 then
            if recovery then recovery.confirm(actor, M.frame, chars, mons) end
            return { "a" }
          end
          tgtSpin = tgtSpin + 1
          if tgtSpin >= 40 then
            M.log(string.format("[%s] all-ally latch never took -- "
              .. "single-target fallback", tag or "fight"))
            plan.all, tgtSpin = nil, 0
            return {}
          end
          return (tgtSpin % 4) < 2 and { "r" } or {}
        end
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
            local d = cur < plan.target and "down" or "up"
            -- ...and a direction that moved nothing twice is not pressed
            -- a third time; the give-up below confirms instead (#176)
            if (steerDead[d] or 0) < 2 then return steer(d) end
            M.log(string.format("[%s] %s does nothing in this party-side "
              .. "window (chars=%02X want=%02X)", tag or "fight", d, chars,
              wantMask))
          end
          M.log(string.format("[%s] target steer gave up (chars=%02X " ..
            "want=%02X) -- confirming on whoever is highlighted",
            tag or "fight", chars, wantMask))
        end
      end
      -- opts.focus = { {slot=S, mask=M}, ... }: monster kill order, steered
      -- against the live target mask ($7B7E) the way the item line steers
      -- $7B7D.  Each entry names a monster slot (for the liveness check
      -- against $3BFC) and the $7B7E mask bit that puts the cursor on it;
      -- mask bits follow the on-screen formation layout rather than
      -- monster-table order, so the two are not interchangeable.  Focus
      -- picks the first entry whose slot is still alive; single-target
      -- plans steer to its mask (summons, items and cures keep their own
      -- targeting), and the tgtSpin backstop still confirms rather than
      -- holding the turn open.
      -- A lore is multi-target: the focus rotation would spin against a
      -- whole-side mask it can never match, so it confirms on the default.
      if opts.focus and plan.kind ~= "item" and plan.kind ~= "summon"
         and plan.kind ~= "heal" and plan.kind ~= "lore" and not plan.ally then
        local want = nil
        -- MONSTER_IDS is six 8-bit ID low bytes, one per slot; a word
        -- read at a 2-byte stride walks off the table into the position
        -- bytes and can pass dead slots and skip live ones (measured:
        -- the thamlab deadboard misdiagnosis).  monsterIds() decodes the
        -- present mask, the authority on which slots hold a monster.
        local ids = M.monsterIds()
        for _, e in ipairs(opts.focus) do
          if ids[e.slot + 1] ~= 0xFFFF
             and M.readWord(0x3BFC + e.slot * 2) > 0 then want = e.mask; break end
        end
        if want ~= nil then
          local mons = M.readByte(TGTMONS)
          -- The focused monster has to be UNDER the cursor, not be the
          -- whole of it: a group-targeting ability (Bio Blaster $7D,
          -- targeting $6A = ENEMY|MULTI_TARGET|INIT_GROUP|ONE_SIDE, no
          -- MANUAL) lights a whole monster group ($7B7E=$2C measured on
          -- the Zozo street) and its left/right only swap groups, so
          -- an exact match against one slot's bit could never happen
          -- and the turn was parked away into a wipe (2026-09-04).
          if mons & want == 0 then
            tgtSpin = tgtSpin + 1
            if tgtSpin < 24 then
              -- On the ally side (mons == 0) the cursor has to cross, and
              -- which way that is depends on the battle's layout, not on
              -- a fixed side (#176: a back attack crosses with RIGHT --
              -- LEFT is an rts there, and the J39-row fight idled in
              -- target select pressing it).  Among monsters the walk
              -- leads with LEFT/RIGHT: a side-by-side formation's rest
              -- mask does not move on down/up.  A direction this window
              -- has shown to do nothing is skipped.
              if mons == 0 then return cross("monsters") end
              local dirs = { "left", "right", "down", "up" }
              for i = 0, 3 do
                local d = dirs[1 + ((tgtSpin // 6 + i) % 4)]
                if (steerDead[d] or 0) < 2 then return steer(d) end
              end
              failFast(string.format("walking the monster row in a %s: every "
                .. "direction did nothing twice (state $%02X, window %s, "
                .. "want=%02X)", layoutOf().name, st, tgtSig(), want))
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
      -- Watch what the heal we just confirmed is actually worth.  For an item
      -- this replaces a prior (the power byte) with the engine's own number;
      -- for a cast there is no prior at all, and this is the only place the
      -- number can come from, which is why an unmeasured cure is offered
      -- unconditionally in makePlan.  Either way it is measured once per
      -- battle, because a reloaded retry is a different fight.
      local watch = nil
      if plan.kind == "item" and plan.item ~= FENIX_DOWN
         and itemRestore[plan.item] == nil then
        watch = { into = itemRestore, id = plan.item, what = "item" }
      elseif plan.kind == "heal" and not plan.all
         and castRestore[plan.spell] == nil then
        -- an all-ally cast is boosted and spread, so its per-head number
        -- would poison the single-cast ledger; it goes unmeasured
        watch = { into = castRestore, id = plan.spell, what = "cure" }
      end
      if watch then
        watch.target = plan.target
        watch.hp = M.readWord(0x3BF4 + plan.target * 2)
        watch.maxhp = M.readWord(0x3C1C + plan.target * 2)
        watch.until_ = battleTick + 900
        healWatch = watch
      end
      -- The raise-then-top-up pair (#168): a confirmed Fenix Down is
      -- pending until the target's HP moves (F.frame); a confirmed heal
      -- on a raised member pays the top-up owed.
      if plan.ally then
        unmuddlePending = { e = plan.target, by = actor, tick = battleTick }
      elseif plan.kind == "item" and plan.item == FENIX_DOWN then
        raisePending = { e = plan.target, by = actor, tick = battleTick }
        raiseQueued[plan.target] = { by = actor, tick = battleTick }
      elseif plan.kind == "item" and plan.target
         and type(plan.reason) == "string" and plan.reason:sub(1, 5) == "cure " then
        -- a confirmed status cure (#187): nobody plans another on this
        -- entity until the bit clears (F.frame) or the window lapses
        cureQueued[plan.target] = { by = actor, tick = battleTick, item = plan.item }
      elseif (plan.kind == "item" or plan.kind == "heal") and plan.target
         and topUpOwed[plan.target] then
        M.log(string.format("[%s] actor=%d's %s on entity %d is the top-up its raise "
          .. "was owed (raised at tick %d)", tag or "fight", actor, plan.kind,
          plan.target, topUpOwed[plan.target]))
        topUpOwed[plan.target] = nil
      end
      -- and what a damage plan lands, for the press rule's window (the
      -- dmgWatch queue above; F.frame credits and settles it).  A Fight
      -- on a muddled ally (#170) moves no monster HP and is not one.
      if not plan.ally and (plan.kind == "fight" or plan.kind == "skill" or plan.kind == "magic"
         or plan.kind == "summon" or plan.kind == "throw" or plan.kind == "lore") then
        -- an actor gets a fresh confirm only after its last command
        -- resolved (settled below) or was refused at the cursor, so an
        -- earlier watch of this actor's still holding nothing is the
        -- refused one: it is superseded, not queued behind
        for i = #dmgWatch, 1, -1 do
          if dmgWatch[i].actor == actor and dmgWatch[i].seen == 0 then
            table.remove(dmgWatch, i)
          end
        end
        dmgWatch[#dmgWatch + 1] = { actor = actor, kind = plan.kind,
                                    skill = plan.skill, seen = 0, norm = 0, n = 0,
                                    until_ = battleTick + DMG_EXPIRE }
      end
      -- A confirmed lore is the progress the stall guard watches for.
      if plan.kind == "lore" then
        loreSpinN = 0
        M.log(string.format("[%s] lore $%02X confirmed", tag or "fight",
          plan.lore))
      end
      -- A refused confirm (corpse under the target cursor) re-enters
      -- button()'s plan-nil ST_TGT head next tick, which owns the
      -- backstop; the optimistic clear here is what routes it there.
      if recovery then recovery.confirm(actor, M.frame,
        M.readByte(TGTCHARS), M.readByte(TGTMONS)) end
      dropPlan("confirm_attempt")
      return { "a" }
    end
    if st == ST_ITEM or st == ST_TOOLS or st == ST_MAGIC or st == ST_ESPER
       -- the lore states join the back-out set only when the repertoire is
       -- in play: without opts.nukeLore nothing here ever opens that
       -- window, and the default driver stays byte-identical.
       or (opts.nukeLore and (st == ST_LORE or st == ST_LORE_OPEN)) then
      dropPlan()
      return { "b" }
    end
    return nil
  end

  function F.idle()
    if recovery then
      recovery.close(M.frame, "battle_ended")
      if recoveryObserver == recovery then recoveryObserver = nil end
      recoveryFlush()
    end
    menuStreak, tick, battleTick = 0, 0, 0
    plan, planActor, held = nil, nil, {}
    parkDropN = 0
    layout, layoutUnreadSaid, steerLast, steerDead = nil, false, nil, {}
    parkSt, parkN, idleSt, idleN = nil, 0, nil, 0
    unknownSt, unknownN, unknownSeen, sideWindowN = nil, 0, {}, 0
    if healSaid == "parked-out" then healSaid = nil end
    careActor, startSnap, planPulses = nil, nil, 0
    -- Everything the heal policy measured belongs to the battle that just
    -- ended.  A retry ladder replays the same fight from a reload, and
    -- carrying a round cost across the boundary would let one attempt's
    -- damage decide the next attempt's first turns.
    roundCost, turnSnap = {}, {}
    itemRestore, castRestore = {}, {}
    healWatch, healSaid, finisherSaid, inertSaid = nil, nil, nil, {}
    priceSaid = {}
    dmgWatch, dmgSeen, monHpLast = {}, {}, {}
    dmgHit, hitLedger, partyHpLast = {}, {}, {}
    monAct, deathSaid, battleDeaths, wipeSaid = nil, {}, {}, false
    raisePending, topUpOwed, unmuddlePending = nil, {}, nil
    raiseQueued, cureQueued = {}, {}
    statusSaid, cureSaid, freeRoundSaid = {}, nil, false
    execActor, execActorCmd, execDone = nil, nil, {}
    execParty, execSkipped = nil, {}
    execMon, execMonDone = nil, nil
    execMonCmd, execMonAtk = nil, nil
    -- The stall guard's verdict belongs to the battle it watched: a retry
    -- ladder's reload is a different fight, and a recurrence should dump
    -- again there rather than inherit a dead lore line silently.
    loreSpinN, loreDead = 0, false
  end

  function F.frame()
    if recovery then recoveryActivate(recovery); recoveryFlush() end
    execActivate()
    battleTick = battleTick + 1
    -- The party's HP as the battle opened, for the first-turn danger floor
    -- in makePlan.  Taken a beat after the table goes live so every entity
    -- is written (the f+1 log line already reads every entity); no monster
    -- acts inside 4 frames.
    if startSnap == nil and battleTick == 4 and M.battleLoadStarted() then
      local snap = {}
      for e = 0, 3 do snap[e] = M.readWord(0x3BF4 + e * 2) end
      startSnap = snap
    end
    -- The [status] line (#187), once per battle per entity per status:
    -- what landed, what the engine does with it, and what the bag holds
    -- for it -- said the frame it lands, so the driver's next lines read
    -- against it; and once when it clears.
    if battleTick > 4 then
      for e = 0, 3 do
        if M.readWord(0x3C1C + e * 2) > 0 then
          local s1, s2, s3 = statusOf(e)
          local names = {}
          local den = M.turnDenied({ s1 = s1, s2 = s2, s3 = s3 })
          if den then names[#names + 1] = den end
          if (s1 & M.ST1_IMP) ~= 0 then names[#names + 1] = "Imp" end
          local on = {}
          for _, name in ipairs(names) do
            on[name] = true
            local key = e .. ":" .. name
            if not statusSaid[key] then
              statusSaid[key] = "on"
              local what
              if name == "Stop" then
                what = "the engine holds its gauge (Ot6Gate; $3AF1 counts $12 ticks "
                  .. "down) and opens no window for it; planning around it"
              elseif name == "Sleep" then
                what = "the ATB-full check cancels its menu (battle_main @0941); a "
                  .. "physical hit on it clears the bit (@0c45), else the counter "
                  .. "runs out; planning around it"
              elseif name == "Berserk" then
                local item = cureFor(e)
                what = "the engine Fights for it (RandCharAction); planning around it; cure: "
                  .. (item and string.format("$%02X x%d", item, bagCount(item))
                      or string.format("none in the bag (Remedy x%d carries no Berserk bit)",
                        bagCount(M.REMEDY)))
              else
                local item = cureFor(e)
                what = "its Fight lands for 0 (battle power zeroed @1029) and its Magic "
                  .. "keeps only Imp; every row but Fight/Item/Magic greyed; cure: "
                  .. (item and string.format("$%02X x%d (planned next turn)", item,
                        bagCount(item))
                      or string.format("none in the bag (Green Cherry %d, Remedy %d)",
                        bagCount(M.GREEN_CHERRY), bagCount(M.REMEDY)))
              end
              M.log(string.format("[%s] [status] f+%d entity %d char %d %s (STATUS1/2/3 "
                .. "$%02X/$%02X/$%02X, atb=%04X menu=%02X st=%02X actor=%d): %s",
                tag or "fight", battleTick, e, M.readByte(BCHID + e * 2),
                name == "Imp" and "is an IMP" or ("is under " .. name:upper()),
                s1, s2, s3, M.readWord(ATB + e * 2), M.readByte(MENU),
                M.readByte(MSTATE), M.readByte(ACTOR) & 3, what))
            end
          end
          for _, name in ipairs({ "Stop", "Sleep", "Berserk", "Imp" }) do
            local key = e .. ":" .. name
            if statusSaid[key] == "on" and not on[name] then
              statusSaid[key] = "off"
              M.log(string.format("[%s] [status] f+%d entity %d's %s is CLEARED "
                .. "(STATUS1/2/3 $%02X/$%02X/$%02X)", tag or "fight", battleTick, e,
                name, s1, s2, s3))
            end
          end
        end
      end
    end
    -- VICTORY-DEADLOCK guard (measured, Thamasa grind bake fight 37): the
    -- killing blow can land while an actor's spell/item window is still
    -- open; in Wait mode the open window freezes the battle clock, and
    -- this driver only plans at the command state, so the battle sat at
    -- state $0E for 100k+ frames with every monster at 0 HP.  When no
    -- monster slot holds HP and a battle menu window is still up, tap B
    -- to close it so the battle can end.
    if battleTick > 600 and M.readByte(MENU) ~= 0 then
      local alive = false
      for s = 0, 5 do
        if M.readWord(0x3BFC + s * 2) > 0 then alive = true; break end
      end
      if not alive then
        M.setPad(battleTick % 8 < 4 and { b = true } or {})
        return
      end
    end
    -- The landed value of a heal, watched from its confirmation until the HP
    -- moves.  HP falling first is the enemy acting between the confirm and
    -- the heal, so the baseline follows it down rather than reading the
    -- rebound as a bigger heal than it was.
    -- A heal that fills the target to maximum is CLIPPED, and the HP it
    -- moved is a lower bound rather than what the heal is worth, so a
    -- clipped heal is not recorded; it stays unmeasured, which falls back
    -- to the item's power byte or to offering the cast, and the next use
    -- on somebody with room measures it properly.
    if healWatch then
      local hp = M.readWord(0x3BF4 + healWatch.target * 2)
      if hp > healWatch.hp and hp >= healWatch.maxhp then
        healWatch = nil
      elseif hp > healWatch.hp then
        healWatch.into[healWatch.id] = hp - healWatch.hp
        M.log(string.format("[%s] %s $%02X restored %d hp on entity %d " ..
          "(measured; the heal policy uses this from here on)",
          tag or "fight", healWatch.what, healWatch.id, hp - healWatch.hp,
          healWatch.target))
        healWatch = nil
      elseif hp < healWatch.hp then
        healWatch.hp = hp
      elseif battleTick > healWatch.until_ then
        healWatch = nil
      end
    end
    -- The damage watch (see dmgWatch): monster HP falling is credited to
    -- the entity whose command is executing (execActor), or, for the
    -- DMG_SETTLE frames after a command returned, to that command; then
    -- the figure is normalized and kept per actor.  A rise (a monster
    -- healing itself, an absorbed hit) only moves the baseline.
    do
      -- an engine command under a party X (a dot tick) is not that
      -- member's action: said once per battle per member and command
      -- when it would have settled a pending watch, which is #207
      while execSkipped[1] ~= nil do
        local k = table.remove(execSkipped, 1)
        local key = string.format("skip:%d:%02X", k.actor, k.cmd)
        if dmgWatchOf(k.actor) and not inertSaid[key] then
          inertSaid[key] = true
          M.log(string.format("[%s] entity %d ran engine command $%02X atk $%02X "
            .. "(a dot tick or other engine action, not its menu command): its "
            .. "pending damage watch stays open for the command it chose (#207)",
            tag or "fight", k.actor, k.cmd, k.atk))
        end
      end
      local who = execActor
      if who == nil and execDone[#execDone] ~= nil then
        who = execDone[#execDone].actor
      end
      for s = 0, 5 do
        local hp = M.readWord(MON_HP + s * 2)
        local last = monHpLast[s]
        if who ~= nil and last ~= nil and hp < last then
          local _, w = dmgWatchOf(who)
          if w then
            local drop = last - hp
            w.seen = w.seen + drop
            -- normalized per hit by the state of THIS slot's gauge as
            -- the hit landed: a volley that breaks mid-way lands its
            -- rest broken (x4 shielded), and the per-hit figure (#165)
            -- must not average the two
            w.norm = w.norm
              + ((M.readByte(BRK_TICKS + s * 2) ~= 0) and (drop // 4) or drop)
            w.n = w.n + 1
          end
        end
        monHpLast[s] = hp
      end
      while execDone[1] ~= nil and M.frame - execDone[1].frame > DMG_SETTLE do
        local done = table.remove(execDone, 1)
        local i, w = dmgWatchOf(done.actor)
        if w then
          dmgSeen[w.actor] = w.norm
          if w.n > 0 then
            dmgHit[w.actor] = { kind = w.kind, skill = w.skill,
                                per = w.norm // w.n, n = w.n }
          end
          M.log(string.format("[%s] actor=%d's %s took %d off the monsters "
            .. "(%d shielded-equivalent over %d hit(s), %d a hit; the press "
            .. "rule counts it) [exec cmd $%02X atk $%02X]", tag or "fight", w.actor,
            w.kind, w.seen, w.norm, w.n, w.n > 0 and w.norm // w.n or 0,
            done.cmd or 0xFF, done.atk or 0xFF))
          table.remove(dmgWatch, i)
        end
      end
      for i = #dmgWatch, 1, -1 do
        if battleTick > dmgWatch[i].until_ then table.remove(dmgWatch, i) end
      end
    end
    -- The raise-then-top-up pair (#168): a pending Fenix Down has landed
    -- when its target's HP moves off 0; the member is then owed a top-up
    -- until it arrives, they climb clear on their own, or they fall again.
    for e, q in pairs(raiseQueued) do
      local hp = M.readWord(0x3BF4 + e * 2)
      if (hp > 0 and hp ~= 0xFFFF) or battleTick - q.tick > RAISE_WAIT + 600 then
        raiseQueued[e] = nil
      end
    end
    -- a queued status cure has landed when the bit it carries is gone
    -- (the [status] CLEARED line says so), or is forgotten after its window
    for e, q in pairs(cureQueued) do
      local s1, s2 = M.readByte(ST1 + e * 2), M.readByte(ST2 + e * 2)
      local still = (M.itemStatus1(q.item) & s1) ~= 0 or (M.itemStatus2(q.item) & s2) ~= 0
      if not still or M.readWord(0x3BF4 + e * 2) == 0
         or battleTick - q.tick > RAISE_WAIT + 600 then
        cureQueued[e] = nil
      end
    end
    if raisePending then
      local hp = M.readWord(0x3BF4 + raisePending.e * 2)
      if hp > 0 and hp ~= 0xFFFF then
        topUpOwed[raisePending.e] = battleTick
        M.log(string.format("[%s] actor %d's Fenix Down landed: entity %d is at %d/%d "
          .. "at tick %d -- a top-up is owed (the care budget opens for it)",
          tag or "fight", raisePending.by, raisePending.e, hp,
          M.readWord(0x3C1C + raisePending.e * 2), battleTick))
        raisePending = nil
      elseif battleTick - raisePending.tick > RAISE_WAIT + 600 then
        M.log(string.format("[%s] actor %d's Fenix Down on entity %d never landed "
          .. "(%d ticks) -- forgetting it", tag or "fight", raisePending.by,
          raisePending.e, battleTick - raisePending.tick))
        raisePending = nil
      end
    end
    -- the Muddle rule's pending hit (#170) is done when the bit clears
    -- (or the member falls), or forgotten after its window
    if unmuddlePending then
      local e = unmuddlePending.e
      if (M.readByte(ST2 + e * 2) & M.ST2_MUDDLE) == 0
         or M.readWord(0x3BF4 + e * 2) == 0
         or battleTick - unmuddlePending.tick > RAISE_WAIT + 600 then
        M.log(string.format("[%s] entity %d's Muddle %s (actor %d's hit confirmed at "
          .. "tick %d, now tick %d, STATUS2 $%02X)", tag or "fight", e,
          (M.readByte(ST2 + e * 2) & M.ST2_MUDDLE) == 0 and "is CLEARED" or "hit is forgotten",
          unmuddlePending.by, unmuddlePending.tick, battleTick, M.readByte(ST2 + e * 2)))
        unmuddlePending = nil
      end
    end
    for e, _ in pairs(topUpOwed) do
      local hp, maxhp = M.readWord(0x3BF4 + e * 2), M.readWord(0x3C1C + e * 2)
      if hp == 0 or hp == 0xFFFF or maxhp == 0
         or hp * 100 // maxhp >= (opts.healPercent or 60) then
        topUpOwed[e] = nil
      end
    end
    -- The hit ledger (#165): party HP falling while a monster's command
    -- executes (execMon, or within DMG_SETTLE frames of one returning
    -- with no party command running) is that monster's hit on that
    -- member -- the numeral a person reads over their own character.  A
    -- drop with no monster acting (a poison tick, a party member's own
    -- reflected spell) is nobody's and not recorded.  A killing hit is
    -- capped at the HP the victim had, which is the right reading for
    -- the raise rule: a member raised to 44 and killed from 44 measured
    -- the enemy at "44 or more".
    do
      local slot = execMon
      if slot == nil and execMonDone ~= nil and execParty == nil
         and M.frame - execMonDone.frame <= DMG_SETTLE then
        slot = execMonDone.slot
      end
      -- one monAct per attributed action: it opens when a slot starts
      -- executing and closes when the attribution window ends.  Its
      -- drops are held until it closes and committed to the ledger
      -- together (commitMonAct), and read provisionally by the raise gate
      -- while it is open (raiseOk).
      if slot == nil or monAct == nil or monAct.slot ~= slot then
        if monAct ~= nil then commitMonAct(monAct) end
        monAct = nil
      end
      if slot ~= nil and monAct == nil then
        monAct = { slot = slot, cmd = execMonCmd or 0, atk = execMonAtk or 0,
                   tick = battleTick, hp0 = {}, kills = 0, fullKills = 0, drops = {} }
        for e = 0, 3 do monAct.hp0[e] = partyHpLast[e] or M.readWord(0x3BF4 + e * 2) end
      end
      for e = 0, 3 do
        local hp = M.readWord(0x3BF4 + e * 2)
        local last = partyHpLast[e]
        if slot ~= nil and last ~= nil and last ~= 0xFFFF and hp < last then
          monAct.drops[#monAct.drops + 1] = { e = e, drop = last - hp, last = last, hp = hp }
        end
        -- The [death] line (#175): a member's HP reaching 0 from above,
        -- with the pips they were holding.  The killer is the action
        -- being attributed (or nobody: a poison tick, a bounced spell).
        local maxhp = M.readWord(0x3C1C + e * 2)
        if last ~= nil and last ~= 0xFFFF and last > 0 and hp == 0 and maxhp > 0
           and not deathSaid[e] then
          deathSaid[e] = true
          local from = last
          if monAct ~= nil and monAct.hp0[e] ~= nil and monAct.hp0[e] ~= 0xFFFF then
            from = monAct.hp0[e]
          end
          local bp = M.readByte(BP + e * 2)
          local pbp = {}
          for p = 0, 3 do pbp[#pbp + 1] = tostring(M.readByte(BP + p * 2)) end
          local oneAction = monAct ~= nil and from * 100 // maxhp >= ONE_SHOT_PCT
          if monAct ~= nil then
            monAct.kills = monAct.kills + 1
            if from >= maxhp then monAct.fullKills = monAct.fullKills + 1 end
          end
          local rec = { e = e, char = M.readByte(BCHID + e * 2), tick = battleTick,
                        from = from, maxhp = maxhp, bp = bp,
                        slot = monAct and monAct.slot, cmd = monAct and monAct.cmd,
                        atk = monAct and monAct.atk, oneAction = oneAction }
          battleDeaths[#battleDeaths + 1] = rec
          M.log(string.format("[%s] [death] f+%d entity %d char %d from %d/%d "
            .. "by %s%s bp=%d party_bp=%s%s", tag or "fight", battleTick, e,
            rec.char, from, maxhp,
            monAct and string.format("slot %d cmd $%02X atk $%02X", monAct.slot,
              monAct.cmd, monAct.atk) or "nobody (no monster action attributed)",
            oneAction and " (ONE ACTION from >= 80%)" or "", bp,
            table.concat(pbp, ","),
            bp >= BANKED_BP and string.format(" -- died holding %d BP", bp) or ""))
          if recovery then
            recovery.death(M.frame, { entity = e, char = rec.char, tick = battleTick,
              from = from, maxhp = maxhp, bp = bp, party_bp = table.concat(pbp, ","),
              slot = rec.slot, cmd = rec.cmd, atk = rec.atk, one_action = oneAction })
          end
        elseif hp > 0 and hp ~= 0xFFFF then
          deathSaid[e] = nil
        end
        partyHpLast[e] = hp
      end
      -- The [wipe] line (#175), once: the engine's own verdict (M.wipeVerdict
      -- via partyWipedInBattle, #166) with the pips every member held, and
      -- the classification the owner reads a wipe by -- a one-shot early
      -- in the fight is a level problem; three or more pips banked at a
      -- death is a driver problem ("we weren't trying our best").
      if not wipeSaid and M.partyWipedInBattle and M.partyWipedInBattle() then
        wipeSaid = true
        local pbp, ds = {}, {}
        for p = 0, 3 do pbp[#pbp + 1] = tostring(M.readByte(BP + p * 2)) end
        for _, d in ipairs(battleDeaths) do
          ds[#ds + 1] = string.format("e%d@f+%d:%d/%d:bp%d%s", d.e, d.tick, d.from,
            d.maxhp, d.bp, d.oneAction and ":one_action" or "")
        end
        local cls = M.wipeClass(battleDeaths, { onePct = ONE_SHOT_PCT,
          early = EARLY_TICKS, banked = BANKED_BP })
        M.log(string.format("[%s] [wipe] f+%d party_bp=%s deaths=%s class=%s",
          tag or "fight", battleTick, table.concat(pbp, ","),
          #ds > 0 and table.concat(ds, ";") or "none", cls))
      end
    end
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
      -- present-mask driven (see the focus note above: the old word-stride
      -- read here printed a slotless garbage list -- "all zero, monsters=3"
      -- -- that misdiagnosed a live board as dead).  The s%d: tag keeps
      -- slot identity in the log so that can never happen silently again.
      local mids = M.monsterIds()
      for s2 = 0, 5 do
        if mids[s2 + 1] ~= 0xFFFF then
          -- hp, and the shield count beside it: shields live at
          -- $3E38 + entity*2 and monsters are entities 4..9, so slot s is
          -- $3E40 + s*2.  Without the shield count the log shows low
          -- damage without showing the cause, since shielded damage is
          -- halved and a broken monster takes 4x.
          mhp[#mhp + 1] = string.format("s%d:%d/sh%d", s2,
            M.readWord(0x3BFC + s2 * 2), M.readByte(0x3E40 + s2 * 2))
        end
      end
      -- What a round has cost each member so far, beside their HP: it is what
      -- the heal policy decides on, and without it a log shows a driver
      -- declining to heal without showing why.
      local cost = {}
      for e = 0, 3 do cost[#cost + 1] = tostring(roundCost[e] or 0) end
      M.log(string.format("[%s] battle f+%d menu=%02X state=%02X actor=%d " ..
        "cursor=%d cmds=%s partyhp=%s roundcost=%s monhp=%s monsters=%d",
        tag or "fight", battleTick, menu, state,
        actor, M.readByte(CMDROW + actor) & 3,
        table.concat(rows, ","), table.concat(hp, ","),
        table.concat(cost, ","), table.concat(mhp, ","), M.monstersPresent()))
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
    -- the layout is read once the command window is up (InitBattle has
    -- run by then) and said at that moment, before any steer needs it
    if layout == nil then layoutOf() end
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
    -- One press per `cadence` frames, and the number affects outcomes: too
    -- slow a cadence costs decisions per fight, which can decide a close
    -- fight on input rate rather than the party.  6-on/6-off is still
    -- slower than a human pressing buttons, and it stays clear of the
    -- menu's auto-repeat threshold; callers that have a reason to be slow
    -- can ask for it.
    local ph = tick % (opts.cadence or 30)
    local actor = M.readByte(ACTOR) & 3
    if plan and planActor ~= actor then traceDrop("actor_changed"); plan, planActor = nil, nil end
    -- The stall guard's clock: frames spent on a LIVE lore plan, rather
    -- than wall clock since the first offer, so another actor's slow turn
    -- between two pursuits cannot fire it.
    if plan and plan.kind == "lore" then loreSpinN = loreSpinN + 1 end
    if ph == 0 then
      held = button(actor) or {}
      heldFast, held.fast = held.fast or false, nil
    end
    -- `fast`: three 5-on/5-off presses in the pulse instead of one 6-on;
    -- each is a distinct press to the menu (a release between), so no
    -- auto-repeat is involved and the count per pulse is exact.
    if heldFast then M.setPad(ph % 10 < 5 and held or {})
    else M.setPad(ph < 6 and held or {}) end
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


-- ---- the tile trace ---------------------------------------------------
-- Records which tiles the party actually stood on, per map, and emits them
-- as [tiles] log lines at each map change and at run end.  Read-only:
-- nothing written.  tools/chest_visibility.py harvests these lines from a
-- regen log and intersects them with the chest table.  Samples only at
-- tileAligned(), which keeps a mid-step direction-skewed coordinate out of
-- the record; battle and menu frames re-record the frozen field tile,
-- which the dedupe absorbs.
local traceMap, traceSet, traceCount = nil, {}, 0
local function traceFlush()
  if traceMap == nil or traceCount == 0 then return end
  local keys = {}
  for k in pairs(traceSet) do keys[#keys + 1] = k end
  table.sort(keys)
  local line = {}
  for i, k in ipairs(keys) do
    line[#line + 1] = k
    if #line == 120 or i == #keys then
      M.log(string.format("[tiles] map=%d n=%d xy=%s",
        traceMap, traceCount, table.concat(line, ",")))
      line = {}
    end
  end
  traceSet, traceCount = {}, 0
end

-- ---- CDL code coverage --------------------------------------------------
-- When OT6_COVERAGE is set, dump the "touched" bitmap for the OT6 code
-- ranges at run teardown.  emu.getCdlData(prgRom) returns one CdlFlags
-- byte per PRG-ROM offset, with 0x01 (Code) set once fetched as an opcode
-- and 0x02 (Data) set once read as data; we record 0x03 (either), so a
-- data table exercised by the run counts as touched.  The CDL is
-- per-process and starts empty each boot; lib/coverage_report.py unions
-- the per-test bitmaps and maps set bits back to routine names.
-- Read-only: nothing written.
--
-- The ranges track ff6/rom/ff6-en.map's ot6_code and ot6_c1 segments,
-- expressed as PRG-ROM offsets (CPU addr & 0x3FFFFF); coverage_report.py
-- carries the same {base,len} pairs in the same order and unpacks the
-- concatenated bitmap against them, so the two lists must stay in
-- lockstep.  emu.getCdlData returns a 0-indexed array, so read
-- cdl[offset] directly.
--
-- The on/off switch is the global OT6_COVERAGE, not an env var: Mesen's
-- Lua sandbox blocks os.getenv, so lib/compose.py injects
-- OT6_COVERAGE=true into the composed preamble when its own environment
-- has OT6_COVERAGE set.  Undefined for a normal run, so the
-- `not OT6_COVERAGE` guard makes this a no-op.
local COVERAGE_RANGES = { { 0x300000, 0x2C5C }, { 0x01FFE8, 0x0D } }
local coverageDone = false
local function coverageFlush()
  if coverageDone or not OT6_COVERAGE then return end
  coverageDone = true
  local ok, cdl = pcall(function()
    return emu.getCdlData(emu.memType.snesPrgRom)
  end)
  if not ok or type(cdl) ~= "table" then
    M.log("coverage: getCdlData unavailable (" .. tostring(cdl) .. ")")
    return
  end
  local total = 0
  for _, r in ipairs(COVERAGE_RANGES) do total = total + r[2] end
  local nbytes = math.floor((total + 7) / 8)
  local bytes = {}
  for i = 1, nbytes do bytes[i] = 0 end
  local bit = 0
  for _, r in ipairs(COVERAGE_RANGES) do
    local base, len = r[1], r[2]
    for off = 0, len - 1 do
      local flag = cdl[base + off] or 0
      if (flag & 0x03) ~= 0 then
        local idx = math.floor(bit / 8) + 1
        bytes[idx] = bytes[idx] | (1 << (bit % 8))
      end
      bit = bit + 1
    end
  end
  local chars = {}
  for i = 1, nbytes do chars[i] = string.char(bytes[i]) end
  M.emitBlob("coverage.cdl", table.concat(chars))
end

local function traceTick()
  if not M.tileAligned() then return end
  local m = M.mapId() & 0x1ff
  if m ~= traceMap then
    traceFlush()
    traceMap = m
  end
  local k = M.fieldX() .. ":" .. M.fieldY()
  if not traceSet[k] then
    traceSet[k] = true
    traceCount = traceCount + 1
  end
end

-- ============================================ the segment runner (#178) ====
-- Runs are bit-reproducible, so any additive route change -- buying ten more
-- Potions, one more grind lap -- reshuffles every later encounter, NPC walk
-- and back-attack roll.  A segment that passed on its one seed then turns
-- that edit into a red build (#179, #185).  Owner, 2026-09-16: "we must not
-- allow shifting randomness to become a blocker.  Robustness please."
--
-- So every segment gets three things here, none of which are the route's
-- business:
--
--   1. WATCHDOGS.  The run samples what it is looking at (a hash of the
--      frame buffer, the control cells, the progress cells, the pad) every
--      WATCH.sampleEvery frames and keeps a ring of them.  Pressing at a
--      screen that answers nothing (the #185 back attack: LEFT into a
--      target cursor that only RIGHT moves, 9000 frames of it) fails fast
--      as `no-effect` (a held L+R in a battle is the run mechanic and is
--      judged on the escape cells instead, see escapeSig; a battle list
--      being scrolled is judged on its cursor block, see listSig); a run that
--      goes visually and mechanically still fails fast as `no-progress`.
--      Fast, because a 9000-frame step budget
--      is a poor first line of defence: it burns eight minutes to say what
--      three seconds of samples already said.  The budgets stay as the
--      backstop.
--
--   2. RETRY FROM THE BOOT POINT.  A failure whose class is SEED-DEPENDENT
--      (a wipe, a navTo/worldNavTo "no path", a step timeout, a watchdog
--      trip, a recovery-cap trip) restores the snapshot taken at the run's
--      first frame, re-executes the generator's body from source -- fresh
--      closures, fresh per-run tables, fresh step objects -- and replays it
--      with the seed legitimately varied by idle frames at the boot point.
--      Up to opts.retries attempts (3 by default for a gen_* segment, 1 for
--      everything else).  A CONTRACT failure (assertEq, a checkpoint
--      contract, a Lua error) is a bug and fails at once: a retry must
--      never launder one.
--
--   3. THE COUNT.  Every attempt logs one greppable `[retry] attempt n/N`
--      line with its class, frame, seed phase and raw message (and, for a
--      wipe, the formation and every member's HP/BP), the verdict carries
--      `attempts=n/N`, and tools/audit_retries.py lists every log with
--      attempts > 1 so each class becomes an issue rather than a shrug.
--
-- HOW THE REPLAY IS CLEAN.  The step machine cannot be rewound: a step
-- object holds its own counters, driveUntil has no reset at all, and the
-- generator's own upvalues (blobs, ladder tallies, "did we already buy it"
-- flags) are the state that really matters.  So nothing is rewound.
-- lib/compose.py wraps everything after the `local H = dofile(...)` line in
-- `H.segmentBody(function() ... end)`, and an attempt is that function run
-- again: every local in the generator is constructed from scratch, H.run is
-- called again (it installs the new step list instead of re-arming the
-- runner), and the lib's own per-run state is reset by resetLibState below.
-- The previous attempt's emu callbacks go inert through the epoch shim.
--
-- WHY THE SNAPSHOT IS THE RUN'S FIRST FRAME rather than the post-load boot
-- state: the replayed body starts at ITS FIRST STEP, which is the fixture
-- load (or the cold Continue of a checkpoint).  Restoring a post-load boot
-- snapshot and then replaying a body that begins by loading that same
-- fixture reaches the same machine state either way, so the snapshot is
-- taken where the body starts, and the boot point is where the SEED
-- VARIATION goes in: M.bootMark (called by M.loadState when the fixture
-- load settles, and by assertEntryContract after a cold Continue) idles the
-- pad for this attempt's shift before the body walks on.  Frame budgets,
-- M.frame and the canary are per attempt; M.totalFrames counts the
-- emulator's own.
--
-- A GENERATOR WITH ITS OWN LADDER (gen_fc_alcove, gen_fc_escape,
-- gen_zozo4_dadaluma and the #163 ladders) is not double-retried: it runs
-- with allowGameOver, so its wipes never reach the canary, and when its
-- ladder is exhausted it raises its own message ("battle 69 not won in 3
-- attempts"), which classifies as `other` and fails at once.  What the
-- default catches for those files is the part their ladder never covered:
-- the climb to the fight (#185 is exactly that).  A segment that wants out
-- entirely passes opts.retries = 1.
--
-- MODULE-LEVEL STATE A GENERATOR CANNOT RESET: none in the tree today (the
-- body's own chunk is re-executed, so its file-scope locals are rebuilt).
-- A generator that parks state where the re-execution cannot reach it --
-- inside the lib, or in a global -- clears it from a hook registered with
-- H.onReplay(fn); every hook runs after the reload, before the body is
-- re-executed, and hooks do not carry over into the next attempt.
do

local WATCH = {
  sampleEvery     = 16,     -- frames between observations
  noEffectFrames  = 300,    -- 5s of game time pressing into no answer
  pressFraction   = 0.25,   -- ... with the pad down at least this often
  quietFrames     = 1800,   -- ~30s with neither the screen nor a progress
                            --     cell showing anything new
  memoryFrames    = 900,    -- how long a sampled signature counts as "seen"
  escapeQuiet     = 600,    -- a held L+R is an escape in progress while the
                            --     run counters moved this recently (measured
                            --     128-160 frames apart per character, below)
  ringSize        = 24,
  recoveryCap     = 3,      -- drops of the same plan in one battle
  screenStride    = 7,      -- frame-buffer sampling stride for the hash
}
M.WATCH = WATCH

local RUN                   -- the current attempt; filled in below

-- Where the seed variation goes when a body marks no boot point of its own
-- (M.bootMark, below).  Late enough that a cold Continue has landed and
-- asserted its entry contract first (measured f1035..f1456 across the
-- checkpoint-booted generators' logs), so only a body with neither a
-- fixture nor a contract ever reaches it.
local BOOT_FALLBACK = 2400

-- A retry whose first battle repeats an earlier attempt's is re-run at the
-- next untried shift REROLL_STEP further on (7 is coprime to the 60-phase
-- period, so the walk reaches every phase), at most MAX_REROLLS times.
local REROLL_STEP, MAX_REROLLS = 7, 8

-- An idle whose game clock has not moved its shift's worth of ticks after
-- this many frames past the shift ends anyway, and says so.
local IDLE_SLACK = 600

-- ---------------------------------------------------------- observation --
-- Everything here is read-only: frame-buffer reads, RAM reads, and the pad
-- the script itself is holding.

local function screenHash()
  local ok, buf = pcall(emu.getScreenBuffer)
  if not ok or type(buf) ~= "table" then return nil end
  local h, n = 2166136261, #buf
  for i = 1, n, WATCH.screenStride do
    h = ((h ~ (buf[i] & 0xFFFFFF)) * 16777619) & 0xFFFFFFFF
  end
  return h
end

local function monsterHpSum()
  if not M.battleLoadStarted() then return 0 end
  local ids, s = M.monsterIds(), 0
  for i = 1, 6 do
    if ids[i] ~= 0xFFFF then s = s + M.readWord(0x3BFC + (i - 1) * 2) end
  end
  return s
end

local function invSum()
  local s = 0
  for i = 0, 255 do s = s + M.readByte(0x1969 + i) end
  return s
end

-- The ESCAPE cells: what a held L+R moves.  CheckRunAway
-- (battle_main.asm, "try to run away") runs on every character's ATB tick
-- while $2F45 -- the engine's own "L+R is down" latch, set by the graphics
-- half when it reads the pad -- is set: it adds random($3D71,x)+1 to that
-- character's run counter $3D70,x, and when the counter reaches the run
-- difficulty $3A3B it sets the character's bit in $3A38 (just escaped),
-- which becomes $3A39 (left the battle) when the run action resolves.
-- Measured 2026-09-16 (probe_escape_cells.lua, the crescent_landing world
-- random that tripped the first version of this rule, TERRA/LOCKE vs two
-- Behemoth-class monsters, $3A3B=4): with L+R held from the first battle
-- frame $2F45 went 0->1 at +133 frames, the counters moved at +245, +373,
-- +389, +533, +661 (128-160 frames apart per character), $3A38 set at
-- +373 and +533, and the party was out at +837 -- 544 frames after the
-- command window opened.  The same snapshot with the pad released: none
-- of these cells moved.  The ATB gauges sit full under the open window in
-- both branches, so they say nothing.
local function escapeSig()
  return string.format("%02X.%02X.%02X.%02X%02X%02X%02X",
    M.readByte(0x2F45), M.readByte(0x3A38), M.readByte(0x3A39),
    M.readByte(0x3D70), M.readByte(0x3D72),
    M.readByte(0x3D74), M.readByte(0x3D76))
end

-- The formation refuses to run: $B1 bit 1 (set for a pincer, or by a
-- monster whose "can't run" flag is set -- UpdateMonsterGfxBuf) or the
-- formation's own "L+R has no effect" bit, $2F4B bit 0 (event battles).
-- Checked BEFORE the escape cells: the run counters tick in such a
-- formation too (measured 2026-09-16 on the Whelk fight, $B1=07 $2F4B=0C,
-- counters 03,01,03 -> 06,03,05 under a held L+R; probe_noeffect_cantrun),
-- it is the run command itself that refuses ("can't run away!!", Cmd_2a).
local function cantRun()
  return (M.readByte(0x00B1) & 0x02) ~= 0 or (M.readByte(0x2F4B) & 0x01) ~= 0
end

-- The list windows' cursor block.  btlgfx_ram.inc reserves $890F..$896E
-- as 24 four-byte tables, one byte per actor (indexed by $62CA), and each
-- battle list keeps its scroll offset, column and in-window row there
-- (btlgfx_main.asm UpdateMenuState_0a/0e/1b/1e/21/2d/30 and the get_*_poi
-- readers; GetCursorInput moves the row inside the window and asks the
-- list handler to scroll only past its last line):
--   $890F command row              $8913/17/1B magic scroll/col/row
--   $891F/23/27 lore scroll/col/row  $892B/2F/33 rage scroll/col/row
--   $8937/3B the state-$21 list      $893F/43 magitek
--   $8947/4B/4F item scroll/col/row  $8953/57/5B throw scroll/col/row
--   $895F/63/67 tools scroll/col/row $896B
-- A DOWN into a long list is answered here and nowhere the earlier
-- signature looked (actor 0's $890F and $891F, whichever actor's menu was
-- up): the menu state only alternates between the list and its
-- scroll-animation state ($0A/$17 for items), both seen before, and the
-- in-window row sits on the last line while the scroll offset walks.
-- Measured 2026-09-16 on vector_crash's BASEMENT 3 random: the driver's
-- 43-row walk to the Potion read as "no-effect: down for 304 frames at
-- B:01.0A.03.00.00.00.00.00" on all three attempts (probe_list_scroll.lua
-- has the per-cell trace).  Printed per list so the ring names the cell.
local function listSig()
  local a = M.readByte(0x62CA) & 3
  local function b(addr) return M.readByte(addr + a) end
  return string.format("c%02X m%02X.%02X.%02X l%02X.%02X.%02X g%02X.%02X.%02X "
    .. "u%02X.%02X k%02X.%02X i%02X.%02X.%02X t%02X.%02X.%02X o%02X.%02X.%02X x%02X",
    b(0x890F),
    b(0x8913), b(0x8917), b(0x891B),
    b(0x891F), b(0x8923), b(0x8927),
    b(0x892B), b(0x892F), b(0x8933),
    b(0x8937), b(0x893B),
    b(0x893F), b(0x8943),
    b(0x8947), b(0x894B), b(0x894F),
    b(0x8953), b(0x8957), b(0x895B),
    b(0x895F), b(0x8963), b(0x8967),
    b(0x896B))
end

-- The CONTROL cells: what an input is supposed to move.  Party HP is
-- deliberately NOT here -- monsters chewing through the party while the
-- script presses an inert direction is exactly the #185 hang, and counting
-- that as movement is how it ran for 9000 frames.
local function ctlSig()
  if M.battleLoadStarted() then
    return string.format("B:%02X.%02X.%02X.%02X.%02X.%02X %s",
      M.readByte(0x7BCA),          -- menu byte
      M.readByte(0x7BC2),          -- menu state ($38 = target select)
      M.readByte(0x62CA) & 3,      -- whose menu
      M.readByte(0x7B7D),          -- target mask: party side
      M.readByte(0x7B7E),          -- target mask: monster side
      M.readByte(0x7B7F),          -- all-target flag
      listSig())                   -- the list windows' cursor block
  end
  if M.worldMode and M.worldMode() then
    return string.format("W:%d.%d.%d.%d.%d", M.worldX(), M.worldY(),
      M.readByte(0x0059), M.dialogWaiting() and 1 or 0,
      M.readByte(0x004b))
  end
  return string.format("F:%d.%d.%d.%d.%d.%d.%02X.%02X",
    M.mapId() & 0x1ff, M.fieldX(), M.fieldY(),
    M.readByte(0x0059), M.dialogWaiting() and 1 or 0,
    M.eventRunning() and 1 or 0, M.readByte(0x004b), M.readByte(0x1eb9))
end

-- The PROGRESS cells: ctl plus everything a segment can be making headway
-- on without moving a control cell -- damage out, damage in, shopping.
local function progSig(ctl)
  local php = 0
  for e = 0, 3 do
    local h = M.readWord(0x3BF4 + e * 2)
    if h < 10000 then php = php + h end
  end
  local esc = (ctl:sub(1, 2) == "B:") and ("|e" .. escapeSig()) or ""
  return string.format("%s|m%d|p%d|i%d%s", ctl, monsterHpSum(), php, invSum(),
    esc)
end

local W = {}
local function watchReset()
  W.samples = {}
  W.seenCtl, W.seenProg, W.seenScreen, W.pressAt = {}, {}, {}, {}
  W.lastNewCtl, W.lastNewProg, W.lastNewScreen = 0, 0, 0
  W.prevCtl, W.lastDiffCtl, W.lastUnanswerable, W.lastInert = nil, 0, 0, 0
  W.maxQuietCtl, W.maxQuietProg, W.maxQuietScreen = 0, 0, 0
  W.samplesTaken, W.pressFrames = 0, 0
  W.suppressUntil, W.trips = 0, 0
  W.battleEpoch, W.inBattle, W.recovery = 0, false, {}
  W.prevEsc, W.lastEscMove, W.escSaid, W.cantRunSaid = nil, 0, false, false
  W.prevList, W.lastListMove = nil, 0
end
watchReset()
W.enabled = false

-- A step that is SUPPOSED to sit still says so, and the watchdogs stand
-- down for that long: M.waitFrames does it for a long wait, and a
-- generator or driver can do it explicitly around a cutscene.
function M.watchQuiet(frames, why)
  local untilFrame = M.frame + (frames or 0)
  if untilFrame > W.suppressUntil then
    W.suppressUntil = untilFrame
    if why then
      M.log(string.format("[watch] standing down for %d frames: %s",
        frames, why))
    end
  end
end

local function padString()
  local held = {}
  for _, b in ipairs(ALL_BTN) do if curPad[b] then held[#held + 1] = b end end
  return (#held > 0) and table.concat(held, "+") or "--"
end

local function ringDump(tag)
  M.log(string.format("[watch] ring at the %s trip, oldest first "
    .. "(pad = held buttons, screen = frame-buffer hash, ctl/prog = the "
    .. "state signatures):", tag))
  for _, s in ipairs(W.samples) do
    M.log(string.format("[watch]   f%-7d pad=%-16s screen=%s ctl=%s prog=%s",
      s.frame, s.pad, s.screen and string.format("%08X", s.screen) or "-",
      s.ctl, s.prog))
  end
end

-- Every distinct press the window saw, so the FAIL line names the input
-- that was getting no answer rather than just this frame's pad.
local function pressedIn(frames)
  local seen, out = {}, {}
  for f, p in pairs(W.pressAt) do
    if f >= M.frame - frames and p ~= "--" and not seen[p] then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  table.sort(out)
  return (#out > 0) and table.concat(out, ",") or "--"
end

local function pressFramesIn(frames)
  local n = 0
  for f in pairs(W.pressAt) do if f >= M.frame - frames then n = n + 1 end end
  return n
end

-- The evidence a fast failure leaves: the screen it failed at, and the
-- ring.  The tag names a file run.sh decodes into the run workspace (and
-- publishes to build/states/shots on a pass, retries included).
local function failEvidence(kind)
  local tag = string.format("watchdog_%s_a%d_f%d", kind, RUN.attempt, M.frame)
  M.screenshot(tag)
  ringDump(kind)
  local dir = (type(OT6_ART_DIR) == "string" and OT6_ART_DIR ~= "")
    and OT6_ART_DIR or "<the retained run workspace>/artifacts"
  return string.format("%s/shots/%s.png", dir, tag)
end

local function prune(tbl, keepFrom)            -- signature -> frame seen
  for k, f in pairs(tbl) do if f < keepFrom then tbl[k] = nil end end
end
local function pruneKeys(tbl, keepFrom)        -- frame -> pad held
  for f in pairs(tbl) do if f < keepFrom then tbl[f] = nil end end
end

-- One observation, plus the two verdicts.  Returns an error message -- the
-- runner routes it through the same failure path as a raised step error, so
-- a watchdog trip is retried exactly like the wipe it precedes -- or nil.
local function watchTick()
  local held = padString()
  if held ~= "--" then
    W.pressFrames = W.pressFrames + 1
    W.pressAt[M.frame] = held
  end
  local battle = M.battleLoadStarted()
  if battle and not W.inBattle then
    W.battleEpoch, W.recovery = W.battleEpoch + 1, {}
    W.prevEsc, W.lastEscMove, W.escSaid, W.cantRunSaid = nil, M.frame, false, false
    W.prevList, W.lastListMove = nil, M.frame
  end
  W.inBattle = battle
  if M.frame % WATCH.sampleEvery ~= 0 then return nil end

  local ok, ctl = pcall(ctlSig)
  if not ok or type(ctl) ~= "string" then return nil end
  local okp, prog = pcall(progSig, ctl)
  if not okp then return nil end
  local screen = screenHash()

  if not W.seenCtl[ctl] then W.lastNewCtl = M.frame end
  W.seenCtl[ctl] = M.frame
  if ctl ~= W.prevCtl then W.lastDiffCtl = M.frame end
  W.prevCtl = ctl
  local inBattle = ctl:sub(1, 2) == "B:"
  if inBattle and ctl:sub(1, 4) == "B:00" then W.lastUnanswerable = M.frame end
  -- A menu still open after the last monster died is the engine winding
  -- the fight down (death animation, the victory fade) under a window it
  -- will close itself; the driver's B presses there are inert by design
  -- (measured 2026-09-16 on the Zozo street: three trips, every one with
  -- monster HP summing to 0 under an open command list)
  if inBattle and monsterHpSum() == 0 then W.lastUnanswerable = M.frame end
  -- A held L+R in a battle is the run mechanic, and the engine answers it
  -- in the escape cells (escapeSig above), not in the menu cells: the
  -- command window stays open and unmoving for the whole count.  So while
  -- L+R is held and the formation can be run from, the press is answered
  -- as long as the escape cells have moved within WATCH.escapeQuiet; it
  -- is a real no-effect only when the formation refuses to run (the
  -- can't-run bits) or those cells have gone still.  Measured 2026-09-16
  -- on crescent_landing's first world random: three false trips of the
  -- first version, every one 300 frames of "l+r" under an open window
  -- with the run counters ticking (probe_escape_cells.lua).
  local escapeLive = false
  if inBattle then
    local esc = escapeSig()
    if esc ~= W.prevEsc then W.lastEscMove = M.frame end
    W.prevEsc = esc
    -- The list cursor block is judged on IDENTITY, sample to sample, not
    -- on novelty: the same actor walking the same rows to the same Potion
    -- on its next turn revisits every signature of its last walk inside
    -- WATCH.memoryFrames, and that is the list answering each press, not
    -- a press the game ignores.  A list that has hit its end under a held
    -- DOWN stops moving here and trips like anything else.
    local lst = listSig()
    if lst ~= W.prevList then W.lastListMove = M.frame end
    W.prevList = lst
    if curPad.l and curPad.r then
      if cantRun() then
        if not W.cantRunSaid then
          W.cantRunSaid = true
          M.log(string.format("[watch] L+R held at f%d but this formation "
            .. "cannot be run from ($B1=%02X $2F4B=%02X): the press counts "
            .. "as unanswered", M.frame, M.readByte(0x00B1),
            M.readByte(0x2F4B)))
        end
      else
        escapeLive = (M.frame - W.lastEscMove) < WATCH.escapeQuiet
        if escapeLive and not W.escSaid and M.readByte(0x2F45) ~= 0 then
          W.escSaid = true
          M.log(string.format("[watch] escape in progress at f%d: L+R held, "
            .. "$2F45 set, run difficulty $%02X, counters %s -- the run "
            .. "count answers the press, not the menu", M.frame,
            M.readByte(0x3A3B), esc))
        end
      end
    end
  end
  -- On the field and the world map only a press the game COULD answer
  -- counts: a held direction while the party has control (a walk), or
  -- any press with a dialog or a menu up.  A tapped A through a scripted
  -- walk or a cutscene is what a person does while the game is busy, and
  -- the game legitimately does not answer it yet (measured 2026-09-16 on
  -- gen_vargas: the Kolts intro, A tapped 151 of 300 frames at an
  -- unchanging tile while the scene played; and on gen_arvis's Narshe
  -- cutscenes).  Anything else marks the sample inert.
  if not inBattle then
    local dirHeld = curPad.up or curPad.down or curPad.left or curPad.right
    local walking = dirHeld and ((M.worldMode and M.worldMode())
      and M.worldHasControl() or M.hasControl())
    local windowUp = M.dialogWaiting() or M.readByte(0x0059) ~= 0
    if not (walking or windowUp) then W.lastInert = M.frame end
  end
  if not W.seenProg[prog] then W.lastNewProg = M.frame end
  W.seenProg[prog] = M.frame
  if screen then
    if not W.seenScreen[screen] then W.lastNewScreen = M.frame end
    W.seenScreen[screen] = M.frame
  end
  local keepFrom = M.frame - WATCH.memoryFrames
  prune(W.seenCtl, keepFrom)
  prune(W.seenProg, keepFrom)
  prune(W.seenScreen, keepFrom)
  pruneKeys(W.pressAt, keepFrom)

  W.samples[#W.samples + 1] =
    { frame = M.frame, pad = held, screen = screen, ctl = ctl, prog = prog }
  if #W.samples > WATCH.ringSize then table.remove(W.samples, 1) end
  W.samplesTaken = W.samplesTaken + 1

  local qc, qp, qs = M.frame - W.lastNewCtl, M.frame - W.lastNewProg,
                     M.frame - W.lastNewScreen
  if qc > W.maxQuietCtl then W.maxQuietCtl = qc end
  if qp > W.maxQuietProg then W.maxQuietProg = qp end
  if qs > W.maxQuietScreen then W.maxQuietScreen = qs end

  if not W.enabled or M.frame < W.suppressUntil then return nil end
  -- and not before this attempt has a window's worth of samples
  if M.frame < WATCH.noEffectFrames + WATCH.sampleEvery then return nil end

  -- Two shapes of "no effect", measured on gen_zozo4_dadaluma's climb
  -- (2026-09-16, the three false trips of the first version):
  --
  --  * In a BATTLE the press must land on an open menu for the whole
  --    window -- with no menu open ($7BCA=0) the drivers edge-tap A
  --    through the fly-in, the enemy's turns and the victory text, and
  --    that is waiting, not pressing into a wall (trip 1: 96 A-frames in
  --    192 at the first fight's opening; trip 2: a window that was
  --    menu-closed for 23 of its 24 samples).  With the menu open, the
  --    verdict is NOVELTY over the window: a driver that cycles between
  --    two states it has already been in (#185: target select $38, drop,
  --    command list $05, re-plan, $38 ...) is not moving anything, and a
  --    consecutive-identity test would never see it.
  --  * On the FIELD or the world map the verdict is IDENTITY: the same
  --    control cells at every sample of the window, every sample an
  --    answerable press (above), AND the screen itself unchanged for the
  --    window -- a screen that is still changing is a game still busy,
  --    whatever the cells say.  A walk that re-plans around a wandering
  --    NPC revisits the same three tiles for seconds (trip 3, the Zozo
  --    street), and that is the route working.  The screen rule is
  --    field-only on purpose: a battle's screen animates whether or not
  --    a press is answered (ATB, idle sprites, the damage numbers of the
  --    #185 hang itself), so there the menu cells are the screen's
  --    answer.
  local pressed = pressFramesIn(WATCH.noEffectFrames)
  local N = WATCH.noEffectFrames
  local stuck
  if inBattle then
    stuck = (M.frame - W.lastUnanswerable) >= N and qc >= N and not escapeLive
      and (M.frame - W.lastListMove) >= N
  else
    stuck = (M.frame - W.lastDiffCtl) >= N and (M.frame - W.lastInert) >= N
      and qs >= N
  end
  if stuck and pressed >= WATCH.pressFraction * N then
    W.trips = W.trips + 1
    local shot = failEvidence("noeffect")
    local escNote = ""
    if inBattle then
      escNote = string.format("  The list cursor block (%s) last moved %d "
        .. "frames ago.", listSig(), M.frame - W.lastListMove)
    end
    if inBattle and curPad.l and curPad.r then
      escNote = escNote .. (cantRun()
        and string.format("  L+R is held but this formation cannot be run "
          .. "from ($B1=%02X $2F4B=%02X).", M.readByte(0x00B1),
          M.readByte(0x2F4B))
        or string.format("  L+R is held and the formation can be run from, "
          .. "but the escape cells (%s) have not moved for %d frames.",
          escapeSig(), M.frame - W.lastEscMove))
    end
    return string.format("no-effect: %s for %d frames at %s -- the pad has "
      .. "been down %d of the last %d frames and no control cell has read "
      .. "anything new in that time (the screen last changed %d frames "
      .. "ago).%s  This is a press the game is not answering, not a slow "
      .. "step.  Screenshot %s; ring above.",
      pressedIn(WATCH.noEffectFrames), qc, ctl, pressed,
      WATCH.noEffectFrames, qs, escNote, shot)
  end

  if qp >= WATCH.quietFrames and qs >= WATCH.quietFrames then
    W.trips = W.trips + 1
    local shot = failEvidence("noprogress")
    return string.format("no-progress: nothing has moved for %d frames at "
      .. "%s -- no map, position, menu, dialog, monster HP, party HP or "
      .. "inventory change, and no new frame on screen either.  A step that "
      .. "means to sit this still declares it with H.watchQuiet(n).  "
      .. "Screenshot %s; ring above.", math.min(qp, qs), prog, shot)
  end
  return nil
end

local function watchReport()
  M.log(string.format("[watch] %d samples, pad down %d frames, %d trip(s); "
    .. "max quiet: ctl=%d prog=%d screen=%d frames (thresholds: no-effect "
    .. "%d with the pad down %d%% of it, no-progress %d on prog AND screen)",
    W.samplesTaken, W.pressFrames, W.trips, W.maxQuietCtl, W.maxQuietProg,
    W.maxQuietScreen, WATCH.noEffectFrames,
    math.floor(WATCH.pressFraction * 100), WATCH.quietFrames))
  -- the fight drivers' unknown-menu ledger (#188), so the count sits
  -- beside the verdict of every run rather than in a table nobody measured
  M.log("[watch] " .. M.unknownMenuReport())
end

-- The recovery cap (#185's other half).  A driver that drops its plan and
-- backs out calls this once per drop; past WATCH.recoveryCap drops of the
-- same plan in the same battle it is not recovering, it is cycling, and the
-- run says so now rather than after forty of them.
--
-- Wired into the fight driver at both of its drop sites: the `parkN > 12`
-- "parked %d pulses in known state" drop (key `<kind>/<state>`) and the
-- pulse-budget drop (key `budget:<kind>/<state>`), so drop #4 of the same
-- plan in the same menu state is a counted, retried fast failure with a
-- screenshot (#185 reached #40 before it was).
function M.recoveryCount(tag, key, cap)
  local k = tostring(tag) .. "|" .. tostring(key)
  local n = (W.recovery[k] or 0) + 1
  W.recovery[k] = n
  cap = cap or WATCH.recoveryCap
  if n > cap then
    local shot = failEvidence("recovery")
    error(string.format("recovery cap: %s dropped and re-planned %s %d "
      .. "times in one battle (cap %d).  That is a cycle, not a recovery: "
      .. "the state it keeps returning to is not answering the plan.  "
      .. "Screenshot %s; ring above.", tostring(tag), tostring(key), n, cap,
      shot), 0)
  end
  return n
end

-- ------------------------------------------------------- failure classes --
-- Seed-dependent: the same route on another seed can pass, so it is
-- retried.  Everything else is a bug and fails at once.
local RETRYABLE = {
  wipe = true, nopath = true, timeout = true,
  noeffect = true, noprogress = true, recovery_cap = true,
}

local function classify(msg)
  msg = tostring(msg)
  -- Contract first: an assert that happens to mention a path or a timeout
  -- is still an assert.
  if msg:find("assertEq failed", 1, true)
     or msg:find("CONTRACT DIFF", 1, true)
     or msg:find("entry contract", 1, true)
     or msg:find("exit contract", 1, true) then return "assert" end
  if msg:find("no-effect:", 1, true) then return "noeffect" end
  if msg:find("no-progress:", 1, true) then return "noprogress" end
  if msg:find("recovery cap:", 1, true) then return "recovery_cap" end
  if msg:find("no path", 1, true) then return "nopath" end
  if msg:find("timeout after", 1, true) then return "timeout" end
  -- Only the lib's own wipe texts: the canary's verdict and the
  -- unladdered encounter canary.  A generator's ladder reports its last
  -- loss inside its own exhaustion message ("not won in 3 attempts --
  -- last loss: PARTY WIPED at f..."), and that is a ladder that already
  -- retried, whose verdict is the balance finding: `other`, no re-roll.
  if msg:find("THE PARTY IS WIPED", 1, true)
     or msg:find("^GAME OVER fired") then return "wipe" end
  return "other"
end
M.classifyFailure = classify

-- ----------------------------------------------------------- the attempt --
RUN = {
  attempt = 1, attempts = 1, phase = "run", root = nil, opts = {},
  budget = 60000, shift = 0, gap = 20, idle = 0, idlePad = nil,
  bootMarked = false, s0 = nil, s0blob = nil, ld = nil, ldWait = 0,
  failures = {}, lastBattle = nil, epoch = 1, installing = false,
  goUnhandled = nil,   -- { frame, what }: a counted game over no reload answered (#205)
  firstBattle = nil,   -- this attempt's first battle, as the seed store saw it (#208)
  firstBattles = {},   -- every earlier attempt's (and probe sample's), oldest first
  nextShift = nil,     -- a replay's shift chosen by the caller, not the gap ladder
  reroll = false,      -- the replay in flight re-runs this attempt (no count)
  rerolls = 0,
  tried = {},          -- shift % 60 -> true, every shift an attempt has run
  idleArm = false, idleMoved = 0, idleFrames = 0, idlePrev = 0,
  bootFrame = nil,     -- M.frame at this attempt's boot point
  probe = nil,         -- OT6_SHIFT_PROBE: { stride, shift, rows = {} }
  trace = nil,         -- probe mode: $021e / control transitions after the boot point
}
M.totalFrames = 0

-- What the earlier attempts of this run fell to, oldest first: one record
-- { attempt, class, msg, frame, context } per `[retry] attempt n/N FAILED`
-- line (`context` is the wipe context line's text, for class wipe only).
-- Read-only, and empty on a first attempt.  A negative-control suite
-- (watchdog_cantrun, watchdog_listend) spends attempt 1 on a press the
-- game is known not to answer and attempt 2 asserting that attempt 1 fell
-- to the watchdog with the expected class and message, so the exemption
-- under test is a red suite the day it widens (#200).
function M.attemptFailures()
  local out = {}
  for i, f in ipairs(RUN.failures) do
    out[i] = { attempt = f.attempt, class = f.class, msg = f.msg,
               frame = f.frame, context = f.context }
  end
  return out
end

local replayHooks = {}
function M.onReplay(fn) replayHooks[#replayHooks + 1] = fn end

-- The epoch shim: every callback a body registers is wrapped so the
-- previous attempt's copies stop firing (Mesen will not let them be
-- removed from outside a CPU callback).  Installed once, before the first
-- attempt runs.  Removal still works: the shim hands back Mesen's own ref.
local shimmed = false
local function installShim()
  if shimmed then return end
  shimmed = true
  emu.addMemoryCallback = function(fn, ...)
    local mine = RUN.epoch
    return rawAddMemoryCallback(function(...)
      if mine ~= RUN.epoch then return end
      return fn(...)
    end, ...)
  end
  emu.addEventCallback = function(fn, ...)
    local mine = RUN.epoch
    return rawAddEventCallback(function(...)
      if mine ~= RUN.epoch then return end
      return fn(...)
    end, ...)
  end
end

-- compose.py wraps everything after the `local H = dofile(...)` line in a
-- call to this, so the runner can replay the body.  A script composed
-- before this existed (or composed by hand) simply never calls it: the
-- runner then reports that retries are unavailable rather than pretending.
function M.segmentBody(fn)
  M.__body = fn
  installShim()
  fn()
end

-- Called by M.loadState once the fixture is in, and by assertEntryContract
-- once a cold Continue has landed: the point the replay is equivalent
-- from, and where this attempt's seed variation goes in.
function M.bootMark(what)
  if RUN.bootMarked then return end
  RUN.bootMarked = true
  RUN.bootFrame = M.frame
  if RUN.probe then RUN.trace = { n = 0, key = nil, prev = M.seedPhase() } end
  M.log(string.format("[retry] boot point: %s at f%d (attempt %d/%d, "
    .. "$021e=%d, seed shift %d idle frames)", tostring(what), M.frame,
    RUN.attempt, RUN.attempts, M.seedPhase(), RUN.shift))
  -- The idle is owed from THIS frame (#208).  bootMark runs inside a step's
  -- tick, and seqStep carries straight on into the next step in the same
  -- tick: gen_fc_landing's held RIGHT was set on the boot frame itself, the
  -- world map latched it at that frame's input poll, the walk onto
  -- Thamasa and its 60-frame load (the game clock stopped) ran on the
  -- game's own clock, and an idle that only began on the NEXT frame was
  -- swallowed whole: shifts 0..59 all fought the same first battle.  So
  -- the pad is captured and neutralised AFTER this frame's tick (the
  -- runner's frame(), below), before the game polls it, and handed back
  -- when the idle ends.  The idle's length is the game clock's own
  -- movement ($021e ticks summed, as newSeedLadder counts them), not a
  -- frame count, so a boot point that sits in a stopped clock (a map load,
  -- a fade the module does not tick through) still moves the seed.
  if RUN.shift > 0 then
    RUN.idle = RUN.shift
    RUN.idleArm = true
    RUN.idleMoved, RUN.idleFrames, RUN.idlePrev = 0, 0, M.seedPhase()
  end
end

-- What the fight was, for the attempt line.  Sampled while a battle is up,
-- so it is still readable after the teardown a wipe runs into.  Not
-- resampled once the table reads wiped (battleLoadStarted holds through
-- the Annihilated screen, #205): the last living reading -- the HP and
-- pips the party carried into the killing round -- is the context a loss
-- wants, and the [death] lines carry the exact figures.
local function sampleBattle()
  if M.partyWipedInBattle and M.partyWipedInBattle() and RUN.lastBattle then return end
  local seats = {}
  for e = 0, 3 do
    local a = M.readByte(0x3ed8 + e * 2)
    seats[#seats + 1] = (a == 0xFF) and "-" or
      string.format("a%d:%d/%d bp%d", a, M.readWord(0x3bf4 + e * 2),
        M.readWord(0x3c1c + e * 2), M.readByte(0x3e9c + e * 2))
  end
  local w = M.formationWords()
  RUN.lastBattle = {
    frame = M.frame,
    formation = string.format("%04X %04X %04X %04X %04X %04X",
      w[1], w[2], w[3], w[4], w[5], w[6]),
    seats = table.concat(seats, " "),
  }
end

-- ------------------------------------------------ the first battle (#208) --
-- What a seed shift is FOR is a different first battle, so every attempt
-- records the RNG state its first battle starts from, at InitBattle's
-- seed store (M.seedStoreAddr, the exec watch newSeedLadder uses):
--   $be      the battle seed about to be stored, ($021e * 4) & $FF: the
--            whole in-battle stream (battle Rand walks RNGTbl from it)
--   $11E0    the battle group the field or the event handed the battle
--   $1F6D    the field Rand index (field/reset.asm Rand)
--   $1FA1-4  the random-encounter indices/counters (field/battle.asm
--            UpdateBattleRng / UpdateBattleGrpRng): the NEXT encounter
-- Those cells are the key.  Two attempts with the same key fight the same
-- first battle from the same party (nothing before it differed but the
-- frame), so they are one sample: a whole multiple of the 60-frame phase
-- period lands on the same seed, and a shift the game absorbed (an idle
-- inside a wait that ends on the game's own clock) lands on the same frame.
-- The frame and $021e are logged beside the key, not in it.
local function firstBattleKey(seed, grp)
  return string.format("be%02X-g%04X-r%02X-e%02X%02X%02X%02X", seed, grp,
    M.readByte(0x1f6d), M.readByte(0x1fa1), M.readByte(0x1fa2),
    M.readByte(0x1fa3), M.readByte(0x1fa4))
end
M.firstBattleKey = firstBattleKey

-- Probe mode (OT6_SHIFT_PROBE): the transitions of the game clock and of
-- control from the boot point on -- whether $021e ticked on this frame,
-- whether the player can act (field or world), whether the pad is down --
-- so a shift the game swallows shows WHERE it was swallowed.
local TRACE_FRAMES = 1200
local function seedTraceTick()
  local t = RUN.trace
  if not t or t.n >= TRACE_FRAMES then return end
  t.n = t.n + 1
  local ph = M.seedPhase()
  -- A running clock can read unmoved for one sampled frame (it is ticked at
  -- the end of the owning module's vblank; newSeedLadder's note), so it
  -- reads STOP only after two still frames in a row.
  t.still = ((ph - t.prev) % M.SEED_PERIOD) == 0 and (t.still or 0) + 1 or 0
  t.prev = ph
  local ctl = M.hasControl() or (M.worldHasControl and M.worldHasControl()) or false
  local pad = false
  for _, v in pairs(curPad) do if v then pad = true break end end
  if pad and not t.pressed then
    t.pressed = true
    M.log(string.format("[seedprobe] trace f%d (boot+%d) $021e=%d: the body's "
      .. "first press after the boot point reaches the pad", M.frame,
      M.frame - (RUN.bootFrame or 0), ph))
  end
  local key = string.format("clock=%s control=%s idle=%s",
    t.still >= 2 and "STOP" or "tick", ctl and "yes" or "no",
    RUN.idle > 0 and "yes" or "no")
  if key ~= t.key then
    t.key = key
    M.log(string.format("[seedprobe] trace f%d (boot+%d) $021e=%d %s map=%d",
      M.frame, M.frame - (RUN.bootFrame or 0), ph, key, M.readWord(0x1f64) & 0x3ff))
  end
end

local function resetLibState()
  RUN.epoch = RUN.epoch + 1          -- the old attempt's callbacks go inert
  M.frame = 0
  M.gameOverFired = 0
  M.thawPad()
  M.setPad(nil)
  M.vars = {}
  M.lastState = nil
  M.absorbGuardBattles, M.absorbGuardClashes = 0, 0
  guardArmed, guardSettle = true, 0
  traceMap, traceSet, traceCount = nil, {}, 0
  recoveryObserver, recoveryHooks, recoveryEvents = nil, false, {}
  execActor, execActorCmd, execDone, execMon, execMonDone = nil, nil, {}, nil, nil
  execParty, execSkipped = nil, {}
  execHooks = false
  M._killbitFired = false
  watchReset()
  RUN.bootMarked, RUN.idle, RUN.idlePad, RUN.idleArm = false, 0, nil, false
  RUN.lastBattle, RUN.goUnhandled = nil, nil
  RUN.firstBattle, RUN.bootFrame, RUN.trace, RUN.pendingFirst = nil, nil, nil, nil
  local hooks = replayHooks
  replayHooks = {}
  for _, fn in ipairs(hooks) do pcall(fn) end
end

-- --------------------------------------------------------------- M.run ----
-- The runner.  steps: list of step objects.  opts.maxFrames: per-attempt
-- budget.  opts.retries: attempts allowed (default 3 for a gen_* segment,
-- 1 otherwise; OT6_RETRIES from the environment overrides both, which is
-- how tools/tests/seed_sweep.py turns retries off).  opts.watchdog:
-- true/false to force the fast-failure watchdogs on or off (default: on
-- for a segment, observation-only elsewhere).
local runnerStarted = false

function M.run(opts, steps)
  opts = opts or {}
  -- Attempt 2+: the body has just been re-executed and this is its new
  -- step list.  Install it; the callbacks below stay as they were.
  if RUN.installing then
    RUN.root = seqStep(steps)
    RUN.opts = opts
    RUN.budget = opts.maxFrames or 60000
    return
  end
  assert(not runnerStarted, "ot6.run() called twice")
  runnerStarted = true

  local isSegment = type(OT6_SCRIPT) == "string"
    and OT6_SCRIPT:match("^gen_") ~= nil
  local attempts = opts.retries or (isSegment and 3 or 1)
  if type(OT6_RETRIES) == "number" then attempts = OT6_RETRIES end
  if attempts < 1 then attempts = 1 end
  if not M.__body and attempts > 1 then
    M.log("[retry] retries UNAVAILABLE: this script was not composed with "
      .. "a segment body (lib/compose.py wraps one), so there is nothing to "
      .. "replay; running single-attempt")
    attempts = 1
  end
  RUN.attempts = attempts
  RUN.gap = opts.seedGap or (M.SEED_PERIOD // math.max(attempts, 1))
  RUN.opts = opts
  RUN.budget = opts.maxFrames or 60000
  RUN.root = seqStep(steps)
  RUN.shift = (type(OT6_SEED_SHIFT) == "number" and OT6_SEED_SHIFT or 0)
  RUN.tried[RUN.shift % M.SEED_PERIOD] = true
  -- Probe mode (#208, seed_sweep.py --probe): every sample runs the body
  -- from its boot snapshot to its first battle only, logs the first-battle
  -- key, and replays at the next shift (OT6_SEED_SHIFT, +stride, ... below
  -- one 60-frame period past it).  A measurement, never a verdict on the
  -- route: it PASSes once every shift has been sampled.
  if type(OT6_SHIFT_PROBE) == "number" and OT6_SHIFT_PROBE > 0 then
    RUN.probe = { stride = OT6_SHIFT_PROBE, base = RUN.shift, rows = {} }
    attempts = (M.SEED_PERIOD + OT6_SHIFT_PROBE - 1) // OT6_SHIFT_PROBE
    RUN.attempts = attempts
    if not M.__body then
      error("OT6_SHIFT_PROBE needs a composed segment body to replay", 0)
    end
  end
  if opts.watchdog ~= nil then W.enabled = opts.watchdog
  elseif type(OT6_WATCHDOG) == "number" then W.enabled = OT6_WATCHDOG ~= 0
  else W.enabled = isSegment end
  M.log(string.format("[retry] segment runner: %s, up to %d attempt(s), "
    .. "seed shift %d, watchdogs %s (no-effect %d frames, no-progress %d)",
    tostring(OT6_SCRIPT or "?"), attempts, RUN.shift,
    W.enabled and "ON" or "observing only", WATCH.noEffectFrames,
    WATCH.quietFrames))

  local finished = false

  -- Silent-auto-Continue canary.  Every game-over path routes through the
  -- event GameOver script ($CC/E568); when it runs, the title screen
  -- follows, and any driver that mashes A auto-Continues the last save,
  -- after which the session has TIME-TRAVELED (roster and switches
  -- revert) while every naive predicate reads healthy.  So the default is
  -- LOUD: GameOver ends the attempt, unless the route declares it
  -- survivable (opts.allowGameOver, or a ladder setting M.gameOverFired =
  -- 0 after handling its reload).
  --
  -- READ watch, not exec: GameOver in bank $CC is EVENT SCRIPT DATA -- the
  -- event interpreter READS those bytes and never executes them as CPU
  -- code, so an exec watch there would never fire.
  --
  -- A genuine party wipe inside a live `battle` command is handled by the
  -- BATTLE MODULE directly and never runs the GameOver script at all, so
  -- the READ watch alone is not sufficient.  TitleScreen is the actual
  -- title-screen module entry every path back to the title screen must
  -- reach, GameOver-scripted or not, so an EXEC watch there is the
  -- backstop.  Both watches feed the same M.gameOverFired counter so no
  -- caller needs to know which one fired.
  -- The two references are spelled as direct sym calls inside a thunk
  -- rather than passing M.sym to pcall with the name as a second
  -- argument: compose.py's _SYM_REF scanner only collects the direct-call
  -- literal form, so the comma spelling left OT6_SYMS without either
  -- name, M.sym raised at runtime, the pcall swallowed it, and the
  -- canary silently never armed in ANY composed run (measured 2026-08-27:
  -- a FlameEater wipe auto-Continued the battery save and the run
  -- time-traveled while gameOverFired read 0).
  -- Neither watch counts until the run has actually been IN the game
  -- once (a frame with control or a battle): a raw power-on boots through
  -- the real title screen, so an ungated exec watch condemns the chain's
  -- one from-power-on generator (gen_battle_state) within seconds of
  -- reset -- measured the day the canary was first armed.  For every
  -- state-booted run the latch closes on the first frame.  The counters
  -- are split so the failure names which watch fired; M.gameOverFired
  -- stays the public sum every existing caller reads and clears.
  -- Third watch, the battle-side wipe (#153): an annihilated party never
  -- reaches either of the above on its own.  LoseBattle sets $3ebc bit 0
  -- and the battle module then SITS on the annihilated screen waiting for
  -- a press -- measured with probe_wipe_canary.lua on the FC (394): every
  -- battle-HP word 0 from t=11945, $3ebc=$0D, no GameOver read and no
  -- TitleScreen exec for the next 30,000 frames with the pad released.
  -- Only a press moves it on, and the press a driver makes there is the
  -- A that Continues the last save.  So the wipe predicate itself (every
  -- SEATED battle slot at 0 HP, or LoseBattle's $3ebc bit 0, with the
  -- battle table live -- M.partyWipedInBattle, #166) held for WIPE_FRAMES
  -- counts as a game over: bounded, and before any driver can press
  -- through to the title.
  --
  -- These three watches are registered ONCE, through the raw handles, so
  -- that a replayed attempt inherits a live canary rather than a set of
  -- inert ones (see "callback registration" at the top of this file); the
  -- counters below are reset per attempt instead.
  M.gameOverFired = 0
  local goReadFired, titleExecFired, wipeFired = 0, 0, 0
  local WIPE_FRAMES = 300
  local wipeN = 0
  local canaryInGame = false
  do
    local ok, addr = pcall(function() return M.sym("GameOver") end)
    if ok then
      rawAddMemoryCallback(function()
        if not canaryInGame then return end
        -- Only a read made by the event interpreter ENTERING the script
        -- counts: its pc ($e5-$e7) sits on the script's first byte as it
        -- fetches it.  A neighbouring script's tail, a lookahead, or a
        -- table walk can touch this one byte too (the WoR opening at the
        -- Solitary Island bedside read it three times with the title
        -- screen never entered, 2026-09-01), and those are not a game
        -- over.  TitleScreen's exec watch below stays the backstop.
        local pc = M.readByte(0x00e5) | (M.readByte(0x00e6) << 8) | (M.readByte(0x00e7) << 16)
        if pc ~= addr and pc ~= addr + 1 then return end
        goReadFired = goReadFired + 1
        M.gameOverFired = M.gameOverFired + 1
        RUN.goUnhandled = { frame = M.frame, what = "the GameOver event script was entered" }
        M.freezePad("the GameOver event script was entered")
      end, emu.callbackType.read, addr, addr)
    end
  end
  do
    local ok, addr = pcall(function() return M.sym("TitleScreen") end)
    if ok then
      rawAddMemoryCallback(function()
        if canaryInGame then
          titleExecFired = titleExecFired + 1
          M.gameOverFired = M.gameOverFired + 1
          RUN.goUnhandled = { frame = M.frame, what = "TitleScreen was entered" }
          M.freezePad("TitleScreen was entered")
        end
      end, emu.callbackType.exec, addr, addr)
    end
  end
  -- The first battle's RNG state (#208; firstBattleKey above).  Registered
  -- once through the raw handle, like the canary, and judged in frame():
  -- the exec fires inside the CPU, where no replay can be scheduled.
  do
    local ok, addr = pcall(M.seedStoreAddr)
    if ok then
      rawAddMemoryCallback(function()
        if RUN.phase ~= "run" or RUN.firstBattle then return end
        -- Mesen fires exec callbacks before the instruction: A is the seed.
        local seed = emu.getState()["cpu.a"] & 0xff
        local grp = M.readWord(0x11e0)
        local fb = { attempt = RUN.attempt, shift = RUN.shift, frame = M.frame,
          boot = RUN.bootFrame and (M.frame - RUN.bootFrame) or nil,
          phase = M.seedPhase(), seed = seed, group = grp,
          key = firstBattleKey(seed, grp) }
        RUN.firstBattle, RUN.pendingFirst = fb, fb
        M.log(string.format("[seed] first battle: attempt %d/%d shift %d f%d "
          .. "boot+%s $021e=%d $be=$%02X group $%04X key %s", fb.attempt,
          RUN.attempts, fb.shift, fb.frame, tostring(fb.boot), fb.phase, seed,
          grp, fb.key))
      end, emu.callbackType.exec, addr, addr)
    else
      M.log("[seed] first-battle watch UNAVAILABLE (the seed store did not "
        .. "resolve: " .. tostring(addr) .. "); no attempt's first battle is "
        .. "recorded, so duplicate seeds cannot be flagged")
    end
  end

  -- ---- the failure path, shared by every way an attempt can end --------
  local function attemptLine(class, msg)
    local shot = nil
    if class == "wipe" or class == "nopath" or class == "timeout" then
      -- the watchdog classes already took their own screenshot
      local tag = string.format("attempt%d_%s_f%d", RUN.attempt, class,
        M.frame)
      M.screenshot(tag)
      local dir = (type(OT6_ART_DIR) == "string" and OT6_ART_DIR ~= "")
        and OT6_ART_DIR or "<the retained run workspace>/artifacts"
      shot = string.format("%s/shots/%s.png", dir, tag)
    end
    M.log(string.format("[retry] attempt %d/%d FAILED class=%s frame=%d "
      .. "totalframes=%d shift=%d phase=%d%s: %s",
      RUN.attempt, RUN.attempts, class, M.frame, M.totalFrames, RUN.shift,
      M.seedPhase(), shot and (" screenshot=" .. shot) or "", tostring(msg)))
    local context = nil
    if class == "wipe" then
      local b = RUN.lastBattle
      if b then
        context = string.format("the last battle up (f%d) was formation %s; "
          .. "seats at that reading %s (actor:hp/maxhp bp)", b.frame,
          b.formation, b.seats)
      else
        context = "no battle was sampled in this attempt (the loss was not in "
          .. "a fight this runner saw)"
      end
      M.log(string.format("[retry] attempt %d/%d wipe context: %s", RUN.attempt,
        RUN.attempts, context))
    end
    RUN.failures[#RUN.failures + 1] =
      { attempt = RUN.attempt, class = class, msg = tostring(msg),
        frame = M.frame, context = context }
  end

  local function stopWith(code, class, msg)
    finished = true
    traceFlush()
    coverageFlush()
    watchReport()
    M.finishRecoveryTrace("run_ended")
    local tally = {}
    for _, f in ipairs(RUN.failures) do
      tally[#tally + 1] = string.format("%d:%s", f.attempt, f.class)
    end
    if #tally > 0 then
      M.log(string.format("[retry] attempts=%d/%d%s; failed attempts: %s",
        RUN.attempt, RUN.attempts,
        RUN.attempt >= RUN.attempts and " exhausted" or " stopped",
        table.concat(tally, " ")))
    end
    M.log(string.format("FAIL: %s%s", tostring(msg),
      (class == "assert" or class == "other" or class == "budget")
        and string.format("\n  [retry] class=%s is NOT seed-dependent, so "
          .. "this failed on attempt %d of %d without a retry: fix it, do "
          .. "not re-roll it.", class, RUN.attempt, RUN.attempts)
        or ""))
    emu.stop(code)
  end

  -- Restore the boot snapshot and replay the body; the reloading branch of
  -- frame() re-executes it with RUN.nextShift (or the gap ladder's shift).
  local function scheduleReplay(why)
    M.log(string.format("[retry] attempt %d/%d: restoring the boot snapshot "
      .. "(%d bytes) and replaying the body %s",
      RUN.reroll and RUN.attempt or RUN.attempt + 1, RUN.attempts,
      #RUN.s0blob, why))
    M.thawPad()
    M.setPad(nil)
    RUN.phase = "reloading"
    RUN.ld = M.requestLoadState(RUN.s0blob)
    RUN.ldWait = 0
  end

  -- Probe mode: the sampled table, then a PASS (a measurement, not a route).
  local function probeFinish()
    finished = true
    watchReport()
    local seen, distinct = {}, 0
    M.log(string.format("[seedprobe] %s: first battle per shift (stride %d)",
      tostring(OT6_SCRIPT or "?"), RUN.probe.stride))
    for _, r in ipairs(RUN.probe.rows) do
      if r.key then
        local dup = seen[r.key]
        if not dup then seen[r.key] = r.shift; distinct = distinct + 1 end
        M.log(string.format("[seedprobe] shift %2d: f%d boot+%s $021e=%d "
          .. "$be=$%02X group $%04X key %s%s", r.shift, r.frame,
          tostring(r.boot), r.phase, r.seed, r.group, r.key,
          dup and string.format("  (duplicates shift %d)", dup) or ""))
      else
        M.log(string.format("[seedprobe] shift %2d: no battle -- %s: %s",
          r.shift, r.class, r.msg))
      end
    end
    M.log(string.format("[seedprobe] %d shift(s) sampled, %d distinct first "
      .. "battle(s)", #RUN.probe.rows, distinct))
    M.log(string.format("PASS (frame %d) attempts=%d/%d", M.frame,
      RUN.attempt, RUN.attempts))
    emu.stop(0)
  end

  -- Probe mode: this shift's sample is in; on to the next, or finish.
  local function probeNext()
    local nxt = RUN.shift + RUN.probe.stride
    if nxt >= RUN.probe.base + M.SEED_PERIOD or not (RUN.s0blob and #RUN.s0blob > 0) then
      if nxt < RUN.probe.base + M.SEED_PERIOD then
        M.log("[seedprobe] no boot snapshot was captured; stopping early")
      end
      probeFinish()
      return
    end
    RUN.nextShift = nxt
    scheduleReplay(string.format("for the next probe sample (shift %d)", nxt))
  end

  -- Schedule a replay, or stop.  `code` is the exit code a final failure
  -- takes (3 for a game over, 1 for a raised error, 2 for the budget).
  local function failed(class, msg, code)
    -- A stall that follows a counted game over the body never handled is
    -- the loss, not the stall (#205): under allowGameOver the count raises
    -- nothing here, and what a driver then does at the Annihilated screen
    -- (or the title) is no-effect, no-progress or a step's timeout.  The
    -- attempt files as the wipe it was, with its context line; a body that
    -- handled the count by restoring a snapshot (M.requestLoadState clears
    -- the note) keeps the stall's own class.
    local go = RUN.goUnhandled
    if go ~= nil and (class == "noprogress" or class == "noeffect"
                      or class == "timeout") then
      msg = string.format("a counted game over the body never handled -- %s at "
        .. "f%d (GameOver read x%d, TitleScreen exec x%d, battle wipe x%d; "
        .. "allowGameOver=%s) -- preceded this %s, so the attempt is filed as "
        .. "the loss: %s", go.what, go.frame, goReadFired, titleExecFired,
        wipeFired, tostring(RUN.opts.allowGameOver == true), class, tostring(msg))
      class = "wipe"
    end
    attemptLine(class, msg)
    if RUN.probe then
      RUN.probe.rows[#RUN.probe.rows + 1] =
        { shift = RUN.shift, class = class, msg = tostring(msg):sub(1, 160) }
      probeNext()
      return
    end
    RUN.firstBattles[#RUN.firstBattles + 1] = RUN.firstBattle
      or { attempt = RUN.attempt, shift = RUN.shift }
    local haveS0 = RUN.s0blob and #RUN.s0blob > 0
    if not RETRYABLE[class] or RUN.attempt >= RUN.attempts
       or not M.__body or not haveS0 then
      if RETRYABLE[class] and not haveS0 then
        M.log("[retry] no boot snapshot was captured for this run, so this "
          .. "seed-dependent failure cannot be replayed")
      end
      stopWith(code, class, msg)
      return
    end
    scheduleReplay("with a fresh seed")
  end

  local function frame()
    M.totalFrames = M.totalFrames + 1

    -- ---- a replay in flight: no steps, no canary, no watchdog ---------
    if RUN.phase == "reloading" then
      RUN.ldWait = RUN.ldWait + 1
      if RUN.ld and RUN.ld.done then
        if not RUN.ld.ok then
          stopWith(1, "other", "retry: the boot snapshot would not load: "
            .. tostring(RUN.ld.error))
          return
        end
        if RUN.reroll then
          RUN.reroll = false
        else
          RUN.attempt, RUN.rerolls = RUN.attempt + 1, 0
        end
        if RUN.nextShift then
          RUN.shift, RUN.nextShift = RUN.nextShift, nil
        else
          RUN.shift = (type(OT6_SEED_SHIFT) == "number" and OT6_SEED_SHIFT or 0)
            + RUN.gap * (RUN.attempt - 1)
          -- the gap ladder never re-runs a shift a re-roll already took
          for _ = 1, M.SEED_PERIOD do
            if not RUN.tried[RUN.shift % M.SEED_PERIOD] then break end
            RUN.shift = RUN.shift + 1
          end
        end
        RUN.tried[RUN.shift % M.SEED_PERIOD] = true
        resetLibState()
        M.rearmInputInjection()
        canaryInGame = false
        goReadFired, titleExecFired, wipeFired, wipeN = 0, 0, 0, 0
        RUN.installing = true
        local ok, err = pcall(M.__body)
        RUN.installing = false
        if not ok then
          stopWith(1, "other", "retry: replaying the segment body raised: "
            .. tostring(err))
          return
        end
        M.log(string.format("[retry] attempt %d/%d starting: body replayed "
          .. "from source; it will idle %d frames at its boot point to "
          .. "move the seed", RUN.attempt, RUN.attempts, RUN.shift))
        RUN.phase = "run"
      elseif RUN.ldWait > 600 then
        stopWith(1, "other", "retry: the savestate load trampoline never "
          .. "fired in 600 frames")
      end
      return
    end

    if not canaryInGame and (M.hasControl() or M.battleLoadStarted()) then
      canaryInGame = true
    end
    if M.battleLoadStarted() and M.frame % 30 == 0 then sampleBattle() end
    if canaryInGame and M.partyWipedInBattle and M.partyWipedInBattle() then
      wipeN = wipeN + 1
      if wipeN == WIPE_FRAMES then
        wipeFired = wipeFired + 1
        M.gameOverFired = M.gameOverFired + 1
        local seats = {}
        for e = 0, 3 do
          local a = M.readByte(0x3ed8 + e * 2)
          seats[#seats + 1] = a == 0xFF and "-" or string.format("a%d%s:%d/%d",
            a, (M.readByte(0x3aa0 + e * 2) & 1) == 1 and "" or "(hidden)",
            M.readWord(0x3bf4 + e * 2), M.readWord(0x3c1c + e * 2))
        end
        M.log(string.format("canary: BATTLE WIPE -- the battle table has " ..
          "read wiped for %d frames (seats [%s], $3ebc=%02X: every present " ..
          "seat at 0 HP or LoseBattle's bit 0 set); the engine is sitting " ..
          "on the annihilated screen waiting for a press.  Counted as a " ..
          "game over (f%d).", WIPE_FRAMES, table.concat(seats, " "),
          M.readByte(0x3ebc), M.frame))
        RUN.goUnhandled = { frame = M.frame, what = "the party was wiped in battle" }
        -- Under allowGameOver the pad stays live (#205): the body declared
        -- a lost fight survivable, and a scripted loss (battle 11's
        -- scenario reset, docs/design/sfigaro-gate.md) moves on only with
        -- the press a person makes at the Annihilated screen.  Frozen, that
        -- press was dropped and the attempt stalled to no-progress 1800
        -- frames later, filed as a stall instead of the loss it was.  The
        -- GameOver-read and TitleScreen watches above still freeze: those
        -- are the real game over, past which any A Continues the last save.
        if RUN.opts.allowGameOver then
          M.log(string.format("canary: allowGameOver -- the pad is not frozen on "
            .. "this count; the body's ladder owns the loss (a stall after it "
            .. "files as a wipe) (f%d)", M.frame))
        else
          M.freezePad("the party was wiped in battle")
        end
      end
    else
      wipeN = 0
    end
    if M.gameOverFired > 0 and not RUN.opts.allowGameOver then
      failed("wipe", string.format("GAME OVER fired (GameOver read x%d, " ..
        "TitleScreen exec x%d, battle wipe x%d) -- the run " ..
        "lost and any further input auto-Continues the last save, which " ..
        "reads as silent time travel.  A ladder that can survive this " ..
        "must reload BEFORE the game-over lands, or clear " ..
        "M.gameOverFired after handling it (see #127's ambush finding).",
        goReadFired, titleExecFired, wipeFired), 3)
      return
    end
    M.frame = M.frame + 1
    if OT6_LIVE and (M.frame == 20 or M.frame % LIVE_IVL == 0) then M.liveShot() end

    -- The boot snapshot for the replay: harvested here, a couple of
    -- frames after it was asked for (below, after the tick).
    if RUN.s0 and RUN.s0.done and not RUN.s0blob then
      if RUN.s0.ok then
        RUN.s0blob = RUN.s0.blob
        M.log(string.format("[retry] boot snapshot captured at f%d "
          .. "(%d bytes): the machine as the body's first step found it",
          M.frame, #RUN.s0blob))
      else
        M.log("[retry] boot snapshot FAILED to capture ("
          .. tostring(RUN.s0.error) .. "); this run cannot retry")
        RUN.s0blob = ""              -- asked and answered: do not ask again
      end
      RUN.s0 = nil
    end

    -- The first battle's key is in (the exec watch above).  A probe sample
    -- ends here.
    if RUN.pendingFirst then
      local fb = RUN.pendingFirst
      RUN.pendingFirst = nil
      if RUN.probe then
        RUN.probe.rows[#RUN.probe.rows + 1] = fb
        probeNext()
        return
      end
      -- A replay whose first battle is an earlier attempt's is that
      -- attempt again: the shift was absorbed (or landed a whole period
      -- away), and playing it on would spend an attempt re-losing a known
      -- loss.  Re-roll THIS attempt at a shift no attempt has run yet.
      local same = nil
      for _, prev in ipairs(RUN.firstBattles) do
        if prev.key == fb.key then same = prev break end
      end
      if same and RUN.s0blob and #RUN.s0blob > 0 then
        RUN.rerolls = RUN.rerolls + 1
        if RUN.rerolls > MAX_REROLLS then
          failed("other", string.format("seed shift cannot move this segment: "
            .. "%d re-rolled shift(s) of attempt %d all fought attempt %d's "
            .. "first battle (key %s) -- a harness finding (#208), not a route "
            .. "one", RUN.rerolls - 1, RUN.attempt, same.attempt, fb.key), 1)
          return
        end
        local nxt = RUN.shift + REROLL_STEP
        for _ = 1, M.SEED_PERIOD do
          if not RUN.tried[nxt % M.SEED_PERIOD] then break end
          nxt = nxt + REROLL_STEP
        end
        M.log(string.format("[retry] reroll: attempt %d/%d at shift %d fought "
          .. "attempt %d's first battle (key %s, f%d there, f%d here) -- the "
          .. "same sample; re-running attempt %d at shift %d instead",
          RUN.attempt, RUN.attempts, RUN.shift, same.attempt, fb.key,
          same.frame or -1, fb.frame, RUN.attempt, nxt))
        RUN.reroll, RUN.nextShift = true, nxt
        scheduleReplay(string.format("re-rolled to shift %d", nxt))
        return
      end
    end

    if M.frame > RUN.budget then
      failed("budget", "frame budget exceeded (" .. RUN.budget
        .. " frames in attempt " .. RUN.attempt .. ")", 2)
      return
    end

    -- A body with no fixture load and no entry contract (the two
    -- from-power-on generators, and the harness's own selftests) never
    -- calls M.bootMark, so the seed variation would have nowhere to go.
    -- Mark the run's own opening instead: idling there is the same
    -- legitimate thing -- a player who has not started pressing yet.
    if not RUN.bootMarked and M.frame == BOOT_FALLBACK then
      M.bootMark(string.format("no fixture load or entry contract in the "
        .. "first %d frames: the run's own opening", BOOT_FALLBACK))
    end

    seedTraceTick()

    -- The seed variation: idle frames at the boot point, pad neutral, the
    -- pad restored afterwards so a press the boot step was holding is not
    -- silently dropped.
    if RUN.idle > 0 and not RUN.idleArm then
      local ph = M.seedPhase()
      RUN.idleMoved = RUN.idleMoved + ((ph - RUN.idlePrev) % M.SEED_PERIOD)
      RUN.idlePrev = ph
      RUN.idleFrames = RUN.idleFrames + 1
      M.setPad(nil)
      local stalled = RUN.idleFrames >= RUN.idle + IDLE_SLACK
      if RUN.idleMoved >= RUN.idle or stalled then
        RUN.idle = 0
        M.setPad(RUN.idlePad)
        RUN.idlePad = nil
        M.log(string.format("[retry] seed shift done at f%d ($021e=%d, a "
          .. "battle starting now would seed $be=$%02X): %d idle frame(s), "
          .. "the game clock moved %d of %d%s", M.frame, ph, M.seedOf(ph),
          RUN.idleFrames, RUN.idleMoved, RUN.shift,
          stalled and "  -- STALLED: the clock is not running here, so this "
            .. "shift may not move the run" or ""))
      end
      return
    end

    -- The absorb guard rides here rather than inside the battle drivers
    -- because a route need not use one of those drivers at all, and every
    -- test in the tree goes through this one callback.  The tile trace and
    -- the watchdog sampler ride here for the same reason.
    local ok, r = pcall(function()
      traceTick()
      local bad = M.absorbGuardTick()
      if bad then error(bad, 0) end
      bad = watchTick()
      if bad then error(bad, 0) end
      return RUN.root:tick()
    end)
    -- The boot point was marked inside that tick: take the pad the body
    -- went on to set in the same tick, before the game polls it (bootMark).
    if RUN.idleArm then
      RUN.idleArm = false
      RUN.idlePad = {}
      for _, b in ipairs(ALL_BTN) do RUN.idlePad[b] = curPad[b] end
      M.setPad(nil)
    end
    -- The boot snapshot for the replay, asked for on the first frame of
    -- attempt 1 on which no other savestate trampoline is pending (a
    -- fixture-booted body loads its fixture on frame 1, so this lands a
    -- few frames later, on the loaded fixture; a checkpoint-booted body
    -- gets frame 1, the power-on with its battery).  Either is the state
    -- the replayed body's first step will find, which is all the replay
    -- needs.  No step is delayed for it: the trampoline fires inside the
    -- frame's own emulation, so a first-try run lands frame for frame
    -- where it always did.
    if ok and RUN.attempt == 1 and RUN.attempts > 1 and M.__body
       and not RUN.s0 and not RUN.s0blob and M.pendingStateReqs == 0 then
      RUN.s0 = M.requestSaveState()
    end
    if not ok then
      failed(classify(r), tostring(r), 1)
    elseif r == "done" then
      finished = true
      traceFlush()
      coverageFlush()
      watchReport()
      M.finishRecoveryTrace("run_ended")
      for _, f in ipairs(RUN.failures) do
        M.log(string.format("[retry] this PASS followed a failed attempt: "
          .. "%d/%d class=%s: %s", f.attempt, RUN.attempts, f.class, f.msg))
      end
      M.log(string.format("PASS (frame %d) attempts=%d/%d", M.frame,
        RUN.attempt, RUN.attempts))
      emu.stop(0)
    end
  end

  -- The runner itself must never die without a verdict.  A Lua error in
  -- the reload path, the canary, the sampler or the verdict code is
  -- invisible headless (the script log is not read; docs/TESTING.md's
  -- "no verdict" signature), so the whole frame body runs under pcall and
  -- an error there is a FAIL line naming the runner, exit 1.
  rawAddEventCallback(function()
    if finished then return end
    local ok, err = pcall(frame)
    if not ok and not finished then
      finished = true
      pcall(traceFlush)
      pcall(coverageFlush)
      pcall(watchReport)
      pcall(M.finishRecoveryTrace, "run_ended")
      M.log(string.format("FAIL: segment runner internal error (attempt "
        .. "%d/%d, phase %s, f%d): %s\n  [retry] this is a harness bug, not "
        .. "a route or seed finding; nothing was retried.",
        RUN.attempt, RUN.attempts, tostring(RUN.phase), M.frame,
        tostring(err)))
      emu.stop(1)
    end
  end, emu.eventType.startFrame)
end

end   -- the segment runner's scope
return M
