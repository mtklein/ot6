-- @suite
-- battle_steal.lua -- boost-tiered Steal, the first "chance verb" of the
-- canon rule DESIGN.md states: on damage verbs boost multiplies; on chance
-- verbs boost GUARANTEES. Unboosted Steal is pure vanilla; each BP tilts the
-- common/rare gamble; the full 3-BP spend converts it outright -- a
-- guaranteed steal that takes the rare item if the enemy has one.
--
-- The hooks under test (ot6.asm):
--   Ot6StealBoostLevel -- replaces `lda $3b18,x` at the head of vanilla's
--     success math (TargetEffect_52, battle_main.asm). 0 bp returns the raw
--     level (byte-for-byte vanilla, sneak ring and all); 1/2 bp add +40/+90;
--     3 bp clamps to $ff so the next `adc #$32` overflows and vanilla's own
--     `bcs` guarantees the steal -- drawing no success RNG at all.
--   Ot6StealSlot -- replaces the vanilla 1/8-rare slot roll. 0 bp is the exact
--     vanilla roll (an empty picked slot still yields "nothing"); 1-3 bp are
--     fallback-aware (never "nothing" on a boosted success) and bias to the
--     rare slot, certain at 3 bp.
--   Ot6BoostDmg's $05 gate -- steal never gets a damage multiplier.
--
-- HOW THE RESOLUTION IS EXERCISED. The doorstep is the Magitek opening; its
-- target-select confines Steal to the party group, so the installed Locke's
-- steal resolves against a PARTY entity. That is deliberate and sound:
-- TargetEffect_52's path is target-type-agnostic -- it reads $3308+y/$3309+y
-- and grants $32f4+x for ANY target y -- so a party-entity target runs the
-- identical success-roll + slot-pick + boost-tier code a monster target would.
-- We poke every party entity's two steal slots (the RAM the notes call
-- "$3308 Steal Item 1 (12.5%)" / "$3309 Steal Item 2 (87.5%)", stride 2), the
-- way battle_bushido installs Cyan by poke. One actor acts per scenario
-- (others + enemies stopped), so every steal is attributable.
--
-- THE RNG IS DRIVEN DETERMINISTICALLY. With attacker and target in the party
-- group, level cancels: chance = level+50-targetLevel = 50, a coin flip. We pin
-- the battle RNG index $be the instant the roll runs -- an exec callback at
-- RandA (a $be write made anywhere earlier does not survive the intervening
-- draws) -- keyed to a value derived from the live RNGTbl so the success RandA
-- and the slot Rand land on chosen bytes: V_fail (a losing roll), V_common (the
-- 7/8 slot), V_rare (the 1/8 slot). The natural $be is stashed and handed back
-- when the message clears, so the pin never accumulates. That is the
-- seeded-stream idiom (bal_mines) sharpened to a single frame. 3 bp NEVER draws
-- RandA (its clamp overflows first), so those seeds simply never fire -- which
-- is the whole point: the guarantee is roll-free, provable by pinning the very
-- seeds that miss or take the common at 0 bp and still getting the rare.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR = 0x7BCA, 0x62CA
local PARTY = { 0, 1, 2 }
local MSLOTS = { 0, 1, 2, 3, 4, 5 }
local function ENT_C(s) return s * 2 end
local function ENT_M(s) return 8 + s * 2 end
local LOCKE = 0x01
local RARE, COMMON = 0xE0, 0xE1     -- distinct sentinel item ids
local NONE = 0xFF

local cfg = { rare = RARE, common = COMMON, pend = 3, ring = false, pinHp = true }
local actor, hp0
local V_fail, V_common, V_rare       -- $be seeds derived from RNGTbl at runtime
local pinBe = nil                    -- the seed to pin at the next steal roll
local armRoll = nil                  -- armed by $3401->2, fired at RandA (exec)
local beSaved = nil                  -- natural $be, handed back when the steal ends
local RNGTBL = 0x00FD00              -- ROM offset of RNGTbl (CPU C0/FD00)
local RANDA = 0xC24B98               -- battle RandA entry (ff6-en.map; re-derive
                                     --   if bank $C2 shifts). Pinning $be HERE,
                                     --   the instant the roll runs, is the only
                                     --   pin that survives to it.

local function stealRare(e)   return 0x3308 + e end
local function stealCommon(e) return 0x3309 + e end

local function pinEnemies()
  for _, s in ipairs(MSLOTS) do
    H.writeWord(0x3BFC + s * 2, 0xF000)                        -- never dies
    H.writeByte(0x3EF8 + ENT_M(s), H.readByte(0x3EF8 + ENT_M(s)) | 0x10) -- stopped:
    -- no enemy acts, so nothing attacks the actor (the no-damage assert is
    -- clean) and the RNG stays ours between drives.
  end
