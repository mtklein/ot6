-- probe_muddle_n024.lua -- NUMBER 024 (battle 72) from the n024_entry
-- snapshot under the lib fight driver, traced for Muddle (#170).
--
--   OT6_ACTION_TRACE=1 tools/tests/run.sh tools/tests/probe_muddle_n024.lua build/states/muddle_n024.log
--
-- Hand-run instrument (probe_): boots build/states/n024_entry.mss (the
-- battle_magicite lab's own boot), stands still SEED frames to shift the
-- battle-RNG phase ($021e, period 60), enters the fight the way that lab
-- does (UP into the tube, A until battle-up), runs gen_esper_tubes'
-- driver options {tactical, boost, bank=3, items, healPercent=60,
-- cadence=12}, and reports one machine-readable [result] line, PASSing
-- either way -- this file measures, it does not assert a win.
--
-- Read-only observers, beside the driver's own action trace:
--   [st2]   a party member's STATUS2 byte ($3ee5,e*2) changing, with the
--           frame -- bit 5 ($20) is CONFUSE, the Muddle the boss's SPECIAL
--           lands (battle_magicite measured it at f1803 on this boot);
--   [exec]  every command the engine dispatches at ExecCmd (party or
--           monster: cmd/attack after queue-time folding, the target word)
--           and its return at SaveForMimic, with the party's HP and the
--           actor's STATUS2 -- the same two observers the lib's action
--           trace reads, which only follows newFightDriver plans and so
--           sees nothing of a muddled character's game-chosen action.
-- The [result] line counts: Muddle landings on the party, party commands
-- dispatched BY a muddled actor with the party in their target word (the
-- self-AoE #170 is about), party Fights dispatched at an ally by an
-- unmuddled actor (the cure), and how many of those cleared the bit.
--
-- Pad presses and reads only; complete snapshots only.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/n024_entry.mss.lua"
local SEED = tonumber("@SEED@") or 0
local N024 = 0x010A
local ST2_MUDDLE = 0x20
local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0

local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxHp(e) return H.readWord(0x3C1C + e * 2) end
local function st2(e) return H.readByte(0x3EE5 + e * 2) end
local function partyLine()
  local hps, sts = {}, {}
  for e = 0, 3 do
    hps[#hps + 1] = tostring(hp(e))
    sts[#sts + 1] = string.format("%02x", st2(e))
  end
  return table.concat(hps, "/"), table.concat(sts, " ")
end
local function bag(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return H.readByte(0x1969 + i) end
  end
  return 0
end

-- the tallies the [result] line carries
local R = { muddled = 0, selfAoe = 0, allyHits = 0, cleared = 0,
            deaths = {}, defers = 0 }
local st2Last = {}
local function statusWatch()
  if not H.battleLoadStarted() then return end
  for e = 0, 3 do
    local v = st2(e)
    if st2Last[e] ~= nil and v ~= st2Last[e] then
      H.log(string.format("[st2 f%d] entity %d STATUS2 %02x -> %02x%s", H.frame,
        e, st2Last[e], v,
        ((v & ST2_MUDDLE) ~= 0 and (st2Last[e] & ST2_MUDDLE) == 0) and " MUDDLED"
        or (((v & ST2_MUDDLE) == 0 and (st2Last[e] & ST2_MUDDLE) ~= 0) and " muddle cleared" or "")))
      if (v & ST2_MUDDLE) ~= 0 and (st2Last[e] & ST2_MUDDLE) == 0 then
        R.muddled = R.muddled + 1
      end
    end
    st2Last[e] = v
  end
end

-- the engine observer (battle_magicite's, trimmed): party dispatches
-- carry the actor's own STATUS2 so a muddled actor's game-chosen action
-- is visible as such
local execA, execB = H.sym("ExecCmd@battle_code"), H.sym("SaveForMimic")
local pending = {}                     -- actor -> { muddled, tgt, cmd, atk, st2before }
local observerOn = false
local function installObserver()
  if observerOn then return end
  observerOn = true
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if x % 2 ~= 0 or x >= 20 then return end
    local cmd, atk, tgt = H.readByte(0xB5), H.readByte(0xB6), H.readWord(0xB8)
    local hps, sts = partyLine()
    local who = x < 8 and ("party" .. (x // 2)) or ("mon" .. (x // 2 - 4))
    local muddled = x < 8 and (st2(x // 2) & ST2_MUDDLE) ~= 0
    H.log(string.format("[exec f%d] %s cmd=%02x atk=%02x tgt=%04x%s | hp=%s st2=%s",
      H.frame, who, cmd, atk, tgt, muddled and " (ACTOR MUDDLED)" or "", hps, sts))
    if x < 8 then
      local a = x // 2
      pending[a] = { muddled = muddled, tgt = tgt, cmd = cmd, atk = atk }
      if muddled and (tgt & 0x000F) ~= 0 and (tgt & 0x000F) ~= (1 << a) then
        R.selfAoe = R.selfAoe + 1
        H.log(string.format("[muddle f%d] party%d, MUDDLED, dispatched cmd=%02x "
          .. "atk=%02x at the party (tgt=%04x) -- the #170 shape", H.frame, a,
          cmd, atk, tgt))
      elseif muddled and (tgt & 0x000F) ~= 0 then
        R.selfAoe = R.selfAoe + 1
        H.log(string.format("[muddle f%d] party%d, MUDDLED, dispatched cmd=%02x "
          .. "atk=%02x at itself (tgt=%04x)", H.frame, a, cmd, atk, tgt))
      elseif not muddled and cmd == 0x00 and (tgt & 0x000F) ~= 0 and tgt < 0x100 then
        local t = nil
        for e = 0, 3 do if (tgt & (1 << e)) ~= 0 then t = e end end
        pending[a].allyTarget = t
        pending[a].st2before = t and st2(t) or 0
        R.allyHits = R.allyHits + 1
        H.log(string.format("[unmuddle f%d] party%d Fights ally entity %s "
          .. "(tgt=%04x; its STATUS2 %02x)", H.frame, a, tostring(t), tgt,
          pending[a].st2before))
      end
    end
  end, emu.callbackType.exec, execA, execA)
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if x % 2 ~= 0 or x >= 20 then return end
    local hps, sts = partyLine()
    local who = x < 8 and ("party" .. (x // 2)) or ("mon" .. (x // 2 - 4))
    H.log(string.format("[done f%d] %s | hp=%s st2=%s", H.frame, who, hps, sts))
    if x < 8 then
      local p = pending[x // 2]
      if p and p.allyTarget then
        local after = st2(p.allyTarget)
        if (p.st2before & ST2_MUDDLE) ~= 0 and (after & ST2_MUDDLE) == 0 then
          R.cleared = R.cleared + 1
          H.log(string.format("[unmuddle f%d] party%d's hit CLEARED entity %d's "
            .. "Muddle (STATUS2 %02x -> %02x)", H.frame, x // 2, p.allyTarget,
            p.st2before, after))
        else
          H.log(string.format("[unmuddle f%d] party%d's hit on entity %d: STATUS2 "
            .. "%02x -> %02x", H.frame, x // 2, p.allyTarget, p.st2before, after))
        end
      end
      pending[x // 2] = nil
    end
  end, emu.callbackType.exec, execB, execB)
end

local hpLast = {}
local function deathWatch()
  if not H.battleLoadStarted() then return end
  for e = 0, 3 do
    local v = hp(e)
    if hpLast[e] ~= nil and hpLast[e] > 0 and v == 0 and maxHp(e) > 0 then
      R.deaths[#R.deaths + 1] = string.format("e%d@f%d", e, H.frame)
      H.log(string.format("[death f%d] entity %d down", H.frame, e))
    end
    hpLast[e] = v
  end
end

local F = H.newFightDriver("b72", { tactical = true, boost = true, bank = 3,
  items = true, healPercent = 60, cadence = 12, actionTrace = true })

local fenix0, potion0, tonic0 = 0, 0, 0
local wipedN, lostEarly, bUp = 0, nil, nil
local hb = 0

H.run({ maxFrames = 80000, allowGameOver = true }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    installObserver()
    fenix0, potion0, tonic0 = bag(FENIX), bag(POTION), bag(TONIC)
    H.log(string.format("[probe] n024_entry loaded: map %d (%d,%d) party %s bag Fenix %d Potion %d Tonic %d",
      H.mapId() & 0x1ff, H.fieldX(), H.fieldY(), (partyLine()), fenix0, potion0, tonic0))
  end),
  H.waitFrames(SEED),
  -- battle_magicite's enterBoss, verbatim in its timing
  H.hold({ "up" }), H.waitFrames(4), H.release(), H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "battle 72 opens"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.call(function()
    bUp = H.frame
    H.assertEq(H.formationHas({ [N024] = true }), true, "battle 72 is NUMBER 024 $010A")
    H.log(string.format("[probe] battle up at f%d, $021e=%d", bUp, H.readByte(0x021E)))
  end),
  H.waitFrames(120),
  H.driveUntil(function()
    wipedN = H.partyWipedInBattle() and wipedN + 1 or 0
    if (H.gameOverFired or 0) > 0 and not lostEarly then
      lostEarly = string.format("GAME OVER at f%d", H.frame)
    elseif wipedN >= 90 and not lostEarly then
      lostEarly = string.format("WIPED at f%d", H.frame)
    end
    if lostEarly then return true end
    return not H.battleLoadStarted() and not H.partyWipedInBattle()
  end, 60000, {
    H.call(function()
      hb = hb + 1
      statusWatch()
      deathWatch()
      if hb % 600 == 0 then
        local hps, sts = partyLine()
        H.log(string.format("[hb f%d] n024 hp=%d sh=%d tk=%d | party %s st2=%s",
          H.frame, H.readWord(0x3BFC), H.readByte(0x3E40), H.readByte(0x3E90), hps, sts))
      end
      F.frame()
    end),
  }, "battle 72 under the lib driver"),
  H.call(function()
    F.idle(); H.setPad({})
    local hps, sts = partyLine()
    H.log(string.format(
      "[result] probe=muddle_n024 seed=%d outcome=%s bframes=%d muddled=%d "
      .. "self_aoe_by_muddled=%d ally_hits=%d muddle_cleared_by_hit=%d "
      .. "deaths=%s fenix=%d potion=%d tonic=%d party=[%s] st2=[%s]",
      SEED, lostEarly and "lost" or "won", H.frame - (bUp or H.frame), R.muddled,
      R.selfAoe, R.allyHits, R.cleared,
      #R.deaths > 0 and table.concat(R.deaths, ";") or "none",
      fenix0 - bag(FENIX), potion0 - bag(POTION), tonic0 - bag(TONIC), hps, sts))
  end),
})
