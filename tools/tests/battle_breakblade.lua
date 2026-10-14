-- @suite slow
-- battle_breakblade.lua -- the Break Blade's on-hit Break takes one shield,
-- whatever the swing's boost (#398, #424).
--
-- ot6_breakspell.asm: the Break Blade's random on-hit cast (CheckWeaponMagic,
-- one swing in four) is OT6's Break, not vanilla's petrify, and it takes 1
-- shield: the swing's boost bought swings, not the spell it throws
-- (Ot6BreakChips' OT6_WEAPSPELL bit 6 arm, owner ruling v0.21).  A boosted
-- Magic Break takes 1 + boost (battle_breakspell, battle_breakfour).
--
-- Played: Continue the wor-terra-v1 battery (TERRA wears the Break Blade
-- the route gave her; the save stands on the World of Ruin map by Mobliz),
-- pace two world tiles into a random battle, and TERRA Fights at 3 BP
-- through the real menu (H.kitBattle; Defends bank the points) at the
-- unbroken body with the most shields, two or more; everyone else Defends.
-- A battle that ends first, or fields no such body, is fought out and the
-- next taken.  Nothing is written.
--
-- Recorded at each pass of Ot6BreakSpell for TERRA's Break ($b6 = $0C):
-- the target, its shields, its Break, TERRA's pending boost
-- (OT6_BOOST_REVEALED) and OT6_WEAPSPELL; and every shield write made from
-- inside Ot6BreakSpell (the chips).  Asserted for every on-hit Break that
-- met a live, unbroken body holding two or more shields with 3 BP pending:
--   1. it is the weapon's cast (OT6_WEAPSPELL bit 6) inside a Fight ($3A7C
--      = 0);
--   2. exactly one chip, and the body's shields fell by exactly one;
--   3. the body was not petrified and kept its HP through the cast (OT6's
--      Break deals no damage and sets no status).
-- Precondition: at least one such cast, within FIGHTS boosted Fights.
-- Old-ROM red and mutants: build/attempts/wt/v031-cleanup/ (#424).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CMD_FIGHT, BREAK, BREAK_BLADE = 0x00, 0x00, 0x0C, 0x11
local WEAPSPELL = 0xED98 + 8           -- OT6_WEAPSPELL (ot6_memory.inc: OT6_HPMARK + 8)
local function shields(s) return H.readByte(0x3E40 + s * 2) end
local function broken(s) return H.readByte(0x3E90 + s * 2) ~= 0 end
local function hp(s) return H.readWord(0x3BFC + s * 2) end
local function present(s) return (H.readByte(0x3AA8 + s * 2) & 1) == 1 end

local seat, procs, cur, lastEnd = nil, {}, nil, -1
local BS = H.sym("Ot6BreakSpell")
local BS_END = H.sym("Ot6BreakChips")   -- the next proc in the segment
local function arm()
  local function close()
    if cur == nil then return end
    cur.sh1, cur.brk1, cur.hp1, cur.st1 = shields(cur.slot), broken(cur.slot), hp(cur.slot),
      H.readByte(0x3EEC + cur.slot * 2)
    procs[#procs + 1] = cur
    H.log(string.format("[bblade] f%d Break %d: slot %d shields %d -> %d (chips %d), broken %s -> %s, HP %d -> %d, "
      .. "status %02X -> %02X; TERRA's pending boost %d, command $%02X, OT6_WEAPSPELL $%02X", cur.f, #procs, cur.slot,
      cur.sh0, cur.sh1, cur.chips, tostring(cur.brk0), tostring(cur.brk1), cur.hp0, cur.hp1, cur.st0, cur.st1,
      cur.pend, cur.cmd, cur.ws))
    cur = nil
  end
  emu.addMemoryCallback(function()
    if seat == nil then return end
    local st = emu.getState()
    local x, y = st["cpu.x"] & 0xFF, st["cpu.y"] & 0xFF
    if H.readByte(0xB6) ~= BREAK or x ~= seat * 2 or y < 8 then return end
    close()
    local s = (y - 8) // 2
    cur = { slot = s, sh0 = shields(s), brk0 = broken(s), hp0 = hp(s), st0 = H.readByte(0x3EEC + s * 2),
      pend = H.readByte(0x3E9D + seat * 2), cmd = H.readByte(0x3A7C), ws = H.readByte(WEAPSPELL), chips = 0,
      f = H.frame }
  end, emu.callbackType.exec, BS, BS)
  emu.addMemoryCallback(function()
    if cur == nil then return end
    local st = emu.getState()
    local pc = (st["cpu.k"] << 16) | st["cpu.pc"]
    if pc >= BS and pc < BS_END then cur.chips = cur.chips + 1 end
  end, emu.callbackType.write, 0x7E3E40, 0x7E3E4B)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if seat ~= nil and (emu.getState()["cpu.x"] & 0xFF) == seat * 2 then close(); lastEnd = H.frame end
  end, emu.callbackType.exec, ae, ae)
end

-- the unbroken live body with the most shields, two or more
local function pickTarget()
  local best, bs = nil, 1
  for s = 0, 5 do
    if present(s) and hp(s) > 0 and (H.readByte(0x3EEC + s * 2) & 0xC2) == 0 and not broken(s)
        and shields(s) > bs then
      best, bs = s, shields(s)
    end
  end
  return best, bs
end

-- the world map's entrance tiles (ShortEntrancePtrs / LongEntrancePtrs,
-- route_data.py's reading): a pace must not step onto one (wor-terra-v1's
-- save stands beside Mobliz's door)
local function entranceSet(m)
  local set = {}
  -- (literal names: compose.py collects the H.sym strings it can see)
  for _, t in ipairs({ { H.sym("ShortEntrancePtrs"), 6, false }, { H.sym("LongEntrancePtrs"), 7, true } }) do
    local base = t[1] & 0x3FFFFF
    local function w(o) return H.readRomByte(base + o) | (H.readRomByte(base + o + 1) << 8) end
    for o = w(m * 2), w(m * 2 + 2) - 1, t[2] do
      local x, y = H.readRomByte(base + o), H.readRomByte(base + o + 1)
      local len = t[3] and (H.readRomByte(base + o + 2) & 0x7F) or 0
      local vert = t[3] and (H.readRomByte(base + o + 2) & 0x80) ~= 0
      for i = 0, len do set[(vert and x or x + i) .. "," .. (vert and y + i or y)] = true end
    end
  end
  return set
end

-- two world tiles, paced until a random battle loads
local function worldBattle(tag)
  local A, B
  return H.seqStep({
    H.waitUntil(function() return H.worldSettled() end, 3000, tag .. ": the world map, settled", 5),
    H.call(function()
      local x, y = H.worldX(), H.worldY()
      local doors = entranceSet(H.worldId())
      A, B = { x, y }, nil
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
        local bx, by = x + d[1], y + d[2]
        if B == nil and H.worldPassable(bx, by) and not doors[bx .. "," .. by] then B = { bx, by } end
      end
      H.assertEq(B ~= nil, true, string.format("%s: a passable world tile beside (%d,%d)", tag, x, y))
      H.log(string.format("[%s] pacing world (%d,%d) <-> (%d,%d)", tag, A[1], A[2], B[1], B[2]))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 4000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle on the world map"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
    H.waitFrames(30),
  })
end

-- FIGHTS: a 3-BP Fight swings four times (one + boost), each landing swing
-- casts the weapon's spell one time in four (CheckWeaponMagic: Rand < $40),
-- so a Fight with no Break is (3/4)^4 = 0.316; ten such Fights all miss
-- with 0.316^10 = 1e-5.  A swing that kills, or a battle that ends, costs a
-- few more; FIGHTS = 12.
local FIGHTS = 12
local fights, nCounted, mode, target = 0, 0, nil, nil
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function decide()
  seat, plan, mode, target = nil, {}, "fight", nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then seat = s end end
  H.assertEq(seat ~= nil, true, "TERRA is seated")
  local e = seat * 2
  if H.readWord(0x3BF4 + e) == 0 or (H.readByte(0x3EE4 + e) & 0xE2) ~= 0 then
    mode = "fightout"
    H.log(string.format("[bblade] TERRA cannot act here (status %02X): this battle is fought out",
      H.readByte(0x3EE4 + e)))
    return
  end
  local t, sh = pickTarget()
  if t == nil then
    mode = "fightout"
    H.log("[bblade] no live unbroken body with two or more shields: this battle is fought out")
    return
  end
  fights = fights + 1
  H.assertEq(fights <= FIGHTS, true, string.format("an on-hit Break on a two-shield body within %d Fights", FIGHTS))
  target = t
  H.log(string.format("[bblade] Fight %d: 3 BP at slot %d (%d shields); TERRA seat %d, bank %d", fights, t, sh, seat,
    H.readByte(0x3E9C + e)))
  plan = { { who = TERRA, cmd = CMD_FIGHT, boost = 3, slot = t } }
end

local function judge(n0)
  for i = n0 + 1, #procs do
    local p = procs[i]
    if p.sh0 >= 2 and not p.brk0 and p.hp0 > 0 and (p.st0 & 0xC2) == 0 and p.pend == 3 then
      H.assertEq(p.cmd, CMD_FIGHT, "the Break came inside TERRA's Fight")
      H.assertEq(p.ws & 0x40, 0x40, "it is the weapon's own cast (OT6_WEAPSPELL bit 6)")
      H.assertEq(p.chips, 1, string.format("the Break Blade's Break took one shield at 3 BP pending (chips: %d)",
        p.chips))
      H.assertEq(p.sh0 - p.sh1, 1, string.format("slot %d's shields fell by exactly one (%d -> %d)", p.slot, p.sh0,
        p.sh1))
      H.assertEq(p.st1 & 0x40, 0, string.format("slot %d was not petrified", p.slot))
      nCounted = nCounted + 1
    end
  end
end

local n0 = 0
H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("wor-terra-v1"),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * TERRA + 0x1F), BREAK_BLADE, "TERRA wears the Break Blade")
    arm()
  end),
  H.driveUntil(function() return nCounted >= 1 end, 500000, {
    H.cond(function() return not H.battleLoadStarted() end, { worldBattle("bblade") }, {}),
    H.call(function() n0 = #procs; decide() end),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
        planDone = function()
          local k = H.vars.kit[#H.vars.kit]
          return k ~= nil and lastEnd > k.frame and H.frame > lastEnd + 1
        end }),
      H.call(function() judge(n0) end),
    }),
  }, "an on-hit Break on a two-shield body"),
  H.call(function()
    H.log(string.format("[bblade] PASS: %d on-hit Break(s) at 3 BP pending each took exactly one shield (%d Break "
      .. "pass(es) seen, %d Fight(s))", nCounted, #procs, fights))
  end),
})
