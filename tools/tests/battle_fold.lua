-- @suite
-- battle_fold: boost folds tiered spells — Terra casting with 2 BP
-- pending executes the spell two tiers up (queued as the -ra/-ga id in
-- CreateAction, so name, animation, and power are the higher tier's own),
-- is CHARGED THAT TIER'S OWN MP (issue #64), and tier-family spells never
-- take the generic damage multiplier.
--
-- #64 INVERTED ONE OF THIS FILE'S ASSERTIONS, deliberately and with the
-- behaviour it was guarding.  Until v0.9 the fold charged the BASE spell's
-- MP, so this test asserted `cost < 51` -- "mp charged at base Fire rates,
-- never Fire 3's 51".  @vanorasc's suggestion (issue #64) is that this was
-- the bug: boost was a discount engine, strictly better than three separate
-- casts on both axes, fewer turns AND less MP.  BP buys tempo, MP buys
-- power.  So the bound is now `cost >= 51` -- the same measurement, the
-- opposite verdict, because the correct behaviour changed.  The assertion
-- also got STRICTER rather than looser: the MP delta is a bound (a trailing
-- muddle cast can add to it), so the mechanism is now pinned exactly by
-- watching the cost queue itself.
--
-- Terra is also kept SOLVENT here now, which she did not need to be before.
-- A folded Fire 3 costs 51 MP against an intro pool of ~40 (measured:
-- battle_foldcost.lua logs 127.5% of the L6 pool), so under real pricing the
-- cast this test exists to observe would simply fizzle on the universal
-- insufficient-MP gate.  That fizzle is CORRECT and is asserted where it
-- belongs -- battle_preview.lua's grey phase -- not here, where it would
-- delete the mechanic under test.
--
-- Menu input on this mint is unreliable (a mid-window interrupt eats
-- presses deterministically), so the cast goes through the vanilla
-- AUTO-action path instead: muddle Terra with a Magic-only command list
-- (magitek status cleared — it would force RandMagitekAction beams) and
-- she casts a random known spell for real. Fire and Cure both fold.
--   asserts: $3410 sees the tier-3 id at execution, the damage lands in
--   tier-3-potency-without-multiplier bounds, the TIER's own mp cost is
--   both queued and spent, and the boost is consumed.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local terra, mp0
local spells = {}

local hp0, bpFlush

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

-- #64: the queued MP costs, straight off the write that banks them.
-- CreateAction stores the cost into $3620,y (battle_main.asm:13163) and
-- Ot6QueueFold overwrites it with the folded tier's own price one
-- instruction later (ot6_boost.asm) -- so the queue is where the charge is
-- DECIDED, and watching it is immune to the MP delta's trailing-cast noise.
-- The queue is a full $100-byte page indexed by the action-list pointer (the
-- same shape as the command queue at $3420 and the target queue at $3520),
-- NOT four entity slots -- measured: a $3620-$3627 watch caught nothing at
-- all while a fold was demonstrably executing.  Watch the page.
local queued = {}
local function sawQueuedCost(want)
  for _, v in ipairs(queued) do if v == want then return true end end
  return false
end
local function queuedList()
  local out = {}
  for _, v in ipairs(queued) do out[#out + 1] = tostring(v) end
  return table.concat(out, " ")
end

-- Terra must be able to PAY the folded tier or the cast fizzles before it
-- can be observed: Fire 3 is 51 MP and Cure 3 is 40 against an intro pool
-- near 40.  Max is raised too -- vanilla clamps current to max on restore.
local function solvent()
  H.writeWord(0x3c30 + terra*2, 300)   -- max mp
  H.writeWord(0x3c08 + terra*2, 300)   -- current mp
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    terra = findTerra()
    H.log("terra is slot " .. terra)
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    -- stop the guards so nothing contests the run
    H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)
    H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
    H.log(string.format("terra mp=%d (intro), raising it to pay a folded tier",
      H.readWord(0x3c08 + terra*2)))
    solvent()
    mp0 = H.readWord(0x3c08 + terra*2)
    emu.addMemoryCallback(function(addr, value)
      spells[#spells + 1] = value
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
    emu.addMemoryCallback(function(_, value)
      queued[#queued + 1] = value
    end, emu.callbackType.write, 0x7e3620, 0x7e371f)
  end),
  -- a character who holds the menu when a confusion status lands keeps
  -- replaying its stale C1-staged action forever (the battle_hits
  -- lesson), so drive A until the menu belongs to someone ELSE — only
  -- then is terra safe to muddle (RandCharAction reads her live list)
  H.driveUntil(function()
    return H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= terra
  end, 10000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) == terra then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "menu passed beyond terra"),
  H.call(function()
    local st1 = 0x3ee4 + terra*2
    H.writeByte(st1, H.readByte(st1) & 0xf7)      -- clear magitek
    H.writeByte(0x202e + terra*12, 0x02)          -- Magic
    H.writeByte(0x2031 + terra*12, 0xff)
    H.writeByte(0x2034 + terra*12, 0xff)
    H.writeByte(0x2037 + terra*12, 0xff)
    local st2 = 0x3ee5 + terra*2
    H.writeByte(st2, H.readByte(st2) | 0x20)      -- muddle: menu-less casts
  end),
  -- the fold reads pending AT QUEUE TIME (matching real menu flow, where
  -- R precedes confirm), and stray stale actions can consume an armed
  -- pending before her muddle roll queues. self-heal: re-arm every time
  -- the pending is consumed until a cast actually folds.
  H.driveUntil(function()
    for _, v in ipairs(spells) do
      if v == 0x09 or v == 0x2f then return true end
    end
    return false
  end, 16000, {
    H.call(function()
      if pend(terra) == 0 then
        solvent()                                 -- #64: a folded tier is 40-51
        mp0 = H.readWord(0x3c08 + terra*2)
        H.writeByte(0x3e9c + terra*2, 3)          -- bp
        H.writeByte(0x3e9d + terra*2, 2)          -- pending boost
        hp0 = {}
        for s = 0, 3 do
          -- intro hp (~65) saturates a killing hit; raise it so the
          -- drop is the actual damage dealt
          if hp(s) > 0 then H.writeWord(0x3bf4 + s*2, 400) end
          hp0[s] = hp(s)
        end
      end
    end),
    H.waitFrames(30),
  }, "a boosted cast folded"),
  H.call(function()
    local st2 = 0x3ee5 + terra*2                  -- un-muddle promptly
    H.writeByte(st2, H.readByte(st2) & 0xdf)
  end),
  -- the folded cast's animation is still playing; its ActionEnd consumes
  H.waitUntil(function() return pend(terra) == 0 end, 900,
    "folded cast resolves", 10),
  H.waitFrames(60),
  H.call(function()
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
    -- THE PROPERTY UNDER TEST (#64): the folded tier's own MP is charged.
    -- Asserted twice, at two levels.
    --
    -- (a) THE MECHANISM, exactly.  The tier's real price appears in the MP
    --     cost queue.  Ot6QueueFold re-prices $3620,y off MagicProp after the
    --     fold rewrites $3a7b, so a 51 (or a 40) in this strip is unambiguous:
    --     base Fire is 4 and base Cure 5, and nothing else in the fixture
    --     costs either.  On the pre-#64 ROM this list holds only base costs.
    local want = (fold3 == 0x09) and 51 or 40
    local tier = (fold3 == 0x09) and "Fire 3" or "Cure 3"
    H.log(string.format("costs queued: %s (want %s's %d)",
      queuedList(), tier, want))
    H.assertEq(sawQueuedCost(want), true, string.format(
      "%s was QUEUED at its own %d MP -- boost buys the tempo, not the "
      .. "magnitude (#64)", tier, want))
    -- (b) THE EFFECT.  The pool really moved by at least that much.  A bound
    --     rather than an equality: a trailing muddle cast can add a base
    --     price to the delta, which is why (a) exists.
    local mp1 = H.readWord(0x3c08 + terra*2)
    local cost = mp0 - mp1
    H.log(string.format("mp %d -> %d = %d spent (folded spell %02x)",
      mp0, mp1, cost, fold3))
    H.assertEq(cost >= want, true, string.format(
      "and the pool really paid it: %d spent, at least %s's %d",
      cost, tier, want))
    H.assertEq(pend(terra), 0, "pending consumed")
    H.screenshot("fold_cast")
  end),
})
