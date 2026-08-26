-- @suite slow
-- battle_dotchip.lua -- a poison DOT tick chips a shield.
--
--   tools/tests/run.sh tools/tests/battle_dotchip.lua
--
-- Cmd_22, the DOT command, stores the poison element at $11a1 on the poison
-- branch of $b6, then tail-jumps into CalcTargetDmg's weak-element branch,
-- which chips via Ot6Chip when the target's weak-element byte ($3BE0,y)
-- matches $11a1.  OT6_ATKCLASS is 0 for a DOT record, so a tick chips
-- exactly one axis.  The seize/phantasm branch of Cmd_22 never reaches the
-- element store, so a sap tick lands damage with $11a1 = 0 and chips
-- nothing.
--
-- Lab: guard A (monster slot 2, entity $0c) is weak to poison only,
-- class-weak 0, 2 shields, poisoned.  Guard B (slot 3, entity $0e) is weak
-- to fire only, otherwise identical, and is the negative control: it must
-- never lose a shield.  The party runs Fight-only command lists plus
-- berserk, magitek status cleared, weapon elements zeroed, so no party
-- swing can chip either guard.
--
-- A recorded chip is matched to a DOT tick by frame (Cmd_22 tail-jumps its
-- damage resolution onto the same frame) and by the DOT record's signature
-- ($11a2 = $68, $11a6 = 2).

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local A, B = 0x0c, 0x0e            -- guards in monster slots 2/3
local POISON = 0x04                -- $3ee4,y bit 2 (battle_main.asm:15292)
local SEIZE  = 0x40                -- $3ee5,y bit 6 (battle_main.asm:15374)

local function shieldA() return H.readByte(0x3E38 + A) end
local function shieldB() return H.readByte(0x3E38 + B) end
local function timerA()  return H.readByte(0x3E88 + A) end
local function revA()    return H.readByte(0x3E89 + A) end

local ATB_FAST = 0x1000
local function keepAlive()
  H.writeWord(0x3C00, 5000)                 -- guards outlive the berserk party
  H.writeWord(0x3C02, 5000)
  for c = 0, 2 do                           -- and the party outlives the guards
    local a = 0x3BF4 + c * 2
    if H.readWord(a) > 0 and H.readWord(a) < 200 then H.writeWord(a, 400) end
  end
  for slot = 0, 3 do H.writeWord(0x3AC8 + slot * 2, ATB_FAST) end
end

-- ------------------------------------------------------------- recording --
local dotFrame, dotY = nil, nil
local function inDot() return dotFrame == H.frame end

local dots, chips, classChips, shieldWrites = {}, {}, {}, {}
local refs = {}

local function ctx()
  return {
    frame = H.frame,
    y = emu.getState()["cpu.y"] & 0xFF,
    e = H.readByte(0x11a1), f2 = H.readByte(0x11a2),
    pow = H.readByte(0x11a6), cls = H.readByte(0x57b8),
    sa = shieldA(), sb = shieldB(), ta = timerA(),
    dot = inDot(),
  }
end

local function fmt(c)
  return string.format(
    "f%-6d y=%02X elem=%02X flags2=%02X pow=%02X atkclass=%02X shields=%d,%d " ..
    "timerA=%02X inDot=%s",
    c.frame, c.y, c.e, c.f2, c.pow, c.cls, c.sa, c.sb, c.ta, tostring(c.dot))
end

