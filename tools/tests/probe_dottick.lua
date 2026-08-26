-- probe_dottick.lua -- measures whether a poison status tick reaches the
-- chip path, by poisoning a guard in the opening fight and watching the
-- chip hook.
--
-- Cmd_22 (the DOT command) tail-jumps into ExecSelfAttack, so a DOT tick's
-- whole damage resolution, including any Ot6Chip / Ot6ClassChip call,
-- happens synchronously inside that one command, on the same emulated
-- frame. `inDot` means "a Cmd_22 exec callback fired on this frame", cross-
-- checked against the DOT record's own signature: $11a2 = $68 and
-- $11a6 = 2 are Cmd_22's literal stores, which no ordinary action carries.
--
-- Setup (battle_break's, plus battle_hits's berserk driver so battle time
-- keeps running with no menu holding wait-mode):
--   guard A, entity $0c: weak = poison only ($3BEC=$08), class-weak 0,
--     absorb/null/resist cleared, 2 shields, poison status set
--   guard B, entity $0e: weak = fire only ($3BEE=$01), class-weak 0,
--     2 shields, poison status set. Negative control: it takes the same
--     ticks, and if its shields move, chipping is not element-matched.
--   party: Fight-only command lists + berserk, magitek status cleared,
--     weapon elements zeroed. With class-weak 0 on both guards and no
--     weapon element, no party swing can chip either guard, so every
--     shield transition observed here is a DOT tick or a bug.
--
-- Phases:
--   1. Poison at the engine's own cadence. Logs the counter machinery
--      ($3adc counter / $3add slow-normal-haste constant / $3af0 dot
--      counter) and the per-tick HP drop.
--   2. Sap/seize. Its Cmd_22 branch never reaches the poison-element
--      store, so ticks arrive, damage lands, and nothing chips.
--   3. The cap: guard A is left one shield from break so the next tick
--      empties it, and the window is then watched to the end and past
--      recovery. This phase also pokes $3add -> $80 to speed the counter
--      up; the engine re-derives the slow/normal/haste constant, so this
--      has no effect and phase 3 runs at the same cadence phase 1 measured.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

