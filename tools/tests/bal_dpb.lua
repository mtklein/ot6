-- @manual balance instrument (damage-per-BP), run by hand for tuning
-- bal_dpb.lua -- measures damage-per-BP by target state (shielded-unweak,
-- shielded-weak, broken) on the battle_break fixture (Magitek trio vs
-- guards):
--
--   tools/tests/run.sh tools/tests/bal_dpb.lua build/states/bal_dpb.log
--
-- Mashing A fires an unboosted or boosted Fire Beam at the default enemy
-- target every turn. Per frame the driver pins the target guards into an
-- exact state and pins the party's BP and pending, then records every
-- discrete HP drop with the (state, boost) label live at the moment the hit
-- landed. Pinning holds the state constant across many casts: shields never
-- deplete (chips are re-pinned), the broken timer never expires, and HP
-- never runs out, which makes the fight usable as a damage bench.
--
-- Three states x two boost levels = six phases; each collects N damage
-- samples. Fire Beam base is the same in every phase (casters pinned equal):
--   shielded-unweak   base x 0.5           (Ot6ShieldedDmg, shields up)
--   shielded-weak     base x2 x 0.5 = x1   (vanilla fire-weak, then shielded)
--   broken            base x2              (Ot6BrokenDmg, shields down)
--
-- The resistance byte is read live from ROM and logged, so this lab reports
-- the ordering at whatever Ot6ShieldedMulW the ROM (or a poke) carries.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

-- guards live in monster slots 2/3 (entity offsets $0C/$0E)
local GUARDS = { 2, 3 }
local function SH(slot)   return 0x3E38 + (8 + slot*2) end  -- shields
local function TM(slot)   return 0x3E88 + (8 + slot*2) end  -- broken timer
local function WK(slot)   return 0x3BE0 + (8 + slot*2) end  -- weak elements
local function MHP(slot)  return 0x3BFC + slot*2 end        -- monster cur hp (party is $3BF4)
local MENU  = 0x7BCA
local ACTOR = 0x62CA
local PIN_HP = 0xF000               -- guards pinned here; a hit never kills

-- resistance and hp knobs, read live from ROM for the log. Derived from
-- ff6/rom/ff6-en.dbg at compose time (H.sym). `& 0x3FFFFF` turns the CPU
-- address into the snesPrgRom file offset (bank $F0 -> $30xxxx).
local ROM_SHIELD = H.sym("Ot6ShieldedMulW") & 0x3FFFFF   -- word, low byte
local ROM_HPMUL  = H.sym("Ot6HpMulTbl") & 0x3FFFFF       -- band0 byte
-- POKE_SHIELD: if set, write this into Ot6ShieldedMulW before the phases,
-- so the ordering can be swept across resistance without a rebuild ($08=0.5x,
-- $0c=0.75x, $10=1x). nil = leave the shipped byte.
local POKE_SHIELD = nil

-- ----------------------------------------------------------- phase plan --
-- state: how to pin each guard; boost: pending BP for every cast in the phase
local N_PER_PHASE = 8               -- damage samples collected per phase
local PHASES = {
  { state = "unweak",  boost = 0 },
  { state = "unweak",  boost = 3 },
  { state = "weak",    boost = 0 },
  { state = "weak",    boost = 3 },
  { state = "broken",  boost = 0 },
  { state = "broken",  boost = 3 },
}

local function pinGuard(slot, state)
  if state == "unweak" then
    H.writeByte(WK(slot), 0)          -- no weakness
    H.writeByte(SH(slot), 8)          -- shields up (attenuate)
    H.writeByte(TM(slot), 0)          -- not broken
  elseif state == "weak" then
    H.writeByte(WK(slot), 0x01)       -- fire-weak (Fire Beam doubles)
    H.writeByte(SH(slot), 8)          -- shields up (attenuate the doubled hit)
    H.writeByte(TM(slot), 0)
  elseif state == "broken" then
    H.writeByte(WK(slot), 0)          -- clean broken x2, no element double
    H.writeByte(SH(slot), 0)          -- shields down: no attenuation
    H.writeByte(TM(slot), 0x08)       -- broken timer up (never expires: re-pinned)
  end
  H.writeWord(MHP(slot), PIN_HP)      -- top HP back up so nothing dies
end

-- ------------------------------------------------------ sample buckets --
-- samples[state][boost] = { dmg, dmg, ... }
local samples = {}
for _, s in ipairs({ "unweak", "weak", "broken" }) do
  samples[s] = { [0] = {}, [3] = {} }
end
local prevHp = {}
local pIdx = 1                       -- current phase index
local aphase = 0
local settleFrames = 90             -- discard in-flight beams after a switch

local function phaseFull()
  local p = PHASES[pIdx]
  return #samples[p.state][p.boost] >= N_PER_PHASE
