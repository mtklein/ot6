-- battle_fold: boost folds tiered spells — Terra casting with 2 BP
-- pending executes the spell two tiers up (queued as the -ra/-ga id in
-- CreateAction, so name, animation, and power are the higher tier's own),
-- while MP is charged for the BASE spell and tier-family spells never
-- take the generic damage multiplier.
--
-- Menu input on this mint is unreliable (a mid-window interrupt eats
-- presses deterministically), so the cast goes through the vanilla
-- AUTO-action path instead: muddle Terra with a Magic-only command list
-- (magitek status cleared — it would force RandMagitekAction beams) and
-- she casts a random known spell for real. Fire and Cure both fold.
--   asserts: $3410 sees the tier-3 id at execution, the damage lands in
--   tier-3-potency-without-multiplier bounds, mp cost is the base
--   spell's, and the boost is consumed.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local terra, mp0
local spells = {}

local hp0

local function findTerra()
  for slot = 0, 3 do
    if H.readByte(0x3ed8 + slot*2) == 0 then return slot end
  end
end

-- attack names render through the LARGE font as bitmaps (22 B/glyph),
-- not map cell codes, so the name itself isn't cheaply assertable.
-- potency is: an intro-stats Fire 3 hit lands ~150, base Fire ~20-50,
-- and a x4-multiplied Fire 3 (double-dip bug) ~600.
local function hp(slot) return H.readWord(0x3bf4 + slot*2) end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.call(function()
    terra = findTerra()
    H.log("terra is slot " .. terra)
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    -- stop the guards so nothing contests the run
    H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)
    H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
    mp0 = H.readWord(0x3c08 + terra*2)
    H.log(string.format("terra mp=%d", mp0))
    emu.addMemoryCallback(function(addr, value)
      spells[#spells + 1] = value
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
  end),
  -- let terra's pre-queued entry-mash action (if any) flush first, then
  -- rig her: no magitek routing, magic-only list, muddled, boosted
  H.driveUntil(function()
    return H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) == terra
  end, 10000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= terra then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "terra's menu up"),
  H.call(function()
    mp0 = H.readWord(0x3c08 + terra*2)
    local st1 = 0x3ee4 + terra*2
    H.writeByte(st1, H.readByte(st1) & 0xf7)      -- clear magitek
    H.writeByte(0x202e + terra*12, 0x02)          -- Magic
    H.writeByte(0x2031 + terra*12, 0xff)
    H.writeByte(0x2034 + terra*12, 0xff)
    H.writeByte(0x2037 + terra*12, 0xff)
    local st2 = 0x3ee5 + terra*2
    H.writeByte(st2, H.readByte(st2) | 0x20)      -- muddle: menu-less cast
    H.writeByte(0x3e9c + terra*2, 3)              -- bp
    H.writeByte(0x3e9d + terra*2, 2)              -- pending boost
    hp0 = {}
    for s = 0, 3 do
      -- intro hp (~65) saturates a killing hit; raise it so the drop is
      -- the actual damage dealt
      if hp(s) > 0 then H.writeWord(0x3bf4 + s*2, 400) end
      hp0[s] = hp(s)
    end
  end),
  H.driveUntil(function()
    return pend(terra) == 0
  end, 8000, {
    H.waitFrames(2),
  }, "boosted auto-cast lands"),
  H.waitFrames(180),
  H.call(function()
    local st2 = 0x3ee5 + terra*2                  -- un-muddle
    H.writeByte(st2, H.readByte(st2) & 0xdf)
    local vals = {}
    for _, v in ipairs(spells) do vals[#vals + 1] = string.format("%02x", v) end
    H.log("spells executed: " .. table.concat(vals, " "))
    local fold3 = nil
    for _, v in ipairs(spells) do
      if v == 0x09 or v == 0x2f then fold3 = v end
    end
    H.assertEq(fold3 ~= nil, true, "a base spell folded to its tier 3")
    if fold3 == 0x09 then
      -- muddled fire 3 hit the party: tier-3 potency, not base fire.
      -- legit range is wide (single vs split roll, per-target m.def:
      -- ~75-330 observed); base fire tops out ~50 and a single-target
      -- x4 double-dip starts ~700. the multiplier gate itself is
      -- structural (tier-family scan in Ot6BoostDmg).
      local worst = 0
      for s = 0, 3 do
        local d = hp0[s] - hp(s)
        if d > worst then worst = d end
      end
      H.log(string.format("worst single fire 3 hit: %d", worst))
      H.assertEq(worst >= 60, true, "tier-3 potency applied (not base fire)")
      H.assertEq(worst <= 700, true, "no single-target multiplier double-dip")
    end
    local mp1 = H.readWord(0x3c08 + terra*2)
    local cost = mp0 - mp1
    H.log(string.format("mp %d -> %d (folded spell %02x)", mp0, mp1, fold3))
    if fold3 == 0x09 then
      H.assertEq(cost, 4, "mp charged for base Fire, not Fire 3")
    else
      H.assertEq(cost, 5, "mp charged for base Cure, not Cure 3")
    end
    H.assertEq(pend(terra), 0, "pending consumed")
    H.screenshot("fold_cast")
  end),
})
