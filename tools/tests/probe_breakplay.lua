-- probe_breakplay.lua -- issue #63: WHICH condition suppresses #48's break
-- flash in real play?  battle_breakflash is green and the owner sees nothing.
--
-- The instrument: exec callbacks on every gate inside Ot6BreakStart, so each
-- invocation reports exactly how far it got.  Addresses are derived from the
-- proc's own symbol plus verified opcode offsets, so a rebuild cannot silently
-- point them at the wrong instruction.
--
--   B+$00  entry                 (lda #$00)
--   B+$0B  passed slot-present   (lda $3eec,y)
--   B+$12  passed wound/petrify  (lda $3bfc,y)
--   B+$1A  passed HP-nonzero     (lda $80db,y)
--   B+$23  ARMED                 (sta OT6_BRKPAL,y)
--   B+$33  refused               (clc)
--
-- battle_breakflash's pinLab() does TWO things, and each of them pins away one
-- of the candidate suppressors: it holds monster HP at 6000 (so a break can
-- never coincide with a kill) and it latches vanilla's per-monster turn-flash
-- byte (so the engine never owns obj palette 3).  This probe runs the same
-- doorstep laboratory as three cells that turn those pins off one at a time.
--
--   cell 1  hp survivable, turn-flash latch NOT pinned  -> palette contention?
--   cell 2  hp survivable, turn-flash latch pinned      -> positive control
--   cell 3  hp low enough that the 4x breaking hit KILLS -> the HP-zero refusal
--
-- The doorstep guards' REAL hp is $28 = 40, so the very first fire chip kills
-- them and no break happens at all: hp has to be raised for a break to exist
-- to observe.  That is stated, not hidden -- the pin under test is not "hp is
-- raised" but "hp is held above zero across the numeral frame".

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local BRKTICK  = 0xED76
local BRKLIVE  = 0xED75
local BROKEN   = 0x3E90        -- OT6_BROKEN_TICKS, monster half
local SHIELD   = 0x3E40        -- OT6_SHIELD_CUR, monster half
local MONHP    = 0x3BFC
local MONMAX   = 0x3C24
local SPRDATA  = 0x80DB
local MONFLASH = 0x618B
local G = { [1] = 4, [2] = 6 }

local Y_KEY
local function resolveY()
  local s = emu.getState()
  for _, c in ipairs({ "cpu.y", "cpu.Y" }) do if s[c] ~= nil then Y_KEY = c end end
  H.assertEq(Y_KEY ~= nil, true, "Mesen exposes CPU Y")
end
local function cpuY() return emu.getState()[Y_KEY] end

-- ------------------------------------------------------------- instrument --
local STAGES = {
  { off = 0x00, op = 0xA9, name = "entry" },
  { off = 0x0B, op = 0xB9, name = "present-ok" },
  { off = 0x12, op = 0xB9, name = "alive-ok" },
  { off = 0x1A, op = 0xB9, name = "hp-ok" },
  { off = 0x23, op = 0x99, name = "ARMED" },
  { off = 0x33, op = 0x18, name = "refused" },
}
local trace, cur = {}, nil
local armEnters = 0
local pendSeen = {}
local sfx = {}
local whiteF = { [1] = 0, [2] = 0 }
local watch = false

local function install()
  local B = H.sym("Ot6BreakStart")
  local A = H.sym("Ot6BreakArm")
  for _, s in ipairs(STAGES) do
    H.assertEq(H.readRomByte((B + s.off) & 0x3FFFFF), s.op,
      string.format("Ot6BreakStart+$%02X is the %s instruction", s.off, s.name))
  end
  H.log(string.format("Ot6BreakArm=$%06X Ot6BreakStart=$%06X", A, B))
  emu.addMemoryCallback(function()
    if watch then armEnters = armEnters + 1 end
  end, emu.callbackType.exec, A, A)
  for _, s in ipairs(STAGES) do
    local a, name = B + s.off, s.name
    emu.addMemoryCallback(function()
      if not watch then return end
      if name == "entry" then
        local y = cpuY()
        cur = { f = H.frame, y = y, stage = "entry",
                hp = H.readWord(MONHP + y), pres = H.readByte(0x3AA8 + y),
                st1 = H.readByte(0x3EEC + y), spr = H.readByte(SPRDATA + y),
                brk = H.readByte(BROKEN + y) }
        trace[#trace + 1] = cur
      elseif cur then
        cur.stage = name
      end
    end, emu.callbackType.exec, a, a)
  end
  emu.addMemoryCallback(function(_, v)
    if not watch or v == 0 then return end
    sfx[#sfx + 1] = { f = H.frame, id = H.readByte(0xE9E9),
                      pan = H.readByte(0xE9EA) }
  end, emu.callbackType.write, 0x7EE9EC, 0x7EE9EC)
end

local function sample()
  if not watch then return end
  for g = 1, 2 do
    if H.readByte(BRKTICK + G[g]) == 0xFF and not pendSeen[g] then
      pendSeen[g] = H.frame
    end
    if (H.readByte(SPRDATA + G[g]) & 0x0E) == 0x06 then
      whiteF[g] = whiteF[g] + 1
    end
  end
end

local function armed()
  for _, r in ipairs(trace) do if r.stage == "ARMED" then return true end end
  return false
end

local function dump(tag)
  H.log(string.format("==== %s", tag))
  H.log(string.format("  Ot6BreakArm ran %d times; Ot6BreakStart %d times",
    armEnters, #trace))
  H.log(string.format("  pending ($FF) first seen: g1=%s g2=%s",
    tostring(pendSeen[1]), tostring(pendSeen[2])))
  local counts = {}
  for _, r in ipairs(trace) do
    counts[r.stage] = (counts[r.stage] or 0) + 1
    H.log(string.format("  f%-6d slot+%d stage=%-11s hp=%04X pres=%02X "
      .. "st1=%02X spr=%02X(pal %d) brokenTimer=%02X",
      r.f, r.y, r.stage, r.hp, r.pres, r.st1, r.spr, (r.spr & 0x0E) >> 1, r.brk))
  end
  local parts = {}
  for k, v in pairs(counts) do parts[#parts + 1] = k .. "=" .. v end
  table.sort(parts)
  H.log("  stage histogram: " .. table.concat(parts, " "))
  H.log(string.format("  palette-3 frames observed: g1=%d g2=%d; cleaves=%d",
    whiteF[1], whiteF[2], #sfx))
  for i, s in ipairs(sfx) do
    H.log(string.format("  sfx #%d f%d id=%02X pan=%02X", i, s.f, s.id, s.pan))
  end
end

local function reset()
  trace, cur, armEnters, pendSeen, sfx = {}, nil, 0, {}, {}
  whiteF = { [1] = 0, [2] = 0 }
end

-- put both guards back on the field with a full gauge and the given hp
local function rearm(hp)
  for g = 1, 2 do
    H.writeByte(0x3AA8 + G[g], H.readByte(0x3AA8 + G[g]) | 1)
    H.writeByte(0x3EEC + G[g], 0)
    H.writeByte(BROKEN + G[g], 0)
    H.writeByte(BRKTICK + G[g], 0)
    H.writeByte(SHIELD + G[g], 2)
    H.writeWord(MONHP + G[g], hp)
    H.writeWord(MONMAX + G[g], hp)
  end
end

local function mash()
  return {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }
end

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),

  H.call(function()
    resolveY()
    install()
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
    H.writeByte(0x3BEC, H.readByte(0x3BEC) | 0x01)   -- fire-weak
    H.writeByte(0x3BEE, H.readByte(0x3BEE) | 0x01)
    for c = 0, 2 do
      H.writeByte(0x3B18 + c * 2, 5)
      H.writeByte(0x3B41 + c * 2, 10)
    end
    H.log(string.format("REAL guard hp is %04X/%04X (a fire chip one-shots "
      .. "them, so no break can happen unpinned at all)",
      H.readWord(MONHP + G[1]), H.readWord(MONHP + G[2])))
    rearm(6000)
    H.log(string.format("cell 1: hp 6000, turn-flash latch %02X/%02X LEFT ALONE",
      H.readByte(MONFLASH + 2), H.readByte(MONFLASH + 3)))
    watch = true
  end),

  -- ---------- cell 1: survivable break, vanilla turn-flash latch UNPINNED
  H.driveUntil(function()
    for g = 1, 2 do
      if H.readWord(MONHP + G[g]) < 2500 then H.writeWord(MONHP + G[g], 6000) end
    end
    return #trace > 0
  end, 20000, mash(), "a break with hp survivable and the palette unpinned"),
  H.waitFrames(60),
  H.release(),
  H.call(function()
    watch = false
    dump("CELL 1 -- hp survivable, vanilla turn-flash latch NOT pinned")
    H.vars.cell1 = armed()
  end),

  -- ---------- cell 2: the test's exact configuration, as a positive control
  H.call(function()
    reset()
    rearm(6000)
    for g = 1, 2 do H.writeByte(MONFLASH + (G[g] >> 1), 1) end
    H.log("cell 2: hp 6000 AND the turn-flash latch pinned (the test's config)")
    watch = true
  end),
  H.driveUntil(function()
    for g = 1, 2 do
      if H.readWord(MONHP + G[g]) < 2500 then H.writeWord(MONHP + G[g], 6000) end
      H.writeByte(MONFLASH + (G[g] >> 1), 1)
    end
    return #trace > 0
  end, 20000, mash(), "a break in the test's own configuration"),
  H.waitFrames(60),
  H.release(),
  H.call(function()
    watch = false
    dump("CELL 2 -- the test's configuration (positive control)")
    H.vars.cell2 = armed()
  end),

  -- ---------- cell 3: the break lands as the killing blow (hp NOT held up)
  H.call(function()
    reset()
    -- 450 hp: the first chip (weak x2 then shielded x0.5 ~= 1x base) leaves
    -- it alive, the breaking chip (weak x2 AND broken x2 = 4x) kills it.
    rearm(450)
    H.log("cell 3: hp 450 -- the 4x breaking hit is lethal, hp NOT held up")
    watch = true
  end),
  H.driveUntil(function()
    return #trace > 0
  end, 20000, mash(), "a break that also kills"),
  H.waitFrames(60),
  H.release(),
  H.call(function()
    watch = false
    dump("CELL 3 -- the breaking hit also killed (hp unpinned)")
    H.log(string.format("verdict: cell1 armed=%s cell2 armed=%s cell3 armed=%s",
      tostring(H.vars.cell1), tostring(H.vars.cell2), tostring(armed())))
  end),

  H.logStep(function() return "probe_breakplay complete" end),
})
