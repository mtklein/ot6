-- @suite slow
-- battle_esperknight.lua -- Golem's signature covers only from a knight who can take the hit (#534, #535;
-- docs/design/esper-rework.md; ot6_esper.asm Ot6KnightGate).  Vanilla's True Knight cover has no gate on the
-- knight's own HP; the signature's cover (the relic's bit, $3C58 & $40, from Ot6LadderTbl row 21 rung 5) is meant
-- as a pure upgrade, so a knight not wearing the relic covers only at half its max HP or more and never while near
-- fatal.
--
-- Continue post-opera-v1.  Staged (declared in state_write_waivers.txt, a mechanism expedient): Golem's count at
-- 500 on the first seated member K, who wears no True Knight relic, on the live esper page; then a random battle on
-- the world map.  At its open, K's relic effects 4 carry the cover bit and no other seated member's do (the cover
-- walk would otherwise reach that member and not ask about K), and a snapshot.  Two branches from it, each with its
-- own HP writes (staged): T, another member, at 1 HP and near fatal (the state a cover answers); K at full HP
-- ("above half") or at one under half its max, above near fatal ("below half").  Everyone Defends (the real menu)
-- until a monster's attack on near-fatal T walks the cover candidates and asks Ot6KnightGate about K (an
-- opportunity), then 180 frames for the attack to resolve.  A branch whose battle gives no opportunity (T dies to a
-- spell, the battle ends) goes again from the snapshot after more idle frames, at most TRIES times.  Idle frames
-- move the in-battle RNG only, which does not re-draw the encounter (docs/TESTING.md "Tests that survive any
-- draw"), so when a battle's tries run out the battle is fought out from the snapshot and the next encounter is
-- taken: a new formation, a new snapshot, and the branches that have no opportunity yet.  The encounters allowed
-- come from the zone's decoded pool odds (the rarest slot at 99%), as battle_esperconductor's do.
--   above half: K covers T (Ot6CoverBP, the cover's commit, runs on K);
--   below half: an opportunity, and no cover.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM",
  "SETZER", "MOG", "GAU" }
local LIVE, GOLEM, TRUE_KNIGHT = 0x317C00, 21, 0xBE
local TRIES, IDLE = 6, 45                  -- per battle: idle frames 0, 45, ... before the next encounter
local function seated(c) local b = H.readByte(0x1850 + c); return b ~= 0 and (b & 7) == H.readByte(0x1A6D) end
local function slot(c, s) return H.readByte(0x1600 + 37 * c + 0x1F + s) end

local K, T, eK, eT
local A, B = nil, nil
local BUDGET, encounters = nil, 0          -- encounters allowed (pool odds), and taken
local snap
local obs                                  -- this try's { opp, cover, at }
local res = {}

local function pending(name) return res[name] == nil or res[name].opp == nil end

-- up to TRIES tries from this battle's snapshot, while the branch has no opportunity yet
local function branch(name, kHp)
  local t = {}
  for k = 1, TRIES do
    t[#t + 1] = H.cond(function() return pending(name) end, {
      H.call(function()
        H.setPad({})
        res[name] = res[name] or { tries = 0 }
        obs = nil
        snap.load = H.requestLoadState(snap.blob)
      end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(snap.load, "the snapshot at the battle's open")
        H.rearmInputInjection()
        local maxK, maxT = H.readWord(0x3C1C + eK), H.readWord(0x3C1C + eT)
        local hp = kHp(maxK)
        H.writeWord(0x3BF4 + eK, hp)
        H.writeWord(0x3BF4 + eT, 1)
        H.writeByte(0x3EE5 + eT, H.readByte(0x3EE5 + eT) | 0x02)
        H.assertEq((H.readByte(0x3EE5 + eK) & 0x02) == 0 and hp * 8 > maxK, true,
          name .. ": K is not near fatal")
        obs = { opp = 0, cover = 0, at = nil }
        res[name].tries = res[name].tries + 1
        H.log(string.format("[knight] %s, encounter %d try %d: %s at %d of %d HP, %s at 1 of %d and near fatal; "
          .. "%d idle frames", name, encounters, k, NAMES[K], hp, maxK, NAMES[T], maxT, (k - 1) * IDLE))
      end),
      (function()
        local w = 0
        return H.driveUntil(function() w = w + 1; return w > (k - 1) * IDLE end, TRIES * IDLE + 10,
          { H.call(function() H.setPad({}) end) }, "idle")
      end)(),
      H.driveUntil(function()
        return (obs.at ~= nil and H.frame - obs.at > 180) or not H.battleLoadStarted()
          or (obs.at == nil and H.readWord(0x3BF4 + eT) == 0)     -- T fell without a cover walk
      end, 20000, {
        H.kitBattle({}, { idle = "defend", care = false, maxFrames = 20000 }),
      }, name .. ": an attack on near-fatal T"),
      H.call(function()
        H.log(string.format("[knight] %s, encounter %d try %d: %d opportunit%s, %d cover%s by %s", name, encounters,
          k, obs.opp, obs.opp == 1 and "y" or "ies", obs.cover, obs.cover == 1 and "" or "s", NAMES[K]))
        if obs.opp > 0 then res[name].opp, res[name].cover = obs.opp, obs.cover end
      end),
    }, {})
  end
  return H.seqStep(t)
end