end

local function pinParty()
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, LOCKE)                         -- a real stealer
    H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) & 0xF7)  -- -magitek
    H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) & 0xCF)  -- -muddle/-berserk
    H.writeByte(0x202E + s * 12, 0x05)                         -- Steal, alone
    H.writeByte(0x2031 + s * 12, NONE)
    H.writeByte(0x2034 + s * 12, NONE)
    H.writeByte(0x2037 + s * 12, NONE)
    H.writeByte(0x3B18 + ENT_C(s), 50)                         -- level 50 both sides
    H.writeByte(stealRare(ENT_C(s)), cfg.rare)                 -- this scenario's slots
    H.writeByte(stealCommon(ENT_C(s)), cfg.common)
    if cfg.pinHp then H.writeWord(0x3BF4 + s * 2, 999) end
  end
  if actor then
    for _, s in ipairs(PARTY) do                               -- only the actor acts
      if s ~= actor then
        H.writeByte(0x3EF8 + ENT_C(s), H.readByte(0x3EF8 + ENT_C(s)) | 0x10)
      end
    end
    H.writeByte(0x3E9C + actor * 2, 5)                         -- full bank
    H.writeByte(0x3E9D + actor * 2, cfg.pend)                  -- pending boost
    local r2 = 0x3C45 + actor * 2                              -- relic effects 2
    if cfg.ring then H.writeByte(r2, H.readByte(r2) | 0x01)    -- bit 0 = Sneak Ring
    else H.writeByte(r2, H.readByte(r2) & 0xFE) end
  end
end

local function pin() pinEnemies(); pinParty() end

