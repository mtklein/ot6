-- @suite slow frontier=figaro_cleared
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
--     vanilla roll; 1-3 bp are fallback-aware (never "nothing" on a boosted
--     success) and bias to the rare slot, certain at 3 bp.
--   Ot6BoostDmg's $05 gate -- steal never gets a damage multiplier.
--
-- Issue #75 conversion.  The old apparatus rebuilt the entire battle by
-- poke: LOCKE installed into all three magitek slots, Steal forged into
-- $202E, level 50 written to BOTH sides, sentinel steal slots written into
-- $3308/$3309 for every entity, enemies HP-pinned and STOPped, bp/pending
-- handed, MP pinned, and the $BE RNG index seeded at RandA to chosen
-- bytes.  On figaro_cleared every one of those is a fact instead: LOCKE
-- really carries Steal (row 1, the #55 thief submenu), the desert pool's
-- formation seeds real species with real authored steal slots (measured:
-- species $5C rare=$F2=common, two $5D with rare EMPTY / common Tonic --
-- LoadMonsterProp loads them from MonsterItems, battle_main.asm:7505), and
-- levels are real on both sides (L6 vs L6 -> vanilla chance = 6+50-6 = 50,
-- a coin flip).  The bank is earned by real zero-MP item turns; pending by
-- real R edges.
--
-- THE SEED PINS ARE REPLACED BY A SHARPER ZERO-WRITE DECODE.  An exec
-- callback at RandA READS $BE at the instant the success roll runs and
-- computes the byte the engine is about to draw (r1 = RNGTbl[be+1],
-- roll = r1*100>>8); every unboosted attempt then asserts its OUTCOME
-- matches vanilla's own model (lands iff roll < 50) -- so a miss is not
-- luck-noise but a verified prediction, and a run of successes cannot
-- silently weaken the gamble claim.  The 3-bp guarantee is proven
-- ROLL-FREE directly: zero RandA draws during its resolution -- stronger
-- than any adversarial seed, because there is no roll to survive.
--
-- THE SNEAK RING ARM IS A LABELED ISOLATION ARM (owner ruling 2026-08-10,
-- waiver-burndown plan: mechanism decodes may keep memory-hack staging
-- where the fixture cannot produce the input on cue).  No fixture chain
-- owns a Sneak Ring; the game's own sources are a shop we never visit and
-- a steal FROM species $14 -- owning the ring in normal play is future work.  The
-- arm sets/clears one relic bit ($3C45 bit 0) around two unboosted
-- attempts and uses the same roll decode: with the ring the model becomes
-- "lands iff roll < 100", and any observed roll >= 50 that lands is a
-- roll the bare arm verifiably missed on.  This is the file's ONLY
-- remaining write surface (the .writeByte waiver survives for it alone).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/figaro_cleared.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_THIEF, ST_ITEM, ST_TGT, ST_TRANS = 0x05, 0x30, 0x0A, 0x38, 0x01
local CMD_STEAL, CMD_ITEM = 0x05, 0x01
local NONE = 0xFF
local TONIC, POTION = 0xE8, 0xE9
local RNGTBL = H.sym("RNGTbl") & 0x3FFFFF
local RANDA = H.sym("RandA")

local locke
local function bp() return H.readByte(0x3E9C + locke*2) end
local function pend() return H.readByte(0x3E9D + locke*2) end
local function mp() return H.readWord(0x3C08 + locke*2) end
local function lockeHp() return H.readWord(0x3BF4 + locke*2) end
local function stealRare(s)   return H.readByte(0x3308 + 8 + s*2) end
local function stealCommon(s) return H.readByte(0x3309 + 8 + s*2) end
local function monLevel(s)    return H.readByte(0x3B18 + 8 + s*2) end
local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i*5 + 3) > 0 then return i end
    end
  end
  return nil
end

