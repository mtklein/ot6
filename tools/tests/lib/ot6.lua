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
  if OT6_LIVE then recordPad() end
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

-- True once the battle module has begun loading.
--
-- $7E3BF4 is the party battle-HP table only while the battle module owns
-- that RAM; other modules write over the same bytes.  So this checks the
-- shape of the whole table rather than one slot: every word must be a
-- plausible current HP (0 for an empty or dead slot, else 1..9999) and at
-- least one character alive.  $FFFF/$FF00 anywhere means these bytes
-- belong to another module.
--
-- Known limit: a total party wipe is all zeros, the same shape a menu
-- leaves, so this reports false for a wipe.
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

function M.monsterAbsorb(species)
  return M.readRomByte((M.sym("MonsterProp") & 0x3FFFFF)
    + species * MON_REC + MON_ABSORB)
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
-- cond (inside a driveUntil body) re-asks its predicate.  Top-level steps
-- tick once and are never reset, so their behavior is unaffected.
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

-- Run the body steps in a loop until pred() is truthy.  Raises after
-- maxFrames.  Completion releases the pad: pred can fire mid-body-cycle,
-- abandoning the body wherever it stands, and a button it was holding at
-- that instant must not stay held into the steps that follow (a stuck
-- d-pad auto-repeats the battle-menu cursor and a stuck A confirms into
-- target selection).
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
function M.clearBattle(maxFrames, spare)
  local spareSet = {}
  for _, w in ipairs(spare or {}) do spareSet[w] = true end
  local aPhase = 0
  return M.seqStep({
    M.driveUntil(function()
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
    }, "clear battle"),
    -- heal-after-every-battle: recover outside combat before the script's
    -- next beat (zero frames when nobody needs it; skipped under a live
    -- event timer)
    M.careStop("care after battle (clearBattle)"),
  })
end

