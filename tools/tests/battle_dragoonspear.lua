-- @suite savestate=wor_leo slow
-- battle_dragoonspear.lua -- a spear the Dragoon Boots lend swings, and chips, as a spear (#567).
--
-- Played from wor_leo (the World of Ruin's map beside Thamasa): STRAGO, who cannot hold a spear by his own
-- equip bit, puts on the bag's Dragoon Boots through the Relic menu and takes the bag's strongest spear through
-- the Equip menu (equipLoadout, a no-op when the Relic menu's re-equip already gave it to him).  Then two world
-- tiles are paced into a random battle, and in each battle:
--   1. his command row 0 is Jump (the boots' Fight -> Jump, vanilla);
--   2. the battle inventory's equippability ($2686, five bytes an item, +4: bit n set = seat n cannot equip,
--      LoadItemProp, the Ot6EquipWord site) lets his seat take the bag's other spear and refuses it to a seat
--      without the boots and without a spear bit of its own (TERRA);
--   3. if a live, unbroken body holds a shield and a pierce class weakness ($3E9C+e & OT6_PIERCE), he Jumps at it
--      through the real menu (H.kitBattle; the others Defend).  His landing swing loads OT6_ATKCLASS from
--      Ot6WeapClassTbl for the spear in his hand ($3CA8+seat*2) and that class is pierce ($02) and only
--      pierce; vanilla's spear bonus runs (SpearEffect with the spear in A takes its `sta $bd` of 2); and the
--      body's shields fall when the swing lands.  A battle with no such body is fought out and the next taken.
-- PACE_BURN = K (a lab's global) fights out K battles before the measured one.  Nothing is written.
local H = dofile("tools/tests/lib/ot6.lua")

local STRAGO, TERRA, BOOTS = 7, 0, 0xBF
local REC = 0x1600 + 37 * STRAGO
local CMD_JUMP = 0x16
local OT6_PIERCE = 0x02                       -- ot6_class.asm
local ATKCLASS = 0x7E57B8                     -- OT6_ATKCLASS (ot6_memory.inc)
local function isSpear(id) return id ~= nil and id >= 0x1D and id <= 0x24 end
local function itemProp(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function baseWord(id) return itemProp(id, 1) | (itemProp(id, 2) << 8) end
local function pos(c)
  local b = H.readByte(0x1850 + c)
  if (b & 7) ~= H.activeParty() then return nil end
  return (b >> 3) & 3
end
local function shields(m) return H.readByte(0x3E40 + m * 2) end
local function broken(m) return H.readByte(0x3E90 + m * 2) ~= 0 end
local function mhp(m) return H.readWord(0x3BFC + m * 2) end
local function present(m) return (H.readByte(0x3AA8 + m * 2) & 1) == 1 end
local function clsweak(m) return H.readByte(0x3EA4 + m * 2) end
local function seatOf(actor) for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == actor then return s end end end

local SPEAR, OTHER = nil, nil
local seat = nil
local swings, bonus, landed = {}, {}, nil
local armed = false
local function arm()
  if armed then return end
  armed = true
  local swinger = nil
  emu.addMemoryCallback(function()
    swinger = emu.getState()["cpu.x"] & 0xFF
  end, emu.callbackType.exec, H.sym("Ot6WeaponClass"), H.sym("Ot6WeaponClass"))
  emu.addMemoryCallback(function(_, v)
    if swinger ~= nil and seat ~= nil and (swinger >> 1) == seat then
      local item = H.readByte(0x3CA8 + swinger)
      swings[#swings + 1] = { f = H.frame, item = item, class = v }
      if landed == nil then landed = H.frame end
      H.log(string.format("[spear] f%d STRAGO's swing: hand item $%02X, OT6_ATKCLASS $%02X", H.frame, item, v))
    end
    swinger = nil
  end, emu.callbackType.write, ATKCLASS, ATKCLASS)
  local se = H.sym("SpearEffect")
  emu.addMemoryCallback(function()
    bonus[#bonus + 1] = { f = H.frame, item = emu.getState()["cpu.a"] & 0xFF, taken = false }
  end, emu.callbackType.exec, se, se)
  -- SpearEffect: cmp #$1d / bcc / cmp #$25 / bcs / lda #$02 / sta $bd -- the store at +10
  emu.addMemoryCallback(function()
    if #bonus > 0 then bonus[#bonus].taken = true end
  end, emu.callbackType.exec, se + 10, se + 10)
end

-- the world map's entrance tiles, which a pace must not step onto (battle_breakblade's reading)
local function entranceSet(m)
  local set = {}
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

-- the battle inventory's equippability byte for an item, or nil when the battle bag lacks it
local function battleEquipBits(id)
  for i = 0, 251 do
    if H.readByte(0x2686 + i * 5) == id then return H.readByte(0x2686 + i * 5 + 4) end
  end
end

local JUMPS = 8
-- PACE_BURN (a global a lab sets ahead of the lib; 0 in the suite): fight out that many battles first, to vary
-- the encounter history the measured Jump comes from (TESTING.md: the draw moves with encounters used up)
local BURN = type(PACE_BURN) == "number" and PACE_BURN or 0
local jumps, counted, mode, target, pre = 0, 0, nil, nil, nil
local battles, invChecked = 0, 0
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function decide()
  plan, mode, target, pre = {}, "fight", nil, nil
  battles = battles + 1
  seat = seatOf(STRAGO)
  H.assertEq(seat ~= nil, true, "STRAGO is seated")
  -- 1. the boots' Jump
  H.assertEq(H.readByte(0x202E + seat * 12), CMD_JUMP, "STRAGO's command row 0 is Jump (the Dragoon Boots)")
  -- 2. the battle inventory agrees with the Equip menu
  local bits = battleEquipBits(OTHER)
  local ts = seatOf(TERRA)
  if bits ~= nil and ts ~= nil then
    H.log(string.format("[spear] battle %d: the battle bag's $%02X equippability $%02X (bit = a seat that cannot); "
      .. "STRAGO seat %d, TERRA seat %d", battles, OTHER, bits, seat, ts))
    H.assertEq((bits >> seat) & 1, 0, string.format("the battle bag lets STRAGO's seat take $%02X", OTHER))
    H.assertEq((bits >> ts) & 1, 1, string.format("and refuses it to TERRA's, who wears no boots", OTHER))
    invChecked = invChecked + 1
  end
  local e = seat * 2
  if battles <= BURN then
    mode = "fightout"
    H.log(string.format("[spear] battle %d of the %d PACE_BURN fights out", battles, BURN))
    return
  end
  if H.readWord(0x3BF4 + e) == 0 or (H.readByte(0x3EE4 + e) & 0xE2) ~= 0 then
    mode = "fightout"
    H.log(string.format("[spear] STRAGO cannot act here (status %02X): fought out", H.readByte(0x3EE4 + e)))
    return
  end
  for m = 0, 5 do
    if target == nil and present(m) and mhp(m) > 0 and (H.readByte(0x3EEC + m * 2) & 0xC2) == 0 and not broken(m)
        and shields(m) > 0 and (clsweak(m) & OT6_PIERCE) ~= 0 then
      target = m
    end
  end
  if target == nil then
    mode = "fightout"
    H.log("[spear] no live unbroken pierce-weak body with a shield: this battle is fought out")
    return
  end
  jumps = jumps + 1
  H.assertEq(jumps <= JUMPS, true, string.format("a landed Jump on a pierce-weak body within %d Jumps", JUMPS))
  pre = { sh = shields(target), hp = mhp(target), nswing = #swings, nbonus = #bonus }
  swings, bonus, landed = {}, {}, nil
  pre.nswing, pre.nbonus = 0, 0
  H.log(string.format("[spear] battle %d: Jump %d at slot %d (%d shields, class weak $%02X, HP %d)", battles, jumps,
    target, pre.sh, clsweak(target), pre.hp))
  plan = { { who = STRAGO, cmd = CMD_JUMP, boost = 0, slot = target } }
end

local function judge()
  if pre == nil then return end
  H.log(string.format("[spear] after the Jump: slot %d shields %d -> %d, HP %d -> %d; swings %d, SpearEffect %d",
    target, pre.sh, shields(target), pre.hp, mhp(target), #swings, #bonus))
  if #swings == 0 then
    H.log("[spear] the Jump did not land (no swing loaded a class): not counted")
    return
  end
  for _, s in ipairs(swings) do
    H.assertEq(s.item, SPEAR, string.format("the swing is the spear in his hand ($%02X)", SPEAR))
    H.assertEq(s.class, OT6_PIERCE, "the spear's swing loads the pierce class and only pierce")
  end
  H.assertEq(#bonus > 0, true, "the Jump ran vanilla's SpearEffect")
  H.assertEq(bonus[1].item, SPEAR, string.format("SpearEffect saw the spear ($%02X)", SPEAR))
  H.assertEq(bonus[1].taken, true, "and took the spear's damage multiplier ($bd = 2)")
  if mhp(target) < pre.hp then
    H.assertEq(shields(target) < pre.sh or broken(target), true,
      string.format("the landed spear chipped the pierce-weak body's shields (%d -> %d)", pre.sh, shields(target)))
    counted = counted + 1
  else
    H.log("[spear] the landing dealt no damage (a miss): not counted")
  end
end

H.run({ maxFrames = 500000 }, {
  H.loadState("build/states/wor_leo.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(pos(STRAGO) ~= nil and pos(TERRA) ~= nil, true,
      "precondition: STRAGO and TERRA in the active party (gen_wor_leo seats them)")
    H.assertEq(H.invCountOf(BOOTS) > 0, true,
      "precondition: the Dragoon Boots in the bag (the Magitek factory's chest, gen_mrf_kefka)")
    H.assertEq(H.readByte(REC + 0x23), 0xFF, "precondition: STRAGO's first relic slot is empty (the boots' slot)")
    local sp = {}
    for slot = 0, 255 do
      local id = H.readByte(0x1869 + slot)
      if isSpear(id) and id ~= 0x24 and H.readByte(0x1969 + slot) > 0 and ((baseWord(id) >> STRAGO) & 1) == 0
          and ((baseWord(id) >> TERRA) & 1) == 0 then
        sp[#sp + 1] = id
      end
    end
    table.sort(sp, function(a, b) return itemProp(a, 20) > itemProp(b, 20) end)
    H.assertEq(#sp >= 2, true, "precondition: two kinds of spear neither STRAGO nor TERRA holds by own bit, in the bag")
    SPEAR, OTHER = sp[1], sp[2]
    H.log(string.format("[spear] STRAGO takes $%02X; the battle bag's check is on $%02X", SPEAR, OTHER))
  end),
  H.equipWeapon(function() return pos(STRAGO) end, BOOTS, { slot = 4, tag = "the Dragoon Boots on STRAGO" }),
  H.lazy(function() return H.equipLoadout(STRAGO, { { 0, SPEAR } }, { tag = "STRAGO takes the spear" }) end),
  H.call(function()
    H.assertEq(H.readByte(REC + 0x23), BOOTS, "STRAGO wears the Dragoon Boots")
    H.assertEq(H.readByte(REC + 0x1F), SPEAR, string.format("STRAGO holds $%02X", SPEAR))
    H.assertEq(H.invCountOf(OTHER) > 0, true, string.format("$%02X stays in the bag", OTHER))
    arm()
  end),
  H.driveUntil(function() return counted >= 1 end, 480000, {
    H.cond(function() return not H.battleLoadStarted() end, { worldBattle("spear") }, {}),
    H.call(function() decide() end),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
        planDone = function() return landed ~= nil and H.frame > landed + 120 end }),
      H.call(function() judge() end),
    }),
  }, "a landed spear Jump on a pierce-weak body"),
  H.call(function()
    H.assertEq(invChecked > 0, true, "the battle bag's equippability was checked in a battle")
    H.log(string.format("[spear] PASS: %d landed spear Jump(s) chipped as pierce over %d battle(s); the battle bag "
      .. "agreed in %d", counted, battles, invChecked))
  end),
})