-- ------------------------------------------------- the observation rig --
-- per-steal record: code trail ($3401: 1=entry, 2=past empty check,
-- 3=stole; $ff=cleared), grant ($32F4 range), RandA draws inside the
-- resolution window with the roll each would produce, hp at entry/clear.
local rec = nil
local function newRec() rec = { draws = {}, code = 0 } end
local function rollOf(be)
  return (H.readRomByte(RNGTBL + ((be + 1) & 0xFF)) * 100) >> 8
end
local function armWatches()
  emu.addMemoryCallback(function(_, v)
    if not rec then return end
    if v == 1 then rec.code = math.max(rec.code, 1); rec.hp0 = lockeHp()
    elseif v == 2 then rec.code = math.max(rec.code, 2)
    elseif v == 3 then rec.code = math.max(rec.code, 3)
    elseif v == NONE and rec.code >= 1 and not rec.done then
      rec.done = true; rec.hp1 = lockeHp()
    end
  end, emu.callbackType.write, 0x7E3401, 0x7E3401)
  emu.addMemoryCallback(function()
    if rec and rec.code >= 1 and not rec.done then
      local be = H.readByte(0xBE)
      rec.draws[#rec.draws + 1] = { be = be, roll = rollOf(be) }
    end
  end, emu.callbackType.exec, RANDA, RANDA)
  -- gate the grant on the steal message being OPEN (code >= 1): the bank
  -- turns' item use also writes its item id into this region (measured:
  -- a banking Tonic's $E8 landed in the re-loot record as a false grant)
  emu.addMemoryCallback(function(_, v)
    if rec and rec.code >= 1 and v ~= NONE and not rec.done then rec.grant = v end
  end, emu.callbackType.write, 0x7E32F4, 0x7E32F4 + 18)
end

-- ------------------------------------------------------ the menu drive --
-- others defer with X; Locke banks item turns to `wantBp`, boosts to
-- `wantPend` by real R edges, then steals at the monster slot `target`.
local mf = 0
local drive = { wantBp = 0, wantPend = 0, target = nil }
-- the target-cursor latch/steer machine, promoted into the lib from this
-- file's original copy (H.targetCursor keeps the measured facts: the
-- blink-proof every-frame latch, the reset outside target select --
-- measured here: the re-loot arm stole from the wrong monster off a stale
-- latch -- and the per-press-cycle {left,down,right,up} grid rotation)
local tc = H.targetCursor({ mask = 0x7B7E })
local function decide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  tc.observe()
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  -- the item window needs the slow 6-on/24-off cadence (battle_preview's
  -- measurement); everything else takes 4-on/4-off
  local slow = (act == locke and st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if act ~= locke then
    btn = (st == ST_CMD) and "x" or "b"
  elseif bp() < drive.wantBp then                -- BANK: real item turns
    if st == ST_CMD then
      local want = cmdRowOf(locke, CMD_ITEM)
      local cur = H.readByte(CMDROW + locke) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = bagIdxOf({ TONIC, POTION })
      if want == nil then error("bank ran out of items", 0) end
      local cur = H.readByte(0x8947 + locke) + H.readByte(0x894F + locke)
      if cur < want then btn = "down"
      elseif cur > want then btn = "up"
      else btn = "a" end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif pend() < drive.wantPend then            -- BOOST: real R edges
    btn = (st == ST_CMD) and "r" or "b"
  else                                           -- STEAL via the #55 submenu
    if st == ST_CMD then
      local want = cmdRowOf(locke, CMD_STEAL)
      local cur = H.readByte(CMDROW + locke) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_THIEF then btn = "a"         -- Steal is submenu row 0
    elseif st == ST_TGT then
      btn = tc.steer(drive.target, mf)
    else btn = "b" end
  end
  if btn and (mf - 1) % 32 == 0 then
    H.log(string.format("drv: f%d st=%02x act=%d %s (bp=%d pend=%d mp=%d tgt=%s mask=%02x code=%s)",
      H.frame, st, act, btn, bp(), pend(), mp(), tostring(drive.target),
      H.readByte(0x7B7E), rec and tostring(rec.code) or "-"))
  end
  return btn and { [btn] = true } or {}
end

-- one steal: configure the drive, run it until the record completes.
-- drive.target is set by the caller (it needs live classify() data).
local function oneSteal(tag, wantBp, wantPend)
  return H.repeatN(1, {
    H.call(function()
      drive.wantBp, drive.wantPend = wantBp, wantPend
      newRec()
    end),
    H.driveUntil(function() return rec.done == true end, 30000, {
      H.call(function() H.setPad(decide()) end),
    }, tag),
    H.call(function()
      H.setPad({})
      local d = {}
      for _, w in ipairs(rec.draws) do d[#d+1] = tostring(w.roll) end
      H.log(string.format("[%s] code=%d grant=%s draws={%s} bp=%d pend=%d "
        .. "mp=%d hp %s->%s", tag, rec.code, rec.grant and
        string.format("%02X", rec.grant) or "nil", table.concat(d, ","),
        bp(), pend(), mp(), tostring(rec.hp0), tostring(rec.hp1)))
    end),
    H.waitFrames(60),
  })
end

-- --------------------------------------------------------- the battles --
local plan, idx, goal = nil, 1, nil
-- classify the live formation: `rareT` = a slot whose rare slot is
-- populated; `emptyRareTs` = slots with rare EMPTY but common populated.
local rareT, fbT1, fbT2
local function classify()
  rareT, fbT1, fbT2 = nil, nil, nil
  for s = 0, 5 do
    if H.readWord(0x3BFC + s*2) > 0 then
      if stealRare(s) ~= NONE then rareT = rareT or s
      elseif stealCommon(s) ~= NONE then
        if fbT1 == nil then fbT1 = s else fbT2 = fbT2 or s end
      end
    end
  end
end

-- enter a desert battle whose formation is SUITABLE for the arm: every
-- arm needs a both-populated species (rareT); battle 3 additionally
-- needs a common-only species (fbT1) for the fallback arm.  Flee
-- anything else and re-patrol (measured: the pool draws at least two
-- formation types -- 1x$5C+2x$5D mixed, and rare-holders-only).
local needFb = false
local function suitable()
  return rareT ~= nil and ((not needFb) or fbT1 ~= nil)
end
local function enterDesertBattle(n, wantFb)
  local steps = { H.call(function() needFb = wantFb or false end) }
  for try = 1, 6 do
    steps[#steps+1] = H.cond(function()
      return H.battleLoadStarted() and suitable()
    end, {}, {
      H.cond(function() return H.battleLoadStarted() end, {
        H.logStep("formation unsuitable -- fleeing for a fresh draw"),
        H.fleeBattle(12000),
        H.waitFrames(240),
      }, {}),
      H.call(function() plan, goal = nil, nil end),
      H.driveUntil(function() return H.battleLoadStarted() end, 25000, {
        H.call(function()
          if not H.worldMode() or not H.worldHasControl() then
            plan = nil; H.setPad({}); return
          end
          local phase = (H.frame // 120) % 2
          H.setPad(phase == 0 and { left = true } or { right = true })
        end),
      }, "desert encounter " .. n .. " try " .. try),
      H.release(),
      H.waitUntil(function() return H.battleActive() end, 900,
        "battle " .. n .. " active", 30),
      H.waitFrames(90),
      H.call(function()
        locke = nil
        for slot = 0, 3 do
          if H.readByte(0x3ED8 + slot*2) == 0x01 then locke = slot end
        end
        H.assertEq(locke ~= nil, true, "LOCKE is really in this party")
        H.assertEq(cmdRowOf(locke, CMD_STEAL) ~= nil, true,
          "his real Steal exists")
        classify()
        H.log(string.format("battle %d formation: rareT=%s fbT1=%s fbT2=%s",
          n, tostring(rareT), tostring(fbT1), tostring(fbT2)))
      end),
    })
  end
  steps[#steps+1] = H.call(function()
    H.assertEq(suitable(), true,
      "a suitable desert formation drawn within six encounters")
  end)
  return H.repeatN(1, steps)
end

H.run({ maxFrames = 150000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.hold({ "b" }),                    -- real chocobo dismount (gen_kolts)
  H.driveUntil(function() return H.readByte(0x11fa) & 3 == 0 end, 900, {
    H.waitFrames(1),
  }, "chocobo dismount"),
  H.release(),
  H.waitFrames(120),

  -- ================= BATTLE 1: the 3-bp guarantee, and no re-looting ====
  enterDesertBattle(1),
  H.call(function()
    armWatches()
    H.assertEq(rareT ~= nil, true,
      "the real formation seeds a rare-slot species ($5C)")
    H.log(string.format("targets: rare=%s (slots %02X/%02X, lvl %d) "
      .. "locke lvl %d mp %d", tostring(rareT), stealRare(rareT),
      stealCommon(rareT), monLevel(rareT), H.readByte(0x3B18 + locke*2), mp()))
  end),
  -- ARM 1: bank 3 by real item turns, R x3, steal the rare holder.
  (function()
    local wantRare
    return H.repeatN(1, {
      H.call(function()
        wantRare = stealRare(rareT)
        drive.target = rareT
      end),
      oneSteal("3bp guaranteed steal", 3, 3),
      H.call(function()
        H.assertEq(rec.code, 3, "3 bp is a guaranteed success")
        H.assertEq(#rec.draws, 0,
          "...and draws NO success RNG at all (the clamp overflows first)")
        H.assertEq(rec.grant, wantRare,
          "3 bp took the RARE slot's item (species-authored, read live)")
        H.assertEq(stealRare(rareT), NONE,
          "the game's own clear emptied the rare slot")
        H.assertEq(stealCommon(rareT), NONE, "...and the common slot")
        H.assertEq(rec.hp1, rec.hp0,
          "steal dealt no damage (boost bought certainty, not a x8)")
      end),
      -- the charge lands at Ot6ActionEnd, after the message clears
      H.waitUntil(function() return pend() == 0 end, 900,
        "the boost is consumed", 10),
      H.waitFrames(30),
      H.call(function()
        H.assertEq(bp(), 0, "3 banked - 3 spent = 0, regen skipped")
        H.assertEq(pend(), 0, "pending cleared after the action")
        H.screenshot("steal_3bp_rare")
      end),
    })
  end)(),
  -- ARM 6b: an already-looted enemy.  Re-bank, 3 bp again, same target:
  -- boost cannot conjure -- nothing is taken, and still no roll.
  oneSteal("3bp re-loot attempt", 3, 3),   -- drive.target still the looted one
  H.call(function()
    H.assertEq(rec.grant, nil, "already-looted enemy: 3 bp re-loots nothing")
    H.assertEq(rec.code < 3, true, "no stole-message on an empty enemy")
    H.assertEq(#rec.draws, 0, "and still no roll (empties exit before it)")
  end),
  H.fleeBattle(12000),
  H.waitFrames(240),

  -- ================= BATTLE 2: the RING (labeled isolation arm) =========
  -- One ringed attempt, on the BOTH-populated species: on a common-only
  -- target vanilla's 1/8 slot roll can pick the empty rare and turn a
  -- landed roll into "nothing", which would muddy the lands-iff-roll<100
  -- model this arm asserts.
  enterDesertBattle(2),
  H.call(function()
    -- ISOLATION WRITE (waived, labeled): no fixture owns a Sneak Ring; see
    -- the file header.  One relic bit on, cleared again below.
    H.writeByte(0x3C45 + locke*2, H.readByte(0x3C45 + locke*2) | 0x01)
    drive.target = rareT
  end),
  oneSteal("ringed 0-bp steal", 0, 0),
  H.call(function()
    H.assertEq(#rec.draws >= 1, true,
      "the ringed steal still DREW the roll (0 bp stays vanilla-shaped)")
    local roll = rec.draws[1].roll
    H.log(string.format("ringed roll=%d (bare model would %s)", roll,
      roll < 50 and "also land" or "MISS -- doubling observed"))
    H.assertEq(rec.code, 3,
      "ringed steal landed (model: lands iff roll < 100)")
    H.assertEq(rec.grant ~= nil, true, "and took an item")
    -- take the ring back off: the arms below must be bare vanilla
    H.writeByte(0x3C45 + locke*2, H.readByte(0x3C45 + locke*2) & 0xFE)
  end),
  H.fleeBattle(12000),
  H.waitFrames(240),

  -- ========== BATTLE 3: the fallback, and the bare vanilla gamble =======
  enterDesertBattle(3, true),
  -- ARM 2b: 3 bp on a common-only enemy: fallback-aware, so it takes the
  -- common.  The guarantee is "rare IF PRESENT" -- here it is not, and
  -- boost never conjures.  Still roll-free.
  (function()
    local wantCommon
    return H.repeatN(1, {
      H.call(function()
        H.assertEq(fbT1 ~= nil, true, "a common-only monster seeded")
        wantCommon = stealCommon(fbT1)
        drive.target = fbT1
      end),
      oneSteal("3bp fallback steal", 3, 3),
      H.call(function()
        H.assertEq(rec.code, 3, "3 bp still a guaranteed success")
        H.assertEq(#rec.draws, 0, "still roll-free")
        H.assertEq(rec.grant, wantCommon,
          "3 bp falls back to the COMMON when the rare is absent "
          .. "(guarantee != conjuring)")
      end),
    })
  end)(),
  -- ARM 2: 0 bp is the vanilla roll, DECODED not seeded: each attempt
  -- must draw the success roll, and its outcome must match vanilla's own
  -- model (lands iff roll < 50, chance = L6+50-L6).  Attempts run until
  -- one lands or the MP budget for two is spent.
  -- ARM 2: 0 bp is the vanilla roll, DECODED not seeded: each attempt
  -- must draw the success roll, and its outcome must match vanilla's own
  -- model (lands iff roll < 50, chance = L6+50-L6).  The target is the
  -- BOTH-populated species so the slot pick cannot turn a landed roll
  -- into "nothing" (see the ring arm's note).  Up to three attempts
  -- (4 MP each against the remaining real pool).
  (function()
    local tries, landed, wantVal = 0, false, nil
    return H.repeatN(1, {
      H.driveUntil(function() return landed or tries >= 3 end, 90000, {
        H.call(function()
          drive.target = rareT
          wantVal = stealRare(rareT)
        end),
        oneSteal("bare 0-bp attempt", 0, 0),
        H.call(function()
          tries = tries + 1
          H.assertEq(#rec.draws >= 1, true,
            "0 bp DREW the success roll (boost has not leaked in)")
          local roll = rec.draws[1].roll
          local hit = rec.code == 3
          H.log(string.format("bare attempt %d: roll=%d -> %s",
            tries, roll, hit and "landed" or "missed"))
          -- vanilla's own model, verified per attempt: this is the seeded
          -- V_fail/V_common sweep collapsed into a prediction check
          H.assertEq(hit, roll < 50,
            "outcome matches vanilla's model exactly (lands iff roll < 50)")
          if hit then
            landed = true
            H.assertEq(rec.grant, wantVal,
              "the landed 0-bp steal took the species' authored item")
          end
        end),
      }, "bare vanilla attempts"),
      H.call(function()
        H.log(string.format("bare arm done: %d attempt(s), landed=%s, mp=%d",
          tries, tostring(landed), mp()))
        H.screenshot("steal_vanilla")
      end),
    })
  end)(),
})
