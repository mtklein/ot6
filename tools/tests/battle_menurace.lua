-- @suite savestate=first_battle
-- battle_menurace.lua -- the battle menu's state pair survives a frame interrupt between its two writes (#475).
--
--   tools/tests/run.sh tools/tests/battle_menurace.lua
--
-- The mechanism.  $7BC2 is the battle menu's state, run once a frame by the NMI's UpdateMenuState, and
-- $7BC3-$7BC8 the states queued behind it.  State $01 waits for the window animation queue ($7BF0) to drain and
-- then shifts the queue up one ($7BC2 <- $7BC3, ...); state $02 shifts at once; state $00 does nothing.  The main
-- thread opens a character's command window (window_open) by queueing $04 behind $01: vanilla wrote that pair
-- as two byte stores, $7BC3 first.  A command handed from one character to the next leaves the old state $01
-- pending with the animation queue already drained (the main thread's window_close drained it); when the frame
-- interrupt lands between the two stores, the OLD $01 shifts the new $04 in, the main thread then writes $01
-- over it, and the next interrupt shifts in the empty slot behind: state $00, which reads no input, with the
-- window open.  Nobody can act again, a person included.  Seen once in 413 lab runs (#474's lab,
-- build/attempts/wt/v037-tritoch/lab/trace/k0_s57.log.gz: "w $7BC3=04 pc=C144C8", then UpdateMenuState's
-- "w $7BC2=04 pc=C15A7D", then "w $7BC2=01 pc=C144CD").  The same pair, two byte stores from the main thread,
-- opens and closes the battle dialog window (window_mess_open $3B/$01, _c143cc and battle event $10 $3C/$02).
--
-- The declared fault injection (a synthetic mechanism test, docs/TESTING.md; not play).  The interrupt cannot be
-- placed by input, so at each of those sites the CPU is held right after the site's FIRST write to the pair
-- until UpdateMenuState has run once: each time the instruction after that write comes up, an exec callback
-- moves the program counter back to the write (emu.setState, the one declared write), which stores the same
-- value again, so the machine idles on that boundary, takes the real NMI there, and returns to the real
-- instruction.  No byte of RAM changes; the held CPU only runs late, as a main thread a frame behind would.  The fight is the first battle on tap-A, waiting with the menu up (reading the ATB queue,
-- $7E4001) until a second member is ready, so each command hands the menu straight to the next member.  The
-- first battle opens no dialog window, so the hold is armed at the dialog sites but only window_open's runs
-- here.  (An exec callback cannot change the opcode it reports: Mesen calls it from ProcessInstruction with a
-- copy, so answering the fetch with BRA -2 held nothing: build/attempts/wt/v037-menu-race/suite/mr_main1.)
--
-- Passes when: every held pair's queued state ($04 for a command window) is the state UpdateMenuState next runs
-- under within 240 frames, the battle ends, and at least one held window_open met the race's precondition
-- (the old state $01/$02 pending at entry, the animation queue drained when the held interrupt ran).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/first_battle.mss.lua"
local UMS = H.sym("UpdateMenuState")
-- each main-thread site writing the pair: its code range [lo, hi), hi the next routine's label
local SITES = {
  { "window_open", H.sym("window_open"), H.sym("UpdateCharText") },
  { "window_mess_open", H.sym("window_mess_open"), H.sym("_c1434b") },
  { "_c143cc", H.sym("_c143cc"), H.sym("window_close") },
  { "BattleEventCmd_10", H.sym("BattleEventCmd_10"), H.sym("BattleEventCmd_01") },
}
local DEADLINE = 240

local ums = 0           -- UpdateMenuState runs so far
local rec = nil         -- the pair in flight (one at a time: the main thread is one thread)
local opened = {}       -- every pair, for the summary
local failure = nil
local holds, raced = 0, 0
local function pc() local s = emu.getState(); return (s["cpu.k"] << 16) | s["cpu.pc"] end

-- the declared write: the CPU's program counter, moved back to the pair's first write while held
local function setPc(addr) emu.setState({ ["cpu.pc"] = addr & 0xFFFF }) end

for _, site in ipairs(SITES) do
  local name, lo, hi = site[1], site[2], site[3]
  -- every instruction the routine starts: its entry opens a record; then the last one run is the writer
  emu.addMemoryCallback(function(addr)
    if addr == lo then
      rec = { site = name, f = H.frame, s0 = H.readByte(0x7BC2), q0 = H.readByte(0x7BC3), bf0 = H.readByte(0x7BF0) }
      opened[#opened + 1] = rec
    end
    local r = rec
    if r == nil or r.site ~= name then return end
    if r.holdAt == nil then r.lastExec = addr; return end
    if r.released or addr ~= r.holdAt then return end
    if ums > r.armUms or H.frame - r.f > 3 then
      r.released = true             -- the interrupt has run: on with the real instruction
      return
    end
    r.spins = r.spins + 1
    setPc(r.writer)                 -- not yet: run the first write's store again (the same value, idempotent)
  end, emu.callbackType.exec, lo, hi - 1)
  -- the pair's writes from this range: the first arms the hold at the instruction after it
  emu.addMemoryCallback(function(addr, value)
    local r = rec
    if r == nil or r.site ~= name then return end
    local p = pc()
    if p < lo or p >= hi then return end
    if addr & 0xFFFF == 0x7BC3 then r.q = value end
    if r.holdAt == nil then
      r.holdAt, r.writer, r.armUms, r.spins, r.first = p, r.lastExec, ums, 0, addr & 0xFFFF
    end
  end, emu.callbackType.write, 0x7E7BC2, 0x7E7BC3)
end

emu.addMemoryCallback(function()
  ums = ums + 1
  local st, bf = H.readByte(0x7BC2), H.readByte(0x7BF0)
  for i = #opened, math.max(1, #opened - 8), -1 do
    local r = opened[i]
    if r.holdAt ~= nil and not r.done then
      if r.heldState == nil and ums == r.armUms + 1 then
        -- the interrupt the hold let in, between the pair's first write and its last
        r.heldState, r.heldBf0 = st, bf
      elseif r.q ~= nil and r.heldState ~= nil and st == r.q then
        r.done, r.df = true, H.frame
      elseif failure == nil and r.q ~= nil and H.frame - r.f > DEADLINE then
        failure = string.format("%s at f%d (entry $7BC2=%02X $7BC3=%02X $7BF0=%02X; first write $%04X, held %d "
          .. "spin(s), the held interrupt ran under $7BC2=%02X $7BF0=%02X) queued state $%02X, and UpdateMenuState "
          .. "has not run it in %d frames: the menu sits in state $%02X (window flag $7BCA=%02X)",
          r.site, r.f, r.s0, r.q0, r.bf0, r.first or 0, r.spins or 0, r.heldState or 0xFF, r.heldBf0 or 0xFF, r.q,
          DEADLINE, st, H.readByte(0x7BCA))
      end
    end
  end
end, emu.callbackType.exec, UMS, UMS)

-- every pair closed out: log it, count the holds and the raced ones
local function settle()
  for _, r in ipairs(opened) do
    if not r.said and (r.done or failure) then
      r.said = true
      local race = r.site == "window_open" and (r.s0 == 0x01 or r.s0 == 0x02) and r.heldBf0 == 0
      if r.holdAt then holds = holds + 1 end
      if race then raced = raced + 1 end
      H.log(string.format("[menurace] %s f%d: entry $7BC2=%02X $7BC3=%02X $7BF0=%02X; first write $%04X, held %d "
        .. "spin(s), the interrupt ran under $7BC2=%02X $7BF0=%02X%s; queued $%02X %s", r.site, r.f, r.s0, r.q0,
        r.bf0, r.first or 0, r.spins or 0, r.heldState or 0xFF, r.heldBf0 or 0xFF,
        race and " (the race: the old state pending, the animation drained)" or "", r.q or 0xFF,
        r.done and string.format("ran at f%d", r.df) or "NEVER ran"))
    end
  end
end

local tap = 0
H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 600, "the first battle to be active", 10),
  H.driveUntil(function() return failure ~= nil or not H.battleLoadStarted() end, 20000, {
    H.call(function()
      settle()
      -- tap A, but with a menu up only once a second member is queued behind it
      local queued = 0
      for x = 0, 3 do if H.readByte(0x4001 + x) ~= 0xFF then queued = queued + 1 end end
      tap = (tap + 1) % 8
      local menuUp = H.readByte(0x7BCA) ~= 0
      H.setPad((tap < 4 and (not menuUp or queued >= 2 or H.frame - (rec and rec.f or 0) > 900)) and { "a" } or {})
    end),
  }, "the first battle on tap-A"),
  H.call(function()
    settle()
    if failure then error("[menurace] FAIL " .. failure, 0) end
    H.log(string.format("[menurace] %d pair(s), %d held, %d window_open hand-off(s) under the race's precondition",
      #opened, holds, raced))
    H.assertEq(raced >= 1, true, "at least one held window_open met the race's precondition")
    H.log("[menurace] PASS: every held pair's queued state ran; the battle ended")
  end),
})
