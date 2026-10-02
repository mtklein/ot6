-- @suite savestate=wor_grave
-- battle_typicalgate.lua -- the typical-action gate read live (review of
-- ad048b29): Dullahan's fight, the grave pressed with A as the route does,
-- played by the fight driver one call a frame, while this file keeps its
-- own ground truth from the engine.
--
-- The ground truth: every monster entry into ExecCmd (the same hook the
-- driver uses, installed separately here), with the counterattack flag
-- ($B1 bit 0) and the party target bits ($B8) as it entered, and the party
-- HP that fell between that entry and the next ExecCmd entry of anybody.
-- By the gate's rule (M.ledgerCommit) an entry counts in the typical mean
-- when it is not the script's $2E/$2F and either it is a counter that
-- landed HP, or it is not a counter and it aimed at the party or landed HP.
--
-- Asserted: the driver's slot-0 ledger counted exactly the entries the
-- ground truth says (L.actN), and the fight held at least one counter
-- that landed (precondition: Dullahan's retal Battle, "if_hit: attack
-- NOTHING, NOTHING, BATTLE", ai_script.asm:5470).  The bcf5240f-ad048b29
-- reading -- one monAct for a run of the same slot, every counter out
-- (H.MONACT_OLD) -- counted 89 of 227 entries over arm B's 32 fights
-- (build/attempts/wt/care-policy-review/recount_r3.txt); it is this
-- file's negative control.  Nothing here writes emulated state.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_grave.mss.lua"
local MENU = 0x7BCA
local F, truth, cur, ledgerN, ledgerSum = nil, {}, nil, nil, nil
local hpLast = {}

local function up() return H.battleLoadStarted() and H.monstersPresent() > 0 end

local hooked = false
local function hook()
  if hooked then return end
  hooked = true
  local a = H.sym("ExecCmd@battle_code")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if x >= 20 or x % 2 ~= 0 then return end
    cur = nil
    if x >= 8 then
      cur = { slot = x // 2 - 4, cmd = H.readByte(0xB5), atk = H.readByte(0xB6), b1 = H.readByte(0xB1),
              party = H.readByte(0xB8) & 0x0F, drop = 0, frame = H.frame }
      truth[#truth + 1] = cur
    end
  end, emu.callbackType.exec, a, a)
end

local function tick()
  if not up() then F.idle(); return end
  F.frame()
  for e = 0, 3 do
    local hp = H.readWord(0x3BF4 + e * 2)
    if cur ~= nil and hpLast[e] ~= nil and hpLast[e] ~= 0xFFFF and hp < hpLast[e] then
      cur.drop = cur.drop + (hpLast[e] - hp)
    end
    hpLast[e] = hp
  end
  local L = F.driver.hitLedger and F.driver.hitLedger[0]
  if L ~= nil and L.actN ~= nil then ledgerN, ledgerSum = L.actN, L.actSum end
end

H.run({ maxFrames = 30000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    hook()
    F = H.newFightDriver("typicalgate", { tactical = true, boost = true, items = true, runic = true })
  end),
  H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000, "the grave: face up, A"),
  H.release(),
  H.waitUntil(function() return up() end, 3000, "the fight is up", 1),
  H.driveUntil(function() return not up() end, 25000, { H.call(tick) }, "the driver's play"),
  H.release(),
  H.call(function()
    local want, counters, landed, counted = 0, 0, 0, {}
    for i, t in ipairs(truth) do
      local c
      if t.cmd == 0x2E or t.cmd == 0x2F then c = false
      elseif (t.b1 & 0x01) ~= 0 then
        counters = counters + 1
        c = t.drop > 0
        if c then landed = landed + 1 end
      else c = t.party ~= 0 or t.drop > 0 end
      if c and t.slot == 0 then want = want + 1 end
      if i <= 40 then
        H.log(string.format("[typicalgate] truth %d: f%d slot %d cmd $%02X atk $%02X $B1=$%02X party=$%X dropped %d -> %s",
          i, t.frame, t.slot, t.cmd, t.atk, t.b1, t.party, t.drop, c and "counted" or "out"))
      end
    end
    H.log(string.format("[typicalgate] ExecCmd entries %d, counters %d (landed %d); the gate's count for slot 0 %d; "
      .. "the driver's ledger counted %s (sum %s)", #truth, counters, landed, want, tostring(ledgerN), tostring(ledgerSum)))
    H.assertEq(landed >= 1, true, "precondition: a counterattack landed HP in the fight (Dullahan's retal Battle)")
    H.assertEq(ledgerN, want, "the driver's typical-action count for slot 0 is the ground truth's")
    H.log("[typicalgate] PASSED")
  end),
})