-- outcome recorder: one entry per steal, delimited by the $3401=1 entry write
local attempts = {}
local function resetRec() attempts = {}; armRoll = nil; beSaved = nil end
local function cur() return attempts[#attempts] end

-- drive one FRESH steal: settle first (let the cfg's slots take and any prior
-- action drain), then A (pick Steal), A (confirm the default self/party target)
local function driveOneSteal()
  return H.repeatN(1, {
    H.repeatN(30, { H.call(pin), H.waitFrames(1) }),
    H.call(resetRec),
    H.driveUntil(function() return #attempts >= 1 and cur().done end, 9000, {
      H.call(function()
        pin()
        if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
      end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(3),
      H.call(function() if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(14),
    }, "a steal resolves"),
  })
end

local function outcome()
  local a = cur() or {}
  if a.grant == RARE then return "rare"
  elseif a.grant == COMMON then return "common"
  elseif a.grant ~= nil then return "item:" .. string.format("%02x", a.grant)
  else return "nothing" end
end

H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pin), H.waitFrames(1),
  }, "menu opens (Locke installed)"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("actor slot %d id=$%02x cmd0=$%02x",
      actor, H.readByte(0x3ED8 + actor * 2), H.readByte(0x202E + actor * 12)))

    -- Derive $be seeds from the live RNGTbl. RandA(100) at be=V reads
    -- RNGTbl[(V+1)&255]=r1 -> floor(r1*100/256); fails vs chance 50 iff r1>=128.
    -- The slot Rand then reads RNGTbl[(V+2)&255]=r2 -> rare iff r2<$20. Seeds
    -- re-derive each run, so an RNGTbl edit cannot silently invalidate a claim.
    local function rt(i) return H.readRomByte(RNGTBL + (i & 0xFF)) end
    for V = 0, 255 do
      local r1, r2 = rt(V + 1), rt(V + 2)
      local fail = ((r1 * 100) >> 8) >= 50
      if fail and not V_fail then V_fail = V end
      if not fail and r2 >= 0x20 and not V_common then V_common = V end
      if not fail and r2 < 0x20 and not V_rare then V_rare = V end
    end
    H.log(string.format("$be seeds: fail=%s common=%s rare=%s",
      tostring(V_fail), tostring(V_common), tostring(V_rare)))
    H.assertEq(V_fail ~= nil and V_common ~= nil and V_rare ~= nil, true,
      "RNGTbl yields a fail / common / rare seed")
    -- drift guard: RANDA must still point at RandA's opening `phx` ($DA). A
    -- bank-$C2 edit ahead of RandA (e.g. the Blitz path) shifts it; re-derive
    -- from ff6/rom/ff6-en.map (name="RandA" val=0x......) rather than debug a
    -- silent mispin.
    H.assertEq(H.readRomByte(RANDA & 0x3FFFFF), 0xDA, string.format(
      "RANDA ($%06X) no longer opens RandA -- re-derive from ff6-en.map", RANDA))

    -- $3401 message code (1=entry, 2=past empty check, 3=stole); $ff = cleared.
    -- The 2 ARMS the seed; the RandA exec callback applies it the instant the
    -- roll runs (a write-time pin does not survive -- other RNG draws between).
    emu.addMemoryCallback(function(_, v)
      if v == 1 then attempts[#attempts + 1] = { code = 1 }
      elseif v == 2 and cur() then
        cur().code = 2
        if pinBe then armRoll = pinBe end
      elseif v == 3 and cur() then cur().code = 3
      elseif v == NONE then
        if cur() and not cur().done then cur().done = true end
        if beSaved then H.writeByte(0xBE, beSaved); beSaved = nil end  -- hand back
      end
    end, emu.callbackType.write, 0x7E3401, 0x7E3401)
    -- Pin $be at RandA (the success roll): it reads RNGTbl[seed+1], the slot Rand
    -- then RNGTbl[seed+2]. Stash the natural value; restore it when the steal's
    -- message clears so nothing accumulates across drives. 3 bp skips RandA (its
    -- clamp overflows first), so an armed seed never fires -- guarantee is
    -- roll-free.
    emu.addMemoryCallback(function()
      if armRoll then beSaved = H.readByte(0xBE); H.writeByte(0xBE, armRoll); armRoll = nil end
    end, emu.callbackType.exec, RANDA, RANDA)
    -- $32f4,x obtained item; non-$ff = the item stolen
    emu.addMemoryCallback(function(_, v)
      if v ~= NONE and cur() then cur().grant = v end
    end, emu.callbackType.write, 0x7E32F4, 0x7E32F4 + 18)
    pin()
  end),

  -- 1. THREE BP = GUARANTEED RARE, ACROSS ADVERSARIAL SEEDS. 3 bp takes no roll
  -- (the clamp overflows before $ee is even formed), so we pin $be to the very
  -- seeds a 0-bp steal would MISS on (V_fail) or take the COMMON on (V_common)
  -- and demand a rare success every time. Six different points in the stream:
  -- not one lucky roll.
  H.call(function() cfg = { rare = RARE, common = COMMON, pend = 3, ring = false, pinHp = true } end),
  H.call(function() pinBe = V_fail end), driveOneSteal(),
  H.call(function()
    H.assertEq(outcome(), "rare", "3 bp took the RARE item (seed V_fail)")
    H.assertEq(cur().code, 3, "3 bp is a guaranteed success")
  end),
  H.call(function() pinBe = V_common end), driveOneSteal(),
  H.call(function() H.assertEq(outcome(), "rare", "3 bp rare (seed V_common)") end),
  H.call(function() pinBe = V_rare end), driveOneSteal(),
  H.call(function() H.assertEq(outcome(), "rare", "3 bp rare (seed V_rare)") end),
  H.call(function() pinBe = 0x40 end), driveOneSteal(),
  H.call(function() H.assertEq(outcome(), "rare", "3 bp rare (seed $40)") end),
  H.call(function() pinBe = 0xC0 end), driveOneSteal(),
  H.call(function()
    H.assertEq(outcome(), "rare", "3 bp rare (seed $C0)")
    H.screenshot("steal_3bp_rare")
  end),

  -- 2. ZERO BP IS THE VANILLA ROLL, DRIVEN DETERMINISTICALLY. On a winning seed
  -- the unboosted steal lands and takes the COMMON -- the 7/8 slot, exactly
  -- vanilla, and NOT the rare 3 bp forces on the same both-present enemy.
  H.call(function() cfg = { rare = RARE, common = COMMON, pend = 0, ring = false, pinHp = true } end),
  H.call(function() pinBe = V_common end), driveOneSteal(),
  H.call(function()
    H.assertEq(outcome(), "common", "0 bp lands and takes the COMMON (vanilla 7/8)")
  end),
  -- the 1/8 seed takes the rare: 0 bp CAN reach it, just rarely.
  H.call(function() pinBe = V_rare end), driveOneSteal(),
  H.call(function()
    H.assertEq(outcome(), "rare", "0 bp reaches the rare only on the 1/8 roll")
  end),
  -- the losing seed MISSES: the exact seed 3 bp shrugged off. Boost has not
  -- leaked into the 0-bp path.
  H.call(function() pinBe = V_fail end), driveOneSteal(),
  H.call(function()
    H.assertEq(outcome(), "nothing", "0 bp MISSES on the losing roll (a real gamble)")
  end),

  -- 2b. 3 bp on a common-only enemy: fallback-aware, so it takes the common.
  -- The guarantee is "rare IF PRESENT" -- here it is not, and boost never
  -- conjures. (No pin: 3 bp draws no roll.)
  H.call(function()
    cfg = { rare = NONE, common = COMMON, pend = 3, ring = false, pinHp = true }; pinBe = nil
  end),
  driveOneSteal(),
  H.call(function()
    H.assertEq(outcome(), "common",
      "3 bp falls back to the COMMON when the rare is absent (guarantee != conjuring)")
  end),

  -- 3. SNEAK RING keeps helping the unboosted (the deliberate ruling). Pin the
  -- SAME losing seed V_fail that missed bare above: the ring doubles chance
  -- 50->100, so now it LANDS. Both slots hold the same item so the slot roll
  -- can't vary the result. (At 3 bp the ring is moot -- the clamp overflows
  -- before $ee is ever formed.)
  H.call(function()
    cfg = { rare = 0x66, common = 0x66, pend = 0, ring = true, pinHp = true }; pinBe = V_fail
  end),
  driveOneSteal(),
  H.call(function()
    H.assertEq(cur().code, 3, "sneak ring doubles chance 50->100: the losing seed now lands")
    H.assertEq(outcome(), "item:66", "the ringed 0-bp steal took the item")
  end),

  -- 4. THE ECONOMY: 3 bp charged, no +1 regen that turn, pending cleared.
  H.call(function()
    cfg = { rare = RARE, common = COMMON, pend = 3, ring = false, pinHp = true }; pinBe = nil
    H.writeByte(0x3E9C + actor * 2, 5); H.writeByte(0x3E9D + actor * 2, 3)
  end),
  driveOneSteal(),
  H.waitUntil(function() return H.readByte(0x3E9D + actor * 2) == 0 end, 1200,
    "pending consumed", 10),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("economy: bp=%d pending=%d",
      H.readByte(0x3E9C + actor * 2), H.readByte(0x3E9D + actor * 2)))
    H.assertEq(H.readByte(0x3E9C + actor * 2), 2, "5 bp - 3 spent = 2, regen skipped")
    H.assertEq(H.readByte(0x3E9D + actor * 2), 0, "pending cleared after the action")
  end),

  -- 5. NO DAMAGE MULTIPLIER (Ot6BoostDmg's $05 gate). Self-target means any
  -- stray damage lands on the actor; its HP must not move across a 3-bp steal.
  H.call(function()
    cfg = { rare = RARE, common = COMMON, pend = 3, ring = false, pinHp = false }; pinBe = nil
    H.writeByte(0x3E9C + actor * 2, 5); H.writeByte(0x3E9D + actor * 2, 3)
    hp0 = H.readWord(0x3BF4 + actor * 2)
  end),
  driveOneSteal(),
  H.call(function()
    local hp1 = H.readWord(0x3BF4 + actor * 2)
    H.log(string.format("actor hp %d -> %d across a 3-bp steal", hp0, hp1))
    H.assertEq(hp1, hp0, "steal dealt no damage (boost bought certainty, not a x8)")
  end),

  -- 6a. NEGATIVE CONTROL -- boost cannot conjure loot. Both slots empty ($ff):
  -- even 3 bp yields nothing (the $ffff top check drops out before the hooks).
  H.call(function()
    cfg = { rare = NONE, common = NONE, pend = 3, ring = false, pinHp = true }; pinBe = nil
    H.writeByte(0x3E9C + actor * 2, 5); H.writeByte(0x3E9D + actor * 2, 3)
  end),
  driveOneSteal(),
  H.call(function()
    H.assertEq(outcome(), "nothing", "empty enemy: 3 bp steals nothing (no conjuring)")
  end),

  -- 6b. NEGATIVE CONTROL -- an already-looted enemy. Steal a both-present enemy
  -- once at 3 bp (takes the rare, clears both slots); freeze the slots empty; a
  -- second 3-bp steal must yield nothing (the clear is vanilla; no re-looting).
  H.call(function()
    cfg = { rare = RARE, common = COMMON, pend = 3, ring = false, pinHp = true }; pinBe = nil
    H.writeByte(0x3E9C + actor * 2, 5); H.writeByte(0x3E9D + actor * 2, 3)
  end),
  driveOneSteal(),
  H.call(function()
    H.assertEq(outcome(), "rare", "first 3-bp steal took the rare and cleared the slots")
    cfg.rare, cfg.common = NONE, NONE           -- freeze empty against the re-pin
    H.writeByte(0x3E9C + actor * 2, 5); H.writeByte(0x3E9D + actor * 2, 3)
  end),
  driveOneSteal(),
  H.call(function()
    H.assertEq(outcome(), "nothing", "already-looted enemy: 3 bp re-loots nothing")
    H.screenshot("steal_negatives")
  end),
})