-- -------------------------------------------- input-driven battle endings --
-- A script may inject input and read memory, and may never write emulated
-- game state.  These two end a battle the way a player can, with no
-- writes, and are the opt-in replacements for clearBattle's flag write.
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
--   * steering rotates the d-pad one direction per press cycle rather than
--     per frame; a per-frame rotation flips direction mid-hold and
--     registers nothing;
--   * the cursor grid follows the formation's screen layout, so rotating
--     through all four directions settles on any reachable slot: monster
--     grids walk {left,down,right,up}, character columns
--     {down,up,left,right}.
-- Known limit: on a 2x2 formation the two-press rotation cycles among
-- three hover positions and the ally column, and cannot reach a slot that
-- needs a bare up-then-right.  All four masks are reachable by single
-- presses with a dwell between them; a caller whose formation needs that
-- steers with its own press plan and uses only the latch half of this
-- machine.
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
    -- press-0 must index dirs[1], not dirs[#dirs]: Lua floor division
    -- takes (0-1)//2 to -1 and -1 % #dirs to #dirs-1, so the old
    -- ((T.press - 1) // 2) emitted the LAST direction on the first
    -- frames of every target-select.  Measured on the Thamasa ambush
    -- (pincer formation, char-column dirs): the stray press exiled the
    -- cursor into a monster group within 3 frames of the window opening,
    -- and the timeout's blind A then fed Fenix Downs to a Balloon --
    -- eight ~1740-frame whiff episodes on one seed.  Other callers were
    -- shielded only by coincidence (their configs make the stray press
    -- "up", or a no-op).
    return dirs[(math.max(T.press - 1, 0) // 2) % #dirs + 1]
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
  local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
  local AUTOCROSSBOW, PUMMEL = M.AUTOCROSSBOW, 0x5D
  -- The cures, cheapest first: the loop simply casts again if the target
  -- is still short, so overshoot is only wasted MP.  Under OT6 the upper
  -- tiers are folds of the base spell rather than separate grants, so in
  -- practice only the first of these is ever found in the list.
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
  local loreSpinN = 0                  -- frames spent on live lore plans
                                       -- since the last landed lore cast
  local loreDead = false               -- the stall guard fired this battle

  local function cmdRow(actor, cmd)
    for row = 0, 3 do
      if M.readByte(CMDTBL + actor * 12 + row * 3) == cmd then
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

  -- The absorb guard, shared by every attack-cast line: a spell whose
  -- element a PRESENT species absorbs is a heal for the enemy, so the plan
  -- is refused and the actor falls through (usually to Fight).  Folding
  -- never changes a family's element, so the base ability's byte answers
  -- for every tier a pending boost could fold to.
  local function absorbSlot(abilityId)
    local elem = M.spellElement(abilityId)
    if elem == 0 then return nil end
    for _, s in ipairs(M.formationSpecies()) do
      if M.monsterAbsorb(s.species) & elem ~= 0 then return s end
    end
    return nil
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
    turnSnap[actor] = hpNow
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
      -- part that reads the fight.  A candidate is anyone hurt enough to top
      -- up or standing inside one round of death, neediest first, and each is
      -- offered a cast before the bag for the reasons at opts.cure above.
      -- The first offer the policy says yes to gets the turn.
      local threshold = opts.healPercent or 60
      local cands = {}
      for e = 0, 3 do
        local hp, maxhp = hpNow[e], M.readWord(0x3C1C + e * 2)
        if hp > 0 and maxhp > 0 then
          local pct = hp * 100 // maxhp
          if pct < threshold or hp <= (roundCost[e] or 0) then
            cands[#cands + 1] = { e = e, pct = pct, hp = hp, maxhp = maxhp }
          end
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
                         row = cureRow }
              end
              local said = string.format("[%s] actor=%d not curing entity %d "
                .. "(%d/%d): $%02X restores %d and a round costs %d, so the "
                .. "turn buys back less than it spends -- acting instead",
                tag or "fight", actor, c.e, c.hp, c.maxhp, spell, gain, cost)
              if said ~= healSaid then healSaid = said; M.log(said) end
            end
          end
        end
        -- then the bag
        local item = row ~= nil
                 and ((c.maxhp - c.hp >= 80 and battInvIdx(POTION)) and POTION
                   or battInvIdx(TONIC) and TONIC
                   or battInvIdx(POTION) and POTION) or nil
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
                     idx = battInvIdx(item) }
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
    -- The boost bank.  Spending one BP as soon as it is available plays
    -- OT6's economy badly: damage while a monster still has shields is
    -- halved, with ratios broken:weak:unweak = 4:2:1, so the intended play
    -- is to boost until the shield breaks and then hit.  opts.bank means:
    -- act unboosted, which regenerates BP, until the bank reads at least
    -- this value, then spend.
    local have = M.readByte(BP + actor * 2)
    local boost = 0
    if opts.boost then
      if opts.bank and have < opts.bank then boost = 0
      else boost = math.min(have, 3) end
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
      -- The absorb guard, at plan time, for the ability's element (the
      -- shared absorbSlot above).
      local absorbed = absorbSlot(mg.spell)
      if absorbed then
        M.log(string.format(
          "[%s] cast $%02X refused: %s is ABSORBED by slot %d species " ..
          "$%04X (#99) -- falling through to Fight",
          tag or "fight", mg.spell, M.elemStr(M.spellElement(mg.spell)),
          absorbed.slot, absorbed.species))
        mg = nil
      end
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
      end
    end
    -- opts.nuke = { spellId, ... } and opts.nukeLore = { loreId, ... }: the
    -- party-wide attack repertoire, tried in order, first castable wins
    -- (owner directive: a party without Edgar or Sabin should nuke, not
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
            local absorbed = absorbSlot(0x8B + lid)
            if absorbed then
              M.log(string.format(
                "[%s] lore $%02X refused: %s is ABSORBED by slot %d species "
                .. "$%04X (#99) -- falling through",
                tag or "fight", lid, M.elemStr(M.spellElement(0x8B + lid)),
                absorbed.slot, absorbed.species))
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
        if cell ~= nil
           and M.readWord(CURMP + actor * 2) - cost >= nukeFloor(actor) then
          local absorbed = absorbSlot(spell)
          if absorbed then
            M.log(string.format(
              "[%s] nuke $%02X refused: %s is ABSORBED by slot %d species "
              .. "$%04X (#99) -- falling through",
              tag or "fight", spell, M.elemStr(M.spellElement(spell)),
              absorbed.slot, absorbed.species))
          else
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
    -- opts.tools = false disables the Tools line while keeping the rest of
    -- the tactical kit.  Against a formation where a multi-target attack
    -- (AutoCrossbow hits all targets) heals the enemy, Edgar's
    -- single-target pierce Fight removes the same class-weak shields
    -- without triggering that heal.
    if opts.tactical and opts.tools ~= false and id == 4
       and M.readWord(CURMP + actor * 2) >= 4
       and cmdRow(actor, CMD_TOOLS) then
      return { kind = "skill", cmd = CMD_TOOLS, skill = opts.tool or AUTOCROSSBOW,
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
    if st == ST_CMD then tgtSpin = 0 end
    -- The lore stall guard, checked wherever a lore plan is live rather
    -- than only at plan time: a pursuit wedged inside the window (the
    -- wrong-row failure mode) never returns to makePlan on its own.
    if plan ~= nil and planActor == actor and plan.kind == "lore"
       and loreSpinN > LORE_STALL and not loreDead then
      loreDiagnose(actor, loreCell(actor, plan.lore, false))
      plan, planActor = nil, nil
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
      -- read: mid-menu inventory reads return wrong values, and a wrong
      -- read here returns nil, drops the plan, presses B, and re-plans,
      -- without end.
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
      -- differ only in which window chose them.
      if plan.kind == "item" or plan.kind == "heal" then
        local chars, mons = M.readByte(TGTCHARS), M.readByte(TGTMONS)
        if mons ~= 0 then return { "right" } end
        -- Neither side is selected: falling into the steer below with
        -- chars = 0 would set cur = 0 and, for target 0, spin forever
        -- pressing UP.
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
         and plan.kind ~= "heal" and plan.kind ~= "lore" then
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
          if mons ~= want then
            tgtSpin = tgtSpin + 1
            if tgtSpin < 24 then
              -- on the ally side (mons == 0), LEFT crosses to the enemy
              -- side.  Among monsters the walk leads with LEFT/RIGHT: a
              -- side-by-side formation's rest mask does not move on
              -- down/up.
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
      -- A confirmed lore is the progress the stall guard watches for.
      if plan.kind == "lore" then
        loreSpinN = 0
        M.log(string.format("[%s] lore $%02X confirmed", tag or "fight",
          plan.lore))
      end
      -- A refused confirm (corpse under the target cursor) re-enters
      -- button()'s plan-nil ST_TGT head next tick, which owns the
      -- backstop; the optimistic clear here is what routes it there.
      plan, planActor = nil, nil
      return { "a" }
    end
    if st == ST_ITEM or st == ST_TOOLS or st == ST_MAGIC or st == ST_ESPER
       -- the lore states join the back-out set only when the repertoire is
       -- in play: without opts.nukeLore nothing here ever opens that
       -- window, and the default driver stays byte-identical.
       or (opts.nukeLore and (st == ST_LORE or st == ST_LORE_OPEN)) then
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
    healWatch, healSaid = nil, nil
    -- The stall guard's verdict belongs to the battle it watched: a retry
    -- ladder's reload is a different fight, and a recurrence should dump
    -- again there rather than inherit a dead lore line silently.
    loreSpinN, loreDead = 0, false
  end

  function F.frame()
    battleTick = battleTick + 1
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
    if plan and planActor ~= actor then plan, planActor = nil, nil end
    -- The stall guard's clock: frames spent on a LIVE lore plan, rather
    -- than wall clock since the first offer, so another actor's slow turn
    -- between two pursuits cannot fire it.
    if plan and plan.kind == "lore" then loreSpinN = loreSpinN + 1 end
    if ph == 0 then held = button(actor) or {} end
    M.setPad(ph < 6 and held or {})
  end

  return F
end

function M.fightBattle(maxFrames, spare)
  local spareSet = {}
  for _, w in ipairs(spare or {}) do spareSet[w] = true end
  local aPhase = 0
  return M.seqStep({
    M.driveUntil(function()
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
    }, "fight battle (tap-A)"),
    M.careStop("care after battle (fightBattle)"),
  })
end

-- The command-table-aware counterpart to fightBattle().  Prefer this for a
-- mixed party or any route where command row 0 is not proven to be Fight.
function M.fightBattleByMenu(maxFrames, spare)
  local spareSet = {}
  for _, w in ipairs(spare or {}) do spareSet[w] = true end
  local F = M.newFightDriver("fightBattleByMenu")
  return M.seqStep({
    M.driveUntil(function()
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
    }, "fight battle through the Fight menu"),
    M.careStop("care after battle (fightBattleByMenu)"),
  })
end

-- fleeBattle: hold L+R, which is the engine's run mechanic (see the pad map
-- above; vanilla's run timer counts held L or R).  It takes fewer frames than
-- fighting when it works, and it times out on unrunnable formations
-- and on every event battle whose win-bit the story checks, so callers pick
-- fight or flee per step and record why.  No writes.
function M.fleeBattle(maxFrames)
  return M.seqStep({
    M.driveUntil(function()
      return not M.battleLoadStarted()
    end, maxFrames or 9000, {
      M.call(function() M.setPad({ l = true, r = true }) end),
    }, "flee battle (hold L+R)"),
    M.careStop("care after battle (fleeBattle)"),
  })
end

-- The runner.  steps: list of step objects.  opts.maxFrames: global budget.
local runnerStarted = false

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

function M.run(opts, steps)
  assert(not runnerStarted, "ot6.run() called twice")
  runnerStarted = true
  opts = opts or {}
  local budget = opts.maxFrames or 60000
  local root = seqStep(steps)
  local finished = false

  -- Silent-auto-Continue canary.  Every game-over path routes through the
  -- event GameOver script ($CC/E568); when it runs, the title screen
  -- follows, and any driver that mashes A auto-Continues the last save,
  -- after which the session has TIME-TRAVELED (roster and switches
  -- revert) while every naive predicate reads healthy.  So the default is
  -- LOUD: GameOver fails the run, unless the route declares it survivable
  -- (opts.allowGameOver, or a ladder setting M.gameOverFired = 0 after
  -- handling its reload).
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
  M.gameOverFired = 0
  local goReadFired, titleExecFired = 0, 0
  local canaryInGame = false
  do
    local ok, addr = pcall(function() return M.sym("GameOver") end)
    if ok then
      emu.addMemoryCallback(function()
        if canaryInGame then
          goReadFired = goReadFired + 1
          M.gameOverFired = M.gameOverFired + 1
        end
      end, emu.callbackType.read, addr, addr)
    end
  end
  do
    local ok, addr = pcall(function() return M.sym("TitleScreen") end)
    if ok then
      emu.addMemoryCallback(function()
        if canaryInGame then
          titleExecFired = titleExecFired + 1
          M.gameOverFired = M.gameOverFired + 1
        end
      end, emu.callbackType.exec, addr, addr)
    end
  end

  emu.addEventCallback(function()
    if finished then return end
    if not canaryInGame and (M.hasControl() or M.battleLoadStarted()) then
      canaryInGame = true
    end
    if M.gameOverFired > 0 and not opts.allowGameOver then
      finished = true
      traceFlush()
      coverageFlush()
      M.log(string.format("FAIL: GAME OVER fired (GameOver read x%d, " ..
        "TitleScreen exec x%d) -- the run " ..
        "lost and any further input auto-Continues the last save, which " ..
        "reads as silent time travel.  A ladder that can survive this " ..
        "must reload BEFORE the game-over lands, or clear " ..
        "M.gameOverFired after handling it (see #127's ambush finding).",
        goReadFired, titleExecFired))
      emu.stop(3)
      return
    end
    M.frame = M.frame + 1
    if OT6_LIVE and (M.frame == 20 or M.frame % LIVE_IVL == 0) then M.liveShot() end
    if M.frame > budget then
      finished = true
      traceFlush()
      coverageFlush()
      M.log("FAIL: frame budget exceeded (" .. budget .. " frames)")
      emu.stop(2)
      return
    end
    -- The absorb guard rides here rather than inside the battle drivers
    -- because a route need not use one of those drivers at all, and every
    -- test in the tree goes through this one callback.  The tile trace
    -- rides here for the same reason.
    local ok, r = pcall(function()
      traceTick()
      local bad = M.absorbGuardTick()
      if bad then error(bad, 0) end
      return root:tick()
    end)
    if not ok then
      finished = true
      traceFlush()
      coverageFlush()
      M.log("FAIL: " .. tostring(r))
      emu.stop(1)
    elseif r == "done" then
      finished = true
      traceFlush()
      coverageFlush()
      M.log("PASS (frame " .. M.frame .. ")")
      emu.stop(0)
    end
  end, emu.eventType.startFrame)
end

return M