-- entity map (battle_break.lua's fight): guards in monster slots 2/3
local A, B = 0x0c, 0x0e
local function shieldA() return H.readByte(0x3E38 + A) end
local function shieldB() return H.readByte(0x3E38 + B) end
local function timerA()  return H.readByte(0x3E88 + A) end
local function revA()    return H.readByte(0x3E89 + A) end
local function revB()    return H.readByte(0x3E89 + B) end

local ATB_FAST = 0x1000
local function bumpAtb()
  for slot = 0, 3 do H.writeWord(0x3AC8 + slot * 2, ATB_FAST) end
end

local function keepAlive()
  H.writeWord(0x3C00, 5000)
  H.writeWord(0x3C02, 5000)
  for c = 0, 2 do
    local a = 0x3BF4 + c * 2
    if H.readWord(a) > 0 and H.readWord(a) < 200 then H.writeWord(a, 400) end
  end
  bumpAtb()
end

-- ------------------------------------------------------------- recording --
local dotFrame, dotY = nil, nil   -- the frame/target of the last Cmd_22 exec
local dots = {}                -- every Cmd_22 firing
local function inDot() return dotFrame == H.frame end
local chips = {}               -- every Ot6Chip firing
local classChips = {}          -- every Ot6ClassChip firing
local shieldWrites = {}        -- every write to either guard's shield byte
local refs = {}

local function ctx()
  return {
    frame = H.frame,
    y = emu.getState()["cpu.y"] & 0xFF,
    e = H.readByte(0x11a1),          -- attack elements
    f2 = H.readByte(0x11a2),         -- spell flags2 ($68 for the DOT record)
    f4 = H.readByte(0x11a4),         -- spell flags3
    pow = H.readByte(0x11a6),        -- power
    cls = H.readByte(0x57b8),        -- OT6_ATKCLASS
    sa = shieldA(), sb = shieldB(), ta = timerA(),
    dot = inDot(), dotY = inDot() and dotY or nil,
  }
end

local function fmt(c)
  return string.format(
    "f%-6d y=%02X elem=%02X flags2=%02X flags3=%02X pow=%02X atkclass=%02X " ..
    "shields=%d,%d timerA=%02X inDot=%s",
    c.frame, c.y, c.e, c.f2, c.f4, c.pow, c.cls, c.sa, c.sb, c.ta,
    tostring(c.dot))
end

local function arm()
  refs.cmd22 = emu.addMemoryCallback(function()
    dotFrame = H.frame
    dotY = emu.getState()["cpu.y"] & 0xFF
    dots[#dots + 1] = { frame = dotFrame, y = dotY,
                        b6 = H.readByte(0xb6),
                        hpA = H.readWord(0x3C00), hpB = H.readWord(0x3C02) }
  end, emu.callbackType.exec, H.sym("Cmd_22"), H.sym("Cmd_22"))

  refs.chip = emu.addMemoryCallback(function()
    chips[#chips + 1] = ctx()
  end, emu.callbackType.exec, H.sym("Ot6Chip"), H.sym("Ot6Chip"))

  refs.cchip = emu.addMemoryCallback(function()
    classChips[#classChips + 1] = ctx()
  end, emu.callbackType.exec, H.sym("Ot6ClassChip"), H.sym("Ot6ClassChip"))

  for _, e in ipairs({ A, B }) do
    local a = 0x7e0000 + 0x3E38 + e
    refs["sh" .. e] = emu.addMemoryCallback(function(addr, value)
      shieldWrites[#shieldWrites + 1] = {
        frame = H.frame, e = e, v = value, dot = inDot(),
        elem = H.readByte(0x11a1), f2 = H.readByte(0x11a2),
      }
    end, emu.callbackType.write, a, a)
  end
end

local function disarm()
  if refs.cmd22 then
    emu.removeMemoryCallback(refs.cmd22, emu.callbackType.exec,
      H.sym("Cmd_22"), H.sym("Cmd_22"))
    emu.removeMemoryCallback(refs.chip, emu.callbackType.exec,
      H.sym("Ot6Chip"), H.sym("Ot6Chip"))
    emu.removeMemoryCallback(refs.cchip, emu.callbackType.exec,
      H.sym("Ot6ClassChip"), H.sym("Ot6ClassChip"))
    for _, e in ipairs({ A, B }) do
      local a = 0x7e0000 + 0x3E38 + e
      emu.removeMemoryCallback(refs["sh" .. e], emu.callbackType.write, a, a)
    end
    refs = {}
  end
end

local function reset()
  dots, chips, classChips, shieldWrites = {}, {}, {}, {}
end

local function dump(tag, lim)
  lim = lim or 40
  H.log(string.format("== %s: %d Cmd_22, %d Ot6Chip, %d Ot6ClassChip, " ..
    "%d shield writes", tag, #dots, #chips, #classChips, #shieldWrites))
  local prev = nil
  for i, d in ipairs(dots) do
    if i <= lim then
      H.log(string.format("%s dot %2d f%-6d y=%02X $b6=%02X gap=%s hp=%d,%d",
        tag, i, d.frame, d.y, d.b6, prev and (d.frame - prev) or "-",
        d.hpA, d.hpB))
    end
    prev = d.frame
  end
  for i, c in ipairs(chips) do
    if i <= lim then H.log(tag .. " chip " .. i .. " " .. fmt(c)) end
  end
  for i, c in ipairs(classChips) do
    if i <= lim then H.log(tag .. " classchip " .. i .. " " .. fmt(c)) end
  end
  for i, w in ipairs(shieldWrites) do
    if i <= lim then
      H.log(string.format("%s shieldwrite %2d f%-6d e=%02X -> %d inDot=%s " ..
        "elem=%02X flags2=%02X", tag, i, w.frame, w.e, w.v, tostring(w.dot),
        w.elem, w.f2))
    end
  end
end

local function counters(tag)
  H.log(string.format("%s counters: A $3adc=%02X $3add=%02X $3af0=%02X " ..
    "$3aa0=%02X $3aa1=%02X | B $3adc=%02X $3add=%02X $3af0=%02X",
    tag, H.readByte(0x3ADC + A), H.readByte(0x3ADD + A),
    H.readByte(0x3AF0 + A), H.readByte(0x3AA0 + A), H.readByte(0x3AA1 + A),
    H.readByte(0x3ADC + B), H.readByte(0x3ADD + B), H.readByte(0x3AF0 + B)))
end

-- ------------------------------------------------------------------- lab --
local POISON = 0x04          -- $3ee4,y bit 2
local SEIZE  = 0x40          -- $3ee5,y bit 6

local function setupLab()
  keepAlive()
  -- guard A: poison-weak only, so nothing else can interfere
  H.writeByte(0x3BCC + A, 0x00)   -- absorbed elements
  H.writeByte(0x3BCD + A, 0x00)   -- nullified elements
  H.writeByte(0x3BE0 + A, 0x08)   -- weak: poison only
  H.writeByte(0x3BE1 + A, 0x00)   -- resisted elements
  H.writeByte(0x3E9C + A, 0x00)   -- class-weak: none
  H.writeByte(0x3E38 + A, 2)      -- shields
  H.writeByte(0x3E39 + A, 2)
  H.writeByte(0x3E88 + A, 0)      -- not broken
  H.writeByte(0x3E89 + A, 0)      -- nothing revealed
  H.writeByte(0x3E9D + A, 0)      -- no class revealed
  -- guard B: the negative control, fire-weak but poisoned as well
  H.writeByte(0x3BCC + B, 0x00)
  H.writeByte(0x3BCD + B, 0x00)
  H.writeByte(0x3BE0 + B, 0x01)   -- weak: fire only
  H.writeByte(0x3BE1 + B, 0x00)
  H.writeByte(0x3E9C + B, 0x00)
  H.writeByte(0x3E38 + B, 2)
  H.writeByte(0x3E39 + B, 2)
  H.writeByte(0x3E88 + B, 0)
  H.writeByte(0x3E89 + B, 0)
  H.writeByte(0x3E9D + B, 0)
  H.writeByte(0x3EC8, 0x00)       -- global element field ($3ec8, CalcTargetDmg)
  -- poison both guards
  H.writeByte(0x3EE4 + A, H.readByte(0x3EE4 + A) | POISON)
  H.writeByte(0x3EE4 + B, H.readByte(0x3EE4 + B) | POISON)
  -- party: Fight-only lists, no magitek, berserk, no weapon element
  for slot = 0, 3 do
    H.writeByte(0x202e + slot * 12, 0x00)
    H.writeByte(0x2031 + slot * 12, 0xff)
    H.writeByte(0x2034 + slot * 12, 0xff)
    H.writeByte(0x2037 + slot * 12, 0xff)
    local st1 = 0x3ee4 + slot * 2
    H.writeByte(st1, H.readByte(st1) & 0xf7)          -- clear magitek
    local st2 = 0x3ee5 + slot * 2
    H.writeByte(st2, H.readByte(st2) | 0x10)          -- berserk
    H.writeByte(0x3B90 + slot * 2, 0x00)              -- right-hand element
  end
  H.log(string.format(
    "lab: A(e%02X) weak=%02X cweak=%02X st1=%02X sh=%d | B(e%02X) weak=%02X " ..
    "cweak=%02X st1=%02X sh=%d | $3ec8=%02X",
    A, H.readByte(0x3BE0 + A), H.readByte(0x3E9C + A), H.readByte(0x3EE4 + A),
    shieldA(), B, H.readByte(0x3BE0 + B), H.readByte(0x3E9C + B),
    H.readByte(0x3EE4 + B), shieldB(), H.readByte(0x3EC8)))
  counters("seed")
end

local function repokePoison()
  keepAlive()
  -- keep both guards poisoned so the tick keeps arriving; shields are not
  -- re-poked, because their motion is the measurement
  H.writeByte(0x3EE4 + A, H.readByte(0x3EE4 + A) | POISON)
  H.writeByte(0x3EE4 + B, H.readByte(0x3EE4 + B) | POISON)
end

local phase1 = {}

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function() setupLab(); arm() end),

  -- Phase 1: the engine's own poison cadence
  H.repeatN(60, { H.call(repokePoison), H.waitFrames(30) }),
  H.call(function()
    dump("p1")
    counters("p1")
    H.log(string.format("p1 end: A shields=%d timer=%02X revealed=%02X | " ..
      "B shields=%d revealed=%02X", shieldA(), timerA(), revA(), shieldB(),
      revB()))
    phase1.dots, phase1.chips = #dots, #chips
    H.screenshot("dottick_p1")
  end),

  -- Phase 2: sap/seize, damage without an element
  H.call(function()
    reset()
    for _, e in ipairs({ A, B }) do
      H.writeByte(0x3EE4 + e, H.readByte(0x3EE4 + e) & (~POISON & 0xFF))
      H.writeByte(0x3EE5 + e, H.readByte(0x3EE5 + e) | SEIZE)
    end
    H.writeByte(0x3E38 + A, 2); H.writeByte(0x3E88 + A, 0)
    H.writeByte(0x3E38 + B, 2); H.writeByte(0x3E88 + B, 0)
    H.log(string.format("p2 (SAP/SEIZE): A st1=%02X st2=%02X sh=%d",
      H.readByte(0x3EE4 + A), H.readByte(0x3EE5 + A), shieldA()))
  end),
  H.repeatN(40, {
    H.call(function()
      keepAlive()
      for _, e in ipairs({ A, B }) do
        H.writeByte(0x3EE5 + e, H.readByte(0x3EE5 + e) | SEIZE)
      end
    end),
    H.waitFrames(30),
  }),
  H.call(function()
    dump("p2")
    H.log(string.format("p2 end: A shields=%d revealed=%02X | B shields=%d",
      shieldA(), revA(), shieldB()))
    H.screenshot("dottick_p2")
  end),

  -- Phase 3: the cap, ticks against a broken monster, then after recovery
  H.call(function()
    reset()
    for _, e in ipairs({ A, B }) do
      H.writeByte(0x3EE5 + e, H.readByte(0x3EE5 + e) & (~SEIZE & 0xFF))
      H.writeByte(0x3EE4 + e, H.readByte(0x3EE4 + e) | POISON)
      H.writeByte(0x3ADD + e, 0x80)   -- accelerate this entity's counter
    end
    H.writeByte(0x3E38 + A, 1)        -- one shield: the next tick breaks it
    H.writeByte(0x3E39 + A, 3)        -- and recovery restores three
    H.writeByte(0x3E88 + A, 0)
    H.log(string.format("p3 (CAP): A sh=%d/%d timer=%02X $3add=%02X",
      shieldA(), H.readByte(0x3E39 + A), timerA(), H.readByte(0x3ADD + A)))
  end),
  H.repeatN(120, { H.call(repokePoison), H.waitFrames(30) }),
  H.call(function()
    dump("p3", 80)
    counters("p3")
    H.log(string.format("p3 end: A shields=%d/%d timer=%02X revealed=%02X",
      shieldA(), H.readByte(0x3E39 + A), timerA(), revA()))
    disarm()
    H.screenshot("dottick_p3")
    -- guard against a vacuous pass: at least one tick must have happened
    H.assertEq(phase1.dots > 0, true, "phase 1 saw poison DOT actions")
  end),
})
