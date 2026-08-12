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
-- $7E3BF4: 4 x 16-bit party battle HP ($FFFF outside battle).
--
-- $7E3F46 is NOT six 16-bit monster IDs, which is what this said until
-- 2026-08-12 and what the two readers below still assume.  LoadBattleProp
-- copies the 15-byte formation record verbatim to $3F44
-- (battle_main.asm:8243-8250, `lda f:BattleMonsters,x / sta $3f44,y` for
-- eight words), and that record is: +$00 mold/bg1 bits, +$01 monsters
-- present, +$02..$07 six 8-BIT monster ID low bytes, +$08..$0D six packed
-- xxxxyyyy positions, +$0E the six ID high bits.  So the IDs land at
-- $3F46..$3F4B one byte each, the positions at $3F4C..$3F51, and the MSB
-- mask at $3F52 (ff6/notes/battle-ram.txt:1117-1152; confirmed against
-- formation 43, whose Merchant reads $13A exactly as gen_sfigaro's header
-- says, and formation 504, whose all-$1FF empty record ot6_hud.asm:1796
-- documents).
--
-- Reading it as words therefore mixes ID bytes together and then reads two
-- position bytes as a third and fourth "monster".  Measured on battle 11,
-- formation 64, one monster ($09F): monstersPresent() answers 4, and the
-- gen_sfigaro fight log prints "monhp=495/sh3,0/sh0 monsters=4" for a
-- single soldier.  Nothing has gone wrong from that yet -- battleActive()
-- only asks whether the count is above zero, and the Cranes' opts.focus
-- liveness pre-check is backed by a real $3BFC hp read on the same slot --
-- so the decode is left alone here rather than changed blind: both call
-- sites were measured against the current numbers and re-measuring them is
-- its own job.  Do not add a third reader on top of it.
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

-- Six words off $3F46.  See the note above: these are not monster IDs, and
-- the count below is not a monster count.  Both are kept as they were
-- measured; the real per-slot ID is `readByte(0x3F46 + slot)` plus bit
-- `slot` of `readByte(0x3F52)`, and $3F45 is the present mask.
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

-- --------------------------------------------- absorbed-weapon guard --
-- Fail the run when a character enters a fight holding a weapon whose
-- element something in the formation ABSORBS, because then every swing
-- heals the enemy.
--
-- Why this exists.  Measured 2026-08-10 on the airship Cranes:
-- H.equipOptimum drives the game's own Optimum command, which picks by
-- attack power and knows nothing about elements, and it armed LOCKE and
-- EDGAR with ThunderBlades (item $0F, element bolt).  Left Crane $010D
-- absorbs bolt, so every Fight healed the boss (+160/+198 a pair swing,
-- +943 boosted) and advanced its Giga Volt counter.  The fight was
-- reported as honestly unwinnable and nearly became a request for a
-- tuning change.  The record is at M.equipWeapon below.
--
-- Why ABSORB only, and why a check rather than a swap.  The obvious
-- generalisation -- prefer an element-clean weapon -- was written and
-- measured WORSE.  On battle 70 the same weapon on the same two
-- characters is merely NULLED (monster_prop.dat +$18 reads $FC for both
-- Ifrit $0109 and Shiva $0108), and the swing was never where the damage
-- came from: that fight is won by chipping shields, and a chip goes by
-- weapon CLASS rather than element.  ThunderBlade is a sword, so
-- ot6_class.asm:58-64 makes it OT6_SLASH, and slashing is Shiva's break
-- axis.  The element-aware equip swapped to daggers (OT6_PIERCE), sold
-- the chip that wins the fight, and lost all three attempts.  So null is
-- a human judgement about class against the boss's break axis; absorb is
-- the one case with no upside on either side of the trade.  A check that
-- fails is the right shape for it, because it tells someone to think
-- instead of choosing for them.
--
-- Where the numbers come from, each confirmed against behaviour that was
-- already recorded rather than taken on trust:
--   * monster_prop.dat, 32-byte records, +23 absorb (+24 null, +25 weak;
--     HANDOFF "canonical facts", tools/check_boss_rows.py:88-92).  Ifrit
--     $0109 reads absorb $01 fire and Shiva $0108 absorb $02 ice, which
--     is bosses-wob.md's "fire heals Ifrit"; Whelk $0100 reads absorb $04
--     bolt, which is the game's own tutorial; Crane $010D reads absorb
--     $04 bolt, which is the Cranes measurement above.
--   * item_prop_en.dat, 30-byte records, +$00 type (&$07 == 1 is a
--     weapon) and +$0F element (research/data-formats.md "Items").
--     ThunderBlade $0F reads element $04 bolt, power 108, matching the
--     Cranes record.
M.ELEM_NAMES = { "fire", "ice", "bolt", "poison", "wind", "holy", "earth",
                 "water" }