local function allDone() return not pending("above half") and not pending("below half") end

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("post-opera-v1"),
  H.call(function()
    H.assertEq(emu.read(LIVE, emu.memType.snesMemory) | (emu.read(LIVE + 1, emu.memType.snesMemory) << 8), 0x3145,
      "the live esper page is signed ('E1', ot6_esper.asm OT6_ESPER_MAGIC_WORD)")
    for c = 0, 11 do
      if seated(c) then
        if K == nil and slot(c, 4) ~= TRUE_KNIGHT and slot(c, 5) ~= TRUE_KNIGHT then K = c
        elseif T == nil then T = c end
      end
    end
    H.assertEq(K ~= nil and T ~= nil, true, "a seated member without the True Knight relic, and another")
    local addr = LIVE + 0x10 + (K * 26 + GOLEM) * 2
    emu.write(addr, 500 & 0xFF, emu.memType.snesMemory)
    emu.write(addr + 1, 500 >> 8, emu.memType.snesMemory)
    H.log(string.format("[knight] K = %s (relics $%02X $%02X), Golem's count staged at 500; T = %s", NAMES[K],
      slot(K, 4), slot(K, 5), NAMES[T]))
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A = { x, y }
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(plain(x, y) and B ~= nil, true, "two plain tiles that roll random battles")
    -- the budget from the zone's pool: the battles within which every slot comes up, at 99%
    local pool = H.encounterPool(H.worldEncounterGroup(B[1], B[2]))
    local pmin = 1
    for s = 1, 4 do local sl = pool[s]; if sl and sl.odds and sl.odds > 0 then pmin = math.min(pmin, sl.odds / 256) end end
    BUDGET = math.ceil(math.log(0.01) / math.log(1 - pmin))
    H.log(string.format("[knight] the rarest slot %.3f: budget %d encounters of %d tries", pmin, BUDGET, TRIES))
    local gate, commit = H.sym("Ot6KnightGate"), H.sym("Ot6CoverBP")
    emu.addMemoryCallback(function()
      if obs and (emu.getState()["cpu.x"] & 0xFF) == eK then
        obs.opp = obs.opp + 1
        obs.at = obs.at or H.frame
      end
    end, emu.callbackType.exec, gate, gate)
    emu.addMemoryCallback(function()
      if obs and (emu.getState()["cpu.x"] & 0xFF) == eK then obs.cover = obs.cover + 1 end
    end, emu.callbackType.exec, commit, commit)
  end),
  H.driveUntil(allDone, 800000, {
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, "a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 1),
    H.waitFrames(30),
    H.call(function()
      encounters = encounters + 1
      H.assertEq(encounters <= BUDGET, true, string.format(
        "an attack on near-fatal T for both branches within %d encounters (above half %s, below half %s)", BUDGET,
        pending("above half") and "none" or "ok", pending("below half") and "none" or "ok"))
      eK, eT = nil, nil
      local carriers = {}
      for s = 0, 3 do
        local a = H.readByte(0x3ED8 + s * 2)
        if a == K then eK = s * 2 elseif a == T then eT = s * 2 end
        if a ~= K and a ~= 0xFF and seated(a) and (H.readByte(0x3C58 + s * 2) & 0x40) ~= 0 then
          carriers[#carriers + 1] = NAMES[a]
        end
      end
      H.assertEq(eK ~= nil and eT ~= nil, true, "K and T are in the battle")
      H.assertEq(H.readByte(0x3C58 + eK) & 0x40, 0x40, "K's relic effects 4 carry the cover bit (Golem's signature)")
      H.assertEq(#carriers, 0, "no seated member besides " .. NAMES[K] .. " carries the cover bit ($3C58 & $40): "
        .. table.concat(carriers, ", "))
      H.log(string.format("[knight] encounter %d of %d: formation $%03X; K at seat %d, T at seat %d", encounters,
        BUDGET, H.readWord(0x3ED4), eK // 2, eT // 2))
      H.setPad({})
      snap = { req = H.requestSaveState() }
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(snap.req, "the snapshot at the battle's open"); snap.blob = snap.req.blob end),
    branch("above half", function(m) return m end),
    branch("below half", function(m) return m // 2 - 1 end),
    -- tries spent without an opportunity: from the open again, fight it out (the staged HP is gone) and move on
    H.cond(function() return not allDone() end, {
      H.call(function()
        H.log(string.format("[knight] encounter %d: no opportunity yet for %s; fighting it out, then the next encounter",
          encounters, (pending("above half") and "above half " or "") .. (pending("below half") and "below half" or "")))
        H.setPad({})
        snap.load = H.requestLoadState(snap.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(snap.load, "the snapshot at the battle's open"); H.rearmInputInjection(); obs = nil end),
      H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(40000) }, {}),
      H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 2),
      H.fieldCare({ tag = "care between battles" }),
    }, {}),
  }, "an attack on near-fatal T in each branch"),
  H.call(function()
    local a, b = res["above half"], res["below half"]
    H.assertEq(a.opp ~= nil, true, string.format("above half: an attack on near-fatal T within %d encounters", BUDGET))
    H.assertEq(b.opp ~= nil, true, string.format("below half: an attack on near-fatal T within %d encounters", BUDGET))
    H.assertEq(a.cover >= 1, true, "above half: K covers T")
    H.assertEq(b.cover, 0, "below half: K does not cover T")
    H.log(string.format("[knight] %d encounter(s) of %d allowed; above half %d try(s), below half %d", encounters,
      BUDGET, a.tries, b.tries))
  end),
  H.logStep("[knight] PASS: Golem's signature covers from a knight at half HP or more, and not from one below"),
})