local function arm()
  refs.cmd22 = emu.addMemoryCallback(function()
    dotFrame = H.frame
    dotY = emu.getState()["cpu.y"] & 0xFF
    dots[#dots + 1] = { frame = dotFrame, y = dotY, b6 = H.readByte(0xb6) }
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
      shieldWrites[#shieldWrites + 1] = { frame = H.frame, e = e, v = value,
                                          dot = inDot() }
    end, emu.callbackType.write, a, a)
  end
end

local function disarm()
  if not refs.cmd22 then return end
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

local function countDots(target)
  local n = 0
  for _, d in ipairs(dots) do if d.y == target then n = n + 1 end end
  return n
end

local function dump(tag)
  H.log(string.format("== %s: %d Cmd_22, %d Ot6Chip, %d Ot6ClassChip, " ..
    "%d shield writes", tag, #dots, #chips, #classChips, #shieldWrites))
  for i, d in ipairs(dots) do
    H.log(string.format("%s dot %2d f%-6d y=%02X $b6=%02X", tag, i, d.frame,
      d.y, d.b6))
  end
  for i, c in ipairs(chips) do H.log(tag .. " chip " .. i .. " " .. fmt(c)) end
  for i, w in ipairs(shieldWrites) do
    H.log(string.format("%s shieldwrite %2d f%-6d e=%02X -> %d inDot=%s",
      tag, i, w.frame, w.e, w.v, tostring(w.dot)))
  end
end

-- ------------------------------------------------------------------- lab --
local function setupLab()
  keepAlive()
  H.writeByte(0x3BCC + A, 0x00)   -- absorbed elements
  H.writeByte(0x3BCD + A, 0x00)   -- nullified elements
  H.writeByte(0x3BE0 + A, 0x08)   -- weak: poison only
  H.writeByte(0x3BE1 + A, 0x00)   -- resisted elements
  H.writeByte(0x3E9C + A, 0x00)   -- class-weak: none
  H.writeByte(0x3E38 + A, 2)
  H.writeByte(0x3E39 + A, 2)
  H.writeByte(0x3E88 + A, 0)
  H.writeByte(0x3E89 + A, 0)
  H.writeByte(0x3E9D + A, 0)
  H.writeByte(0x3BCC + B, 0x00)
  H.writeByte(0x3BCD + B, 0x00)
  H.writeByte(0x3BE0 + B, 0x01)   -- weak: fire only, the control
  H.writeByte(0x3BE1 + B, 0x00)
  H.writeByte(0x3E9C + B, 0x00)
  H.writeByte(0x3E38 + B, 2)
  H.writeByte(0x3E39 + B, 2)
  H.writeByte(0x3E88 + B, 0)
  H.writeByte(0x3E89 + B, 0)
  H.writeByte(0x3E9D + B, 0)
  H.writeByte(0x3EC8, 0x00)       -- global element field (CalcTargetDmg)
  H.writeByte(0x3EE4 + A, H.readByte(0x3EE4 + A) | POISON)
  H.writeByte(0x3EE4 + B, H.readByte(0x3EE4 + B) | POISON)
  for slot = 0, 3 do
    H.writeByte(0x202e + slot * 12, 0x00)   -- Fight-only command list
    H.writeByte(0x2031 + slot * 12, 0xff)
    H.writeByte(0x2034 + slot * 12, 0xff)
    H.writeByte(0x2037 + slot * 12, 0xff)
    local st1 = 0x3ee4 + slot * 2
    H.writeByte(st1, H.readByte(st1) & 0xf7) -- clear magitek (no Bio Blast)
    local st2 = 0x3ee5 + slot * 2
    H.writeByte(st2, H.readByte(st2) | 0x10) -- berserk
    H.writeByte(0x3B90 + slot * 2, 0x00)     -- right-hand element
  end
end

local function repokePoison()
  keepAlive()
  H.writeByte(0x3EE4 + A, H.readByte(0x3EE4 + A) | POISON)
  H.writeByte(0x3EE4 + B, H.readByte(0x3EE4 + B) | POISON)
  -- shields are not re-poked: their motion is the measurement
end

local broke = { seen = false, timer = 0 }
local function watchBreak()
  if not broke.seen and shieldA() == 0 and timerA() ~= 0 then
    broke.seen, broke.timer = true, timerA()
  end
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    setupLab()
    arm()
    -- 1. the seed itself, before a single tick
    H.assertEq(H.readByte(0x3BE0 + A), 0x08, "A weak elements = poison only")
    H.assertEq(H.readByte(0x3E9C + A), 0x00, "A class-weak = none")
    H.assertEq(shieldA(), 2, "A seeds 2 shields")
    H.assertEq(H.readByte(0x3EE4 + A) & POISON, POISON, "A is poisoned")
    H.assertEq(H.readByte(0x3EE4 + B) & POISON, POISON, "B is poisoned too")
    H.assertEq(H.readByte(0x3BE0 + B), 0x01, "B weak elements = fire only")
  end),

  -- Drive until A breaks from poison ticks alone, or bail after four ticks.
  H.driveUntil(function()
    watchBreak()
    return broke.seen or countDots(A) >= 4
  end, 8000, {
    H.call(repokePoison), H.waitFrames(15),
  }, "A broken by poison ticks"),
  H.waitFrames(30),

  H.call(function()
    dump("poison")
    H.log(string.format("poison end: A shields=%d timer=%02X revealed=%02X | " ..
      "B shields=%d", shieldA(), timerA(), revA(), shieldB()))
    H.screenshot("dotchip_poison")

    -- 2. ticks arrived
    local nA, nB = countDots(A), countDots(B)
    H.log(string.format("poison ticks: A=%d B=%d", nA, nB))
    H.assertEq(nA >= 2, true, "at least two poison ticks landed on A")
    H.assertEq(nB >= 1, true, "at least one poison tick landed on B (control)")

    -- 3. A's shields walked down inside ticks, and nothing else's moved.
    local seq = {}
    for _, w in ipairs(shieldWrites) do
      H.assertEq(w.e, A, "only A's shield byte moved")
      H.assertEq(w.dot, true, "shield write at f" .. w.frame .. " was in a tick")
      seq[#seq + 1] = w.v
    end
    H.assertEq(table.concat(seq, ","), "1,0", "A's shields walked 2 -> 1 -> 0")

    -- 4. and the emptying tick broke it
    H.assertEq(broke.seen, true, "A broke on poison ticks alone")
    H.assertEq(broke.timer ~= 0, true, "the break timer armed (" ..
      string.format("%02X", broke.timer) .. ")")

    -- 5. the tick taught the weakness as well as chipping it
    H.assertEq(revA() & 0x08, 0x08, "A's poison weakness is revealed")

    -- 6. every chip that ran was a DOT tick on A.
    H.assertEq(#chips >= 2, true, "at least two chips ran")
    for i, c in ipairs(chips) do
      H.assertEq(c.dot, true, "chip " .. i .. " ran inside a Cmd_22 tick")
      H.assertEq(c.e & 0x08, 0x08, "chip " .. i .. " carried the poison element")
      H.assertEq(c.f2, 0x68, "chip " .. i .. " carried the DOT record's flags2")
      H.assertEq(c.pow, 0x02, "chip " .. i .. " carried the DOT record's power")
      H.assertEq(c.y, A, "chip " .. i .. " targeted A")
      -- 7. one axis only: the DOT record carries no attack class
      H.assertEq(c.cls, 0x00, "chip " .. i .. " carried no attack class")
    end

    -- 8. the control: B held both shields, but its ticks did land
    H.assertEq(shieldB(), 2, "B (poisoned, not poison-weak) kept both shields")
    local bJoin = 0
    for _, c in ipairs(classChips) do
      if c.dot and c.y == B and (c.e & 0x08) == 0x08 then bJoin = bJoin + 1 end
    end
    H.log("B ticks that reached the damage join: " .. bJoin)
    H.assertEq(bJoin >= 1, true,
      "B's ticks reached the damage join carrying poison (so the negative " ..
      "is an unmatched weakness, not a missing hit)")
  end),

  -- sap/seize: damage with no element must chip nothing
  H.call(function()
    dots, chips, classChips, shieldWrites = {}, {}, {}, {}
    for _, e in ipairs({ A, B }) do
      H.writeByte(0x3EE4 + e, H.readByte(0x3EE4 + e) & (~POISON & 0xFF))
      H.writeByte(0x3EE5 + e, H.readByte(0x3EE5 + e) | SEIZE)
    end
    H.writeByte(0x3E38 + A, 2); H.writeByte(0x3E88 + A, 0)
    H.writeByte(0x3E38 + B, 2); H.writeByte(0x3E88 + B, 0)
  end),
  H.driveUntil(function() return #dots >= 2 end, 6000, {
    H.call(function()
      keepAlive()
      for _, e in ipairs({ A, B }) do
        H.writeByte(0x3EE5 + e, H.readByte(0x3EE5 + e) | SEIZE)
      end
    end),
    H.waitFrames(15),
  }, "two sap/seize ticks"),
  H.waitFrames(30),

  H.call(function()
    dump("sap")
    H.screenshot("dotchip_sap")
    -- 9. sap ticks land damage with no element, so they chip nothing
    H.assertEq(#dots >= 2, true, "at least two sap/seize ticks landed")
    for i, d in ipairs(dots) do
      H.assertEq(d.b6, SEIZE, "sap tick " .. i .. " took the seize branch")
    end
    H.assertEq(#chips, 0, "no sap tick reached Ot6Chip")
    H.assertEq(#shieldWrites, 0, "no shield moved on a sap tick")
    local join = 0
    for _, c in ipairs(classChips) do
      if c.dot and c.f2 == 0x68 and c.e == 0x00 then join = join + 1 end
    end
    H.log("sap ticks that reached the damage join: " .. join)
    H.assertEq(join >= 2, true,
      "sap ticks reached the damage join carrying NO element (so 'no chip' " ..
      "is the element gate, not a missing hit)")
    H.assertEq(shieldA(), 2, "A kept both shields through the sap ticks")
    disarm()
  end),
})