function M.elemStr(mask)
  local out = {}
  for i, n in ipairs(M.ELEM_NAMES) do
    if (mask >> (i - 1)) & 1 == 1 then out[#out + 1] = n end
  end
  return #out > 0 and table.concat(out, "|") or "-"
end

local ITEM_REC, ITEM_TYPE, ITEM_ELEM, ITEM_POWER = 30, 0x00, 0x0F, 0x14
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

-- Item +$14, the power byte (data-formats.md "Items").  For a consumable
-- that is how much it heals: $E8 Tonic reads 50 and $E9 Potion reads 250 on
-- this ROM.  It is the engine's input rather than its output, so a caller
-- that can watch a use land should prefer what it measures; newFightDriver
-- uses this as the prior and replaces it with the observed number.
function M.itemPower(item)
  if item == nil or item > 0xFF then return 0 end
  return M.readRomByte((M.sym("ItemProp") & 0x3FFFFF)
    + item * ITEM_REC + ITEM_POWER)
end

-- How much of a heal has to land for it to be worth a turn.  1.0 would mean
-- "waste nothing", and that is too strict: it makes a character sitting 49
-- points down with a 50-point Tonic wait for one more point of damage before
-- drinking, and the turn he waits is a turn the enemy spends putting him
-- further down than the Tonic can reach.  This is the "approximately" in the
-- owner's rule, and it is a measured number rather than a taste.
--
-- It does two jobs and they pull opposite ways.  It is the bar for healing at
-- all, where a LOWER value heals more often; and it is the bar bagHeal uses
-- to choose between a Tonic and a Potion, where a LOWER value reaches for the
-- Potion sooner and so heals in FEWER turns.  The second effect is the larger
-- one on this route, because one 250-point Potion covers a hole that would
-- otherwise take four Tonic turns.
--
-- Measured 2026-08-12 over the fights the route is constrained by, from the
-- same savestates and checkpoints, everything else identical:
--
--          gen_zozo3_clock  gen_esper_tubes  gen_n128     gen_ifrit_magicite
--   0.75   nav timeout      PASS f11940      PASS f29842  killed at the cap
--   0.50   PASS f9478       PASS f8404       PASS f29842  PASS f26898
--
-- So 0.50.  The two fights it decides are decided on turn count rather than
-- on supplies: at 0.75 a 150-point hole is filled with three Tonics and at
-- 0.50 with one Potion, and a quarter of a Potion spilled buys back two
-- turns.  Battle 70 is slower than the old rule at both settings and this
-- number is not what would fix it; the cause is recorded in
-- docs/HANDOFF.md under the heal policy.
M.HEAL_VALUE = 0.50

-- Is a heal worth the turn it costs?  All of newFightDriver's heal policy,
-- kept out here as arithmetic on plain numbers so battle_healpolicy can put
-- the measured cases through it without an emulated fight.
--
--   hp, maxhp   the candidate's HP
--   restore     what the heal in hand actually gives back
--   roundCost   what one round takes off this candidate, measured in the
--               fight; 0 before the enemy has landed a round
--   allies      living party members other than the actor deciding
--   unknown     this heal's size has not been established, so there is no
--               hole to weigh it against; heal to maximum instead
--   value       override for M.HEAL_VALUE
--
-- Returns the reason to heal, or nil for "act instead".
--
-- The rule is the owner's, 2026-08-12: "the best healing policy is to heal
-- when you expect to get approximately full value out of the heal.  if a
-- tonic heals 50 hp, heal when you have 50 hp or more to heal, etc.  hard to
-- know with magic... in that case just heal everyone to max."
--
-- So the question is how much of this heal would be thrown away, not what
-- fraction of their health the target has left.  Drinking a 50-point Tonic
-- into a 12-point hole throws away three quarters of it, and doing that
-- repeatedly is how a party runs out of supplies before the fight that needs
-- them.  M.HEAL_VALUE is how much of the heal has to land.
--
-- `unknown` is the magic clause, and it fires exactly while the premise
-- behind it holds.  A cure's size really is not knowable in advance: the
-- power byte is an input to a formula that scales with the caster's magic
-- power and level, so weighing a first cast against a hole would be weighing
-- it against a guess.  While that is the situation, heal to maximum, which is
-- affordable for the same reason the route prefers casting to drinking at all
-- -- OT6 refunds MP in full at every level up (ot6_progression.asm:3-6), so
-- MP spent in a fight comes back and a Tonic does not.
--
-- But newFightDriver watches what its first cast puts back, so from the
-- second cast of a battle the size IS known, and then the value rule governs
-- the cure too.  Measured 2026-08-12 on the Zozo street: taken literally past
-- the point of knowing, "heal everyone to maximum" spent twelve of the
-- caster's turns and 65 MP topping targets up from 225/280 and 228/289 with a
-- cure measured at 148, the fight ran past the step's 30000-frame budget with
-- the party at full HP the whole time, and the run reported a navigation
-- timeout.  What is left of the owner's clause after that is the whole of it:
-- top everyone up to maximum rather than to a fraction, and stop when what is
-- left of the hole is smaller than the heal.
--
-- Two clauses sit on top of the value rule.
--
-- The first is the heal-lock, and it is the thing the fraction rule's
-- replacement had to keep.  Alone, the healer is also the only attacker, and
-- the arithmetic is settled: with HP h, a round costing d and a heal giving
-- g < d, a character who spends k of his turns drinking lands
-- h/d + k*(g/d - 1) attacks before he dies, which falls as k rises.  Every
-- drink costs him more attacking time than it buys, so he does not drink; he
-- swings.  That is solo LOCKE against battle 11's soldier, where a Tonic
-- restoring 50 against 55 to 112 a round bought five drinks and one attack
-- (issue #74).  A cast spends a turn exactly as a drink does, so a measured
-- cure is refused there on the same terms.  An UNMEASURED one is not, because
-- the clause needs a size and there is not one yet; that is the exploratory
-- cast that produces the number, and it is taken at most once per spell per
-- battle in the only shape that matters, since a round big enough to trip the
-- heal-lock leaves a hole bigger than the cure and so a cast that does not
-- fill anyone to maximum, which is the cast healWatch can measure.
--
-- The second is death.  A target inside one round of dying is worth a heal
-- the value rule would refuse, because what the turn buys back is that
-- member's whole remaining turn stream and a Fenix Down besides.  It is
-- required to actually change the outcome: the heal has to lift them clear
-- of the worst round seen, capped at their maximum, so a character the worst
-- round could kill from full HP is not topped up on a promise no heal can
-- keep.  That cap is what makes the clause safe to keep -- the uncapped
-- version was tried as the ONLY way a party could heal and left EDGAR at
-- 63/398 for all of battle 72 with seven Potions in the bag, which under the
-- value rule cannot happen, because a 335-point hole is full value for a
-- Potion and gets one long before anyone is in danger.
function M.healDecision(o)
  local hp, maxhp = o.hp or 0, o.maxhp or 0
  local gain, cost = o.restore or 0, o.roundCost or 0
  if hp <= 0 or maxhp <= 0 then return nil end
  local missing = maxhp - hp
  if missing <= 0 then return nil end
  -- the heal-lock: alone against damage the heal cannot out-run, swing
  if (o.allies or 0) == 0 and gain > 0 and gain < cost then return nil end
  if o.unknown then return "to full" end
  if gain <= 0 then return nil end
  if missing >= gain * (o.value or M.HEAL_VALUE) then return "full value" end
  if hp <= cost and math.min(maxhp, hp + gain) > cost then return "in danger" end
  return nil
end

function M.monsterAbsorb(species)
  return M.readRomByte((M.sym("MonsterProp") & 0x3FFFFF)
    + species * MON_REC + MON_ABSORB)
end

-- Both hands of every party member, as { char = c, hand = "R"|"L",
-- item = id }.  The left hand is usually a shield and weaponElement()
-- returns 0 for one, but a Genji Glove really does put a second weapon
-- there, so both slots are read.  $1600 + 37*c + $1F/$20, the same record
-- audit_equipment.py and M.equipOptimum read.
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

-- The formation's species, from OT6's own per-slot stash rather than from
-- vanilla's $3F46.  Two reasons: OT6_SPECIES ($57c0, six words) is
-- written per entity by Ot6SeedShields at monster-load time
-- (ff6/src/battle/ot6_break.asm:70-78), so it carries a monster that is
-- loaded but not on stage -- gen_ifrit_magicite.lua:340 asserts SHIVA
-- $0108 is there from the first frame of battle 70 -- and $3F46 is six
-- BYTES in vanilla's map (ff6/notes/battle-ram.txt:1123-1128), which is
-- not wide enough for a 0..383 species and is not what the word reads in
-- M.monsterIds() give.
--
-- Which slots are real comes from the formation's own occupied-slot mask.
-- battle-ram.txt:1119-1121 draws the pair as "+$3F44 mmmmbbbb bbpppppp",
-- mold / bg1-monsters / monsters-present, and the two bytes are in the
-- order printed: the low six bits of the SECOND byte, $3F45, are the slot
-- mask.  Measured on the whelk fight, whose formation is $0100 in slot 0
-- and $0134 in slot 1: $3F44 reads $80 (mold 8) and $3F45 reads $03.
-- Reading the pair as one little-endian word and masking its low six bits
-- gives 0, which is what the first draft of this did, and it made the
-- guard silently check nothing.
--
-- OT6_SPECIES is not cleared between battles, so without the mask a short
-- formation would be checked against the tail of the previous one.
-- Formation 504, the Imperial Camp Kefka fight, is legitimately empty
-- (bosses-wob.md:267-268), so a zero mask is "nothing to check" rather
-- than an error.
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
-- cleared, so an event battle always reads 0 and a marker can never leak
-- past one battle (ff6/src/battle/ot6_boost.asm:14-29).  Both measured
-- disasters were scripted fights, where the party stands and swings; a
-- random encounter that happens to absorb is usually fled or over in a
-- round, and failing a multi-hour chain for one would bury the finding
-- this guard exists to surface.  A clash in a random encounter is logged
-- instead, which is how we would learn that the line is in the wrong
-- place.
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
  -- are not both filled yet, which is also what junk looks like on a
  -- playline that has not fought a battle (probe_57ba_strip measured $ff
  -- riding the srm boot line, and M.battleLoadStarted reads a shape
  -- rather than a flag).  Keep waiting rather than failing a run on a
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
    .. "H.equipOptimum's power-greedy pick in place."
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
-- each attempt holds until $021e has advanced to its own target phase, spaced
-- as widely as 60 phases allow, and the seed each attempt actually drew is
-- read off the store instruction and required to be distinct.  A ladder that
-- plays one fight twice is the failure mode with no symptom, so it fails the
-- run.
--
-- WHY THE HOLD COUNTS MOVEMENT INSTEAD OF MATCHING THE TARGET VALUE.  It used
-- to wait for `$021e == target`, sampled once per emulated frame, and that
-- cannot see every phase.  $021e is ticked at the very END of the owning
-- module's vblank handler -- ff6/src/field/reset.asm:286 sits after every
-- palette, sprite, tilemap and dialog transfer FieldNMI performs -- and that
-- handler is long enough to finish either just inside the frame or just past
-- it.  Measured 2026-08-12 on sfigaro_town's battle 11, in the 181 frames the
-- old wait spent failing (map 75, party standing still after a lost attempt):
--
--   * IncGameTime ran 180 times in 180 frames, one per frame on average,
--     exactly as designed -- the counter was never stopped;
--   * the tick executed at scanline 247, then 257, then 1 of the following
--     frame, straddling scanline 0, which is where the harness samples
--     (M.run's startFrame callback);
--   * so frames held 2, 1, 0, 1 ticks on a stable four-frame beat, and the
--     once-per-frame sample stepped +2, +1, 0, +1;
--   * every phase congruent to 3 mod 4 therefore existed only between two
--     sample points.  Phase 7, the target, was written at scanline 1 of a
--     frame and overwritten at scanline 257 of the SAME frame, every cycle.
--     No wait of any length could have matched it.
--
-- The field NMI's own $45/$46 counters step in the same 0/+2 pattern, which
-- is what rules out a second caller ticking the clock instead.
--
-- So the hold accumulates the counter's own movement: it sums each frame's
-- delta and releases once the counter has moved as far as the target was
-- away.  That lands on the target when the sample can see it and one or two
-- phases past it when it cannot, which 20-phase spacing does not care about,
-- and it is report() -- the seed each attempt really drew -- that guarantees
-- the attempts were different fights.  A counter that is genuinely stopped
-- moves nothing, and that still fails the run rather than falling back to
-- "wait a bit and hope": a ladder that cannot spread must not be able to
-- quietly play one fight twice.
--
-- Why the spacing is as wide as it is, rather than merely nonzero.  RNGTbl is
-- 256 bytes (ff6/src/field/rng_tbl.dat, incbin'd at field/rng_tbl.asm:11) and
-- $be is an index into it, so two attempts are not independent streams: they
-- are the same table read from two starting points, 4 entries apart per phase.
-- Attempts one phase apart share every draw with a shift of four, and a fight
-- consuming a few hundred randoms walks the whole table several times over
-- either way.  Distinct seeds are what makes the attempts different fights;
-- distant seeds are what makes them differ early, before the party's state has
-- diverged enough to matter.  Three attempts 20 phases apart start 80 table
-- entries apart, which is the most the cycle allows.

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
-- $021e has advanced to base + 20*(n-1), which is the widest even spacing
-- three attempts fit into the 60-phase cycle.  The seed the fight actually
-- drew is captured at the store and checked by report(): distinct across
-- attempts, and present for every attempt that ran, so a watcher that never
-- fired fails rather than passing silently.
--
-- opts.attempts (default 3) only sets the spacing.  It is not a licence to
-- widen the ladder: three is the doctrine (#74), and a ladder that loses three
-- different fights is reporting a finding.
--
-- opts.phaseSource replaces the live read of $021e, and exists so
-- battle_seedladder can drive the hold with samplers a real route cannot be
-- made to produce on demand: one that aliases the way the field NMI's straddle
-- makes the real one alias (a quarter of the phases never visible), and one
-- that never moves at all.  A generator's ladder reads the counter.
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

  -- The spread, derived from the counter the seed is made of.  Replaces
  -- H.waitFrames((n - 1) * 37).  sopts.forcePhase pins the target outright and
  -- exists for battle_seedladder's controls -- driving two attempts onto one
  -- seed to watch report() fail, and naming a phase the sampler cannot see to
  -- watch the hold release anyway.  A generator does not pass it.
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
      -- Not M.waitUntil: `target` is only known once the step above has run,
      -- and waitUntil bakes its description at construction time.  And not an
      -- equality test on the sampled phase, which is unreachable for a quarter
      -- of the phases whenever the owning module's vblank handler straddles
      -- the emulator's frame boundary -- see the measurement in the header
      -- above.  This sums the counter's own movement and releases once it has
      -- moved as far as the target was away, so it lands on the target or one
      -- or two phases past it.  The budget is three cycles; one is enough at
      -- the one tick per frame every vblank handler gives, so running out
      -- means the counter is stopped or crawling, which is a finding about
      -- where the spread was placed rather than about the length of the wait.
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
-- Healing prefers a cure spell to the bag, the way M.fieldCare does on the
-- field side; opts.cure=false is the item-only drive this had before.  Any
-- character whose live battle Magic list holds a cure can be the healer,
-- which in OT6 usually means whoever is wearing the stone that grants one.
--
-- Call frame() on every frame battleLoadStarted() is true and idle() on the
-- falling edge.  frame() sets the controller pad itself.
function M.newFightDriver(tag, opts)
  opts = opts or {}
  -- Refuse the retired knob rather than ignore it.  Every call site that
  -- named a fraction was tuning the rule M.healDecision replaced, and a
  -- number silently dropped on the floor is how a caller goes on believing it
  -- steers something.
  if opts.healPercent ~= nil then
    error("opts.healPercent is gone.  M.healDecision heals by how much of "
      .. "the heal would land, not by a fraction of maximum HP; drop the "
      .. "option rather than re-tuning it")
  end
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
  -- scroll+row is the absolute grid row, col the column; grid cell N sits at
  -- row N//2, column N%2, the mapping battle_brokendeath measured and
  -- gen_vargas's Cure drive uses)
  local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B
  -- $302C,entity is the engine's own pointer at that character's compacted
  -- battle Magic list ($208E/$21CA/$2306/$2442; GetMPCost walks it,
  -- battle_main.asm:13201-13210, and so does CheckMagicEnabled, :14692).
  -- Record 0 is the esper row and record n+1 is grid cell n.
  local MLISTPTR = 0x302C
  local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
  local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
  local AUTOCROSSBOW, PUMMEL = 0xAA, 0x5D
  -- The cures, cheapest first.  Cheapest rather than biggest for the same
  -- reason M.fieldCare picks that way: the loop simply casts again if the
  -- target is still short, so overshoot is only wasted MP.  Under OT6 the
  -- upper tiers are folds of the base spell rather than separate grants
  -- (battle_esperstats: KIRIN grants Cure and NOT Cure 2), so in practice
  -- only the first of these is ever found in the list.
  local CURES = { 0x2D, 0x2E, 0x2F }
  local F = {}
  local menuStreak, tick, battleTick = 0, 0, 0
  local plan, planActor, held = nil, nil, {}
  local tgtSpin = 0                    -- frames spent undecided in ST_TGT
  -- The two numbers the heal policy weighs against each other, both measured
  -- in the fight rather than assumed.  See the policy note in makePlan.
  local roundCost = {}                 -- entity -> worst HP lost per own turn
  local turnSnap = {}                  -- actor -> party HP at its last turn
  local itemRestore = {}               -- item  -> HP a landed use put back
  local castRestore = {}               -- spell -> HP a landed cast put back
  local healWatch = nil                -- a confirmed heal, awaiting its effect
  local healSaid = nil                 -- last refusal logged, to log it once
  -- A heal confirmed by an earlier actor whose HP has not landed yet:
  -- { target, gain, hp, until_ }.  The next actor to decide adds its `gain`
  -- to that target's HP before measuring the hole, because the hole a heal
  -- has to fit is the one that will be left once the heals already committed
  -- have landed.  Without it the party double-drinks: measured on battle 70,
  -- actors 2 and 0 both planned a Tonic on entity 0 at exactly 270/354, so
  -- the second one poured 50 into a hole of 34.
  local healSent = nil

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

  -- What one use of an item gives back.  The prior is M.itemPower, the +$14
  -- power byte: 50 for a Tonic and 250 for a Potion, and a Tonic was measured
  -- restoring about 50 in battle 11.  It is a prior and not the answer,
  -- because power is an input to the engine's heal routine rather than its
  -- output.  The first use that lands replaces it with the HP that actually
  -- came back (F.frame's healWatch), so a retuned item, or one whose power
  -- does not pass through straight, corrects itself within one heal instead
  -- of steering the policy wrong for a whole fight.
  local function itemRestoreOf(item)
    return itemRestore[item] or M.itemPower(item)
  end

  -- Which of the bag's heals fits a hole this size.  The owner's rule applied
  -- to the choice as well as to the decision: take the biggest heal that
  -- still lands nearly in full, and when nothing fits fall back to the
  -- smallest one the bag holds, which wastes the least.  The old rule reached
  -- for a Potion at a hole of 80 and threw away 170 of its 250 every time.
  -- Sorted by what each is measured to restore rather than by a fixed order,
  -- so a retuned item sorts itself.
  local function bagHeal(missing)
    local avail = {}
    for _, id in ipairs({ POTION, TONIC }) do
      if battInvIdx(id) then avail[#avail + 1] = id end
    end
    table.sort(avail, function(a, b)
      return itemRestoreOf(a) > itemRestoreOf(b)
    end)
    for _, id in ipairs(avail) do
      if missing >= itemRestoreOf(id) * M.HEAL_VALUE then return id end
    end
    return avail[#avail]
  end

  -- Where a spell sits in this actor's live battle Magic list, and what the
  -- engine has priced it at.  Returns the grid cell (the number the cursor
  -- walk below steers to) and the MP cost, or nil if the actor cannot cast
  -- it right now.
  --
  -- Read live, per actor, rather than taken from the caller, because in OT6
  -- the list is runtime state twice over: it is compacted to the union of
  -- what the party knows (InitSpellList), and Ot6UnionEspers /
  -- Ot6EsperSpellKnown (ot6_progression.asm:144, :205) add each equipped
  -- esper's spells to its holder alone.  So the same spell sits at different
  -- cells for different loadouts, and a caller-supplied row number would
  -- silently steer to whatever else the compaction put there.  The row
  -- layout is +0 id, +1 flags (bit 7 = greyed), +2 targeting, +3 MP cost
  -- (battle_preview.lua:59-66).  The price is read here rather than out of
  -- magic_prop_en.dat because the engine's copy is the one it charges.
  --
  -- `strict` picks how hard to refuse.  Deciding what to do (strict) asks
  -- the game's own greyed bit as well, which is the authority on castability
  -- (CheckMagicEnabled, battle_main.asm:14822-14840).  Steering a list that
  -- is already open (not strict) asks only the live MP, because the greyed
  -- bit is refreshed by UpdateEnabledMagic on the action boundary (:1369)
  -- and a bit that has gone stale under an open window would drop a plan
  -- that was fine, spending the healer's turn on a B press.
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
    turnSnap[actor] = hpNow
    -- opts.healer = <battle chid>: only that character runs the item
    -- healing line; everyone else attacks.  Measured need (2026-08-09, the
    -- escape cave): with every actor healing, a party whose only damage is
    -- LOCKE's Fight heal-locks, because one enemy round costs more HP than
    -- the Tonic his turn restores, so he never attacks, the monster never
    -- dies, and the bag drains to a wipe.  A player splits the jobs, with
    -- the safe back-row member healing and the fighter fighting.  This is
    -- role assignment, not the fix for that heal-lock -- the policy below is,
    -- because a solo party has nobody to hand the job to.
    local mayHeal = opts.healer == nil
        or M.readByte(BCHID + actor * 2) == opts.healer
    local row = (opts.items and mayHeal) and cmdRow(actor, CMD_ITEM) or nil
    -- opts.cure = false turns the cast line off and leaves healing to the
    -- bag, the way this driver worked before.  Anything else is the list of
    -- cure spells to try, cheapest first, defaulting to CURES.
    --
    -- Why casting comes first.  M.fieldCare learned the same preference on
    -- the field side and the reason carries over: OT6 refunds MP in full at
    -- every level up (ot6_progression.asm:3-6, called from
    -- battle_main.asm:16251) and never refunds a Tonic.  In battle there is
    -- a second reason, measured on this ride: a segment can run six fights
    -- with no field access between them, so the bag is a fixed supply while
    -- MP is only bounded per fight.  The five Mag Roader fights spent all
    -- eight of the party's Tonics and left the boss to be fought with
    -- nothing (#92).
    --
    -- The option is named `cure` rather than `magic` only because this
    -- driver already spends `opts.magic` on the attack line below.  It is
    -- fieldCare's opts.magic under another name.
    local cureRow = mayHeal and opts.cure ~= false
        and cmdRow(actor, CMD_MAGIC) or nil
    if row ~= nil or cureRow ~= nil then
      -- Revival stays item-only.  Life ($33) is not on any route this
      -- library drives yet: no esper in the WoB grants it (genju_prop.asm)
      -- and only Terra and Celes learn it innately, so a cast branch here
      -- would be a branch nothing has ever taken.
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
      end
      -- Whom to heal, with what, and whether it is worth the turn it costs.
      -- M.healDecision is the policy and carries its reasoning; this is the
      -- part that reads the fight.  A candidate is anyone alive and below
      -- maximum, neediest first, and each is offered a cast before the bag
      -- for the reasons at opts.cure above.  The first offer the policy says
      -- yes to gets the turn.
      --
      -- Everyone below maximum, rather than everyone under a fraction: the
      -- policy asks how much of the heal would be wasted, and a fraction gate
      -- in front of it answers a different question and gets it wrong in both
      -- directions.  A 400-HP character at 87% is a full Tonic down and would
      -- never have been offered one; a 250-HP character at 59% was offered a
      -- Potion that wasted half of itself.
      local cands = {}
      for e = 0, 3 do
        local maxhp = M.readWord(0x3C1C + e * 2)
        -- count a heal another actor has already committed as landed, so
        -- two members do not both drink into one hole
        local hp = hpNow[e] + ((healSent and healSent.target == e)
                               and healSent.gain or 0)
        if hp > maxhp then hp = maxhp end
        if hpNow[e] > 0 and maxhp > 0 and hp < maxhp then
          cands[#cands + 1] =
            { e = e, pct = hp * 100 // maxhp, hp = hp, maxhp = maxhp }
        end
      end
      table.sort(cands, function(a, b) return a.pct < b.pct end)
      local allies = 0
      for e = 0, 3 do
        if e ~= actor and hpNow[e] > 0 and M.readWord(0x3C1C + e * 2) > 0 then
          allies = allies + 1
        end
      end
      for _, c in ipairs(cands) do
        local cost = roundCost[c.e] or 0
        -- The cast, offered first.
        --
        -- A cure's size is not knowable in advance -- its magic_prop power is
        -- an input to a formula that scales with the caster's magic power and
        -- level, so reading it would be deciding the policy on a guess -- so
        -- an unmeasured cure goes to M.healDecision as `unknown`, which is
        -- the owner's magic clause: heal that target to maximum.  That cast
        -- is also how the number is obtained.  healWatch measures what it put
        -- back, and from the second cast of the battle the cure is weighed by
        -- the ordinary value rule, because by then the premise the magic
        -- clause rests on has stopped being true.
        --
        -- A cast that fills the target to maximum records nothing, because
        -- the HP that moved understates the spell.  That leaves the
        -- measurement landing exactly where it is load-bearing: a round big
        -- enough to trip the solo heal-lock leaves a hole bigger than the
        -- cure, which is a cast that does not fill anyone up.
        --
        -- The measurement can also miss outright, and then the spell stays
        -- unmeasured and keeps being offered -- the behaviour the cast line
        -- shipped with, so a miss costs nothing it did not already cost.
        -- Measured missing on battle 70: CELES's Cure was planned on EDGAR at
        -- 183/354 and an ally's Potion landed on him first, so the cast
        -- healed a full target and moved no HP.
        if cureRow ~= nil then
          for _, spell in ipairs(type(opts.cure) == "table" and opts.cure
                                 or CURES) do
            local cell, mpCost = spellCell(actor, spell, true)
            if cell ~= nil then
              local gain = castRestore[spell]
              local why = M.healDecision({ hp = c.hp, maxhp = c.maxhp,
                restore = gain, roundCost = cost, allies = allies,
                unknown = gain == nil })
              if why then
                healSaid = nil
                M.log(string.format("[%s] actor=%d cure entity %d (%d/%d) with "
                  .. "$%02X, cell %d, %d MP of %d -- restores %s, a round "
                  .. "costs %d (%s)", tag or "fight", actor, c.e, c.hp,
                  c.maxhp, spell, cell, mpCost, M.readWord(CURMP + actor * 2),
                  gain and tostring(gain) or "?", cost, why))
                return { kind = "heal", spell = spell, target = c.e,
                         row = cureRow }
              end
              local said = string.format("[%s] actor=%d not curing entity %d "
                .. "(%d/%d): $%02X restores %d into a hole of %d, so most of "
                .. "it would be thrown away -- acting instead", tag or "fight",
                actor, c.e, c.hp, c.maxhp, spell, gain, c.maxhp - c.hp)
              if said ~= healSaid then healSaid = said; M.log(said) end
            end
          end
        end
        -- then the bag, with whichever heal fits the hole best
        local item = row ~= nil and bagHeal(c.maxhp - c.hp) or nil
        if item then
          local gain = itemRestoreOf(item)
          local why = M.healDecision({ hp = c.hp, maxhp = c.maxhp,
            restore = gain, roundCost = cost, allies = allies })
          if why then
            healSaid = nil
            M.log(string.format("[%s] actor=%d heal entity %d (%d/%d) with " ..
              "$%02X -- restores %d into a hole of %d, a round costs %d (%s)",
              tag or "fight", actor, c.e, c.hp, c.maxhp, item, gain,
              c.maxhp - c.hp, cost, why))
            return { kind = "item", item = item, target = c.e, row = row,
                     idx = battInvIdx(item) }
          end
          local said = string.format("[%s] actor=%d not healing entity %d " ..
            "(%d/%d): $%02X restores %d into a hole of %d, so most of it "
            .. "would be thrown away -- acting instead", tag or "fight",
            actor, c.e, c.hp, c.maxhp, item, gain, c.maxhp - c.hp)
          if said ~= healSaid then healSaid = said; M.log(said) end
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
    -- opts.magic = { [charId] = { spell = id, boost = false } }: the
    -- attack-magic line, the same shape as the tactical skills.  Open the
    -- Magic list through the $7BC2 state machine, steer to the spell's own
    -- cell against the live cursor cells, and confirm on the enemy the focus
    -- list picks (or the default enemy target when there is no focus list).
    --
    -- The caller names a spell id, not a grid row.  It used to name the row,
    -- with the MP price as a second caller-supplied number, and both are
    -- wrong to hand in: the compacted list's rows move with the party's
    -- loadout, and OT6 prices a folded cast at the tier it folds to
    -- (battle_subjob scenario C: a boosted Bolt executes as Bolt 3 and is
    -- charged Bolt 3's 53 MP).  spellCell answers both from the engine.  A
    -- character who cannot pay falls through to the branches below, so a
    -- mage out of MP Fights instead of wedging the menu.
    --
    -- opts.magic[id].boost = false keeps the cast at its base tier, which is
    -- what a caller wants when the point is the element rather than the
    -- damage and the BP is owed to somebody's break.
    local mg = opts.magic and opts.magic[id]
    if mg and cmdRow(actor, CMD_MAGIC) then
      local cell, cost = spellCell(actor, mg.spell, true)
      if cell ~= nil then
        M.log(string.format("[%s] actor=%d cast $%02X, cell %d, %d MP of %d",
          tag or "fight", actor, mg.spell, cell, cost,
          M.readWord(CURMP + actor * 2)))
        return { kind = "magic", spell = mg.spell,
                 row = cmdRow(actor, CMD_MAGIC),
                 boostLeft = mg.boost == false and 0 or boost }
      end
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
    if st == ST_MAGIC and (plan.kind == "magic" or plan.kind == "heal") then
      -- The same two-column walk for both magic lines.  The cell was
      -- resolved at plan time, but the list is rebuilt when the window
      -- opens, so it is re-read here: a cell that has moved (or a spell the
      -- engine has since greyed) drops the plan rather than steering to
      -- whatever now occupies the old row.
      local cell = spellCell(actor, plan.spell, false)
      if cell == nil then plan, planActor = nil, nil; return { "b" } end
      local wr, wc = cell // 2, cell % 2
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
      -- Both ally-targeted lines steer the same way: an item and a cure
      -- differ only in which window chose them.  gen_vargas's hand-written
      -- Cure drive already crossed sides and walked $7B7D exactly like its
      -- Potion drive (gen_vargas.lua:281-300); this is that, shared.
      if plan.kind == "item" or plan.kind == "heal" then
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
      -- target plans steer to its mask (summons, items and cures keep their
      -- own targeting), and the tgtSpin backstop still confirms rather than
      -- holding the turn open.
      if opts.focus and plan.kind ~= "item" and plan.kind ~= "summon"
         and plan.kind ~= "heal" then
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
      elseif plan.kind == "heal" and castRestore[plan.spell] == nil then
        watch = { into = castRestore, id = plan.spell, what = "cure" }
      end
      if watch then
        watch.target = plan.target
        watch.hp = M.readWord(0x3BF4 + plan.target * 2)
        watch.maxhp = M.readWord(0x3C1C + plan.target * 2)
        watch.until_ = battleTick + 900
        healWatch = watch
      end
      -- and remember it as in flight, so the next actor to decide sees the
      -- hole this heal is about to fill rather than the one on screen
      -- The window matches healWatch's 900 ticks, which is what the fights
      -- below were measured with.  It is longer than a confirmed action
      -- needs, and this record SUPPRESSES healing while it stands, so a
      -- shorter bound is probably right; it is not measured, so it is not
      -- taken here.
      if plan.kind == "item" and plan.item ~= FENIX_DOWN then
        healSent = { target = plan.target, gain = itemRestoreOf(plan.item),
                     hp = M.readWord(0x3BF4 + plan.target * 2),
                     until_ = battleTick + 900 }
      elseif plan.kind == "heal" then
        healSent = { target = plan.target,
                     gain = castRestore[plan.spell]
                       or M.readWord(0x3C1C + plan.target * 2),
                     hp = M.readWord(0x3BF4 + plan.target * 2),
                     until_ = battleTick + 900 }
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
    -- Everything the heal policy measured belongs to the battle that just
    -- ended.  A retry ladder replays the same fight from a reload, and
    -- carrying a round cost across the boundary would let one attempt's
    -- damage decide the next attempt's first turns.
    roundCost, turnSnap = {}, {}
    itemRestore, castRestore = {}, {}
    healWatch, healSent, healSaid = nil, nil, nil
  end

  function F.frame()
    battleTick = battleTick + 1
    -- The landed value of a heal, watched from its confirmation until the HP
    -- moves.  HP falling first is the enemy acting between the confirm and
    -- the heal, so the baseline follows it down rather than reading the
    -- rebound as a bigger heal than it was.
    -- A heal that fills the target to maximum is CLIPPED, and the HP it moved
    -- is a lower bound rather than what the heal is worth.  Recording one
    -- would tell the policy the heal is far weaker than it is, and the policy
    -- would then decline it for the rest of the battle.  Measured on the
    -- minecart ride, where the same Cure moved 42, 84, 178 and 184 hp
    -- depending on how much room the target had: 42 would have retired the
    -- ride's whole healing line.  So a clipped heal is not recorded; it stays
    -- unmeasured, which falls back to the item's power byte or to offering
    -- the cast, and the next use on somebody with room measures it properly.
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
    -- The in-flight heal above stops counting the moment its HP shows up, or
    -- if it never does.  A heal that misses leaves the hole where it was, and
    -- holding a phantom fill over it would stop anyone healing that member.
    if healSent then
      local hp = M.readWord(0x3BF4 + healSent.target * 2)
      if hp > healSent.hp or hp == 0 or battleTick > healSent.until_ then
        healSent = nil
      elseif hp < healSent.hp then
        healSent.hp = hp
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
    -- The absorb guard rides here rather than inside the battle drivers
    -- because a route need not use one: gen_ifrit_magicite plays battle 70
    -- with its own tactical driver, and a guard hung off M.fightBattle
    -- would not see that fight at all.  Every test in the tree goes
    -- through this one callback.
    local ok, r = pcall(function()
      local bad = M.absorbGuardTick()
      if bad then error(bad, 0) end
      return root:tick()
    end)
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