end

local function frameLogic()
  local p = PHASES[pIdx]
  local settling = settleFrames > 0
  -- 1) record drops first (read the result of last frame's hit), before re-pin.
  --    Suppressed while settling so a beam in flight from the previous phase
  --    can't land in this phase's bucket.
  for _, slot in ipairs(GUARDS) do
    local hp = H.readWord(MHP(slot))
    local pv = prevHp[slot]
    if pv ~= nil and hp < pv and not phaseFull() and not settling then
      local d = pv - hp
      table.insert(samples[p.state][p.boost], d)
      H.log(string.format("[dpb] state=%s boost=%d dmg=%d (n=%d)",
        p.state, p.boost, d, #samples[p.state][p.boost]))
    end
  end
  -- 2) re-pin guard state + party BP/pending every frame (state held constant)
  for _, slot in ipairs(GUARDS) do
    pinGuard(slot, p.state)
    prevHp[slot] = PIN_HP             -- baseline reset to the pinned value
  end
  for c = 0, 2 do
    H.writeByte(0x3E9C + c*2, 5)      -- BP high enough to spend a 3-boost
    H.writeByte(0x3E9D + c*2, p.boost)
    H.writeWord(0x3BF4 + c*2, 999)    -- keep the party alive through the bench
  end
  if settling then settleFrames = settleFrames - 1 end
  -- 3) mash A on a duty cycle to fire Fire Beam at the default target
  aphase = (aphase + 1) % 30
  if H.readByte(MENU) ~= 0 and aphase < 4 then H.setPad({ "a" }) else H.setPad({}) end
end

-- ---------------------------------------------------------- aggregate --
local function mean(t)
  if #t == 0 then return 0 end
  local s = 0
  for _, v in ipairs(t) do s = s + v end
  return s / #t
end
local function report()
  local sh = H.readRomByte(ROM_SHIELD)
  local hp = H.readRomByte(ROM_HPMUL)
  H.log(string.format("[dpb] === Ot6ShieldedMulW=$%02X (%.3gx)  Ot6HpMulTbl.band0=$%02X (%.3gx) ===",
    sh, sh/16, hp, hp/16))
  local order = {}
  for _, st in ipairs({ "unweak", "weak", "broken" }) do
    local u = mean(samples[st][0])
    local b = mean(samples[st][3])
    local marg = b - u
    local perbp = marg / 3
    order[st] = perbp
    H.log(string.format(
      "[dpb] %-7s  unboosted=%.1f (n=%d)  boost3=%.1f (n=%d)  marginal=%.1f  per_bp=%.1f",
      st, u, #samples[st][0], b, #samples[st][3], marg, perbp))
  end
  H.log(string.format(
    "[dpb] ORDERING per_bp: broken=%.1f  weak=%.1f  unweak=%.1f",
    order.broken, order.weak, order.unweak))
  H.log(string.format("[dpb] ratios broken:weak:unweak = %.2f : %.2f : 1.00",
    order.broken / math.max(order.unweak, 0.01),
    order.weak / math.max(order.unweak, 0.01)))
  -- broken is 2x at every resistance (shields down); weak is 2*R and unweak is
  -- R, so broken >= weak always and weak is ~2x unweak always. At 1x
  -- resistance weak ties broken, so the bounds below are loose.
  H.assertEq(order.broken >= order.weak * 0.9, true, "broken buys at least as much per BP as shielded-weak")
  H.assertEq(order.weak >= order.unweak * 1.5, true, "shielded-weak clearly outbuys shielded-unweak")
  H.screenshot("bal_dpb")
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from entry point"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  -- equalize the three casters so Fire Beam base is caster-independent
  H.call(function()
    if POKE_SHIELD ~= nil then
      emu.write(ROM_SHIELD, POKE_SHIELD, emu.memType.snesPrgRom)
      H.assertEq(H.readRomByte(ROM_SHIELD), POKE_SHIELD, "resistance poked")
    end
    for c = 0, 2 do
      H.writeByte(0x3B18 + c*2, 5)    -- level
      H.writeByte(0x3B41 + c*2, 10)   -- magic power
    end
    for _, slot in ipairs(GUARDS) do prevHp[slot] = PIN_HP end
    H.log("[dpb] lab: casters level 5 / mag 10; guards pinned per phase")
  end),
  -- walk the six phases; each ends when it has N samples, then advance
  H.driveUntil(function()
    if settleFrames > 0 then return false end
    if phaseFull() then
      if pIdx >= #PHASES then return true end
      pIdx = pIdx + 1
      settleFrames = 90              -- flush before the next phase collects
    end
    return false
  end, 50000, {
    H.call(frameLogic),
    H.waitFrames(1),
  }, "all dpb phases collected"),
  H.call(report),
})
