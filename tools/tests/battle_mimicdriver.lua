-- @suite slow
-- battle_mimicdriver.lua -- the fight driver's Mimic line for GOGO (#270;
-- Driver:mimicLine, kits.md "Gogo").
--
-- Played: Continue the wor-gogo-v1 battery (the play's save beside the
-- Falcon by Thamasa, GOGO seated with STRAGO, RELM and TERRA and his kit
-- Mimic, Lore, Tools, Item: nothing here writes it), pace two tiles of the
-- plain there into its random battles, and let the real driver fight each
-- one.  Whatever the plain deals, the first battle in which the driver
-- plans GOGO's Mimic and the engine copies an action for his seat
-- (mimicreplace) is the one measured; the asserts read the engine:
--   1. the plan is carried out: mimicreplace runs for GOGO's seat, and what
--      it copies (the saved action, $3F20 command, $3F21 attack) is a
--      command the line copies (M.MIMIC_COPY).  The copy is the party's
--      last action when GOGO's turn runs, which can be a later one than the
--      plan read (another member acting between the plan and the copy:
--      measured, lab md1, a Tools plan copied a Fight); both are logged;
--   2. the price: GOGO's MP ($3C08 + his seat) when his copy ends
--      (Ot6ActionEnd for his seat) is his MP at mimicreplace: Mimic is free
--      (mp-economy.md);
--   3. the boost: the pips GOGO holds pending at the copy are the ones the
--      plan asked for (capped at the bank he held), so the copy buys what
--      the plan bought.
-- Then the control: MIMIC_OFF set, the next battle is fought with no
-- mimicreplace for GOGO's seat at all.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 0x0C
local BUDGET = 16                     -- battles to see a measured Mimic in
local A, B = { 251, 229 }, { 252, 229 }   -- the plain beside the Falcon, clear of the town's door (251,230)
local FIGHT = {}

local function gogoSlot()
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == GOGO then return s end end
  return nil
end
local cur, done = nil, nil
local nm0, n0 = 0, 0
local inBattle = false
local function fresh() return { copies = 0 } end

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("wor-gogo-v1"),
  H.call(function()
    H.assertEq(H.partyOfChar(GOGO), 1, "GOGO seated in wor-gogo-v1 (the play's own save)")
    H.assertEq(H.readByte(0x1600 + 37 * GOGO + 0x16), 0x12, "GOGO's first command Mimic")
    n0 = #H.outcomes
    -- the copy: mimicreplace runs with the acting seat in X
    emu.addMemoryCallback(function()
      local s = gogoSlot()
      if cur and s ~= nil and (emu.getState()["cpu.x"] & 0xFF) == s * 2 then
        cur.copies = cur.copies + 1
        if cur.copy == nil then
          cur.copy = { cmd = H.readByte(0x3F20), atk = H.readByte(0x3F21), mp = H.readWord(0x3C08 + s * 2),
            pend = H.readByte(0x3E9C + s * 2 + 1), bank = H.readByte(0x3E9C + s * 2) }
        end
      end
    end, emu.callbackType.exec, H.sym("mimicreplace"), H.sym("mimicreplace"))
    -- the copy's end: Ot6ActionEnd for the same seat
    emu.addMemoryCallback(function()
      local s = gogoSlot()
      if cur and cur.copy and cur.copy.mpEnd == nil and s ~= nil and (emu.getState()["cpu.x"] & 0xFF) == s * 2 then
        cur.copy.mpEnd = H.readWord(0x3C08 + s * 2)
      end
    end, emu.callbackType.exec, H.sym("Ot6ActionEnd"), H.sym("Ot6ActionEnd"))
  end),
  H.worldNavTo(A[1], A[2], { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
  H.driveUntil(function()
    local b = H.battleLoadStarted()
    if b and not inBattle then
      inBattle, cur, nm0 = true, fresh(), #H.mimics
    elseif not b and inBattle and H.worldMode() and H.worldSettled() then
      inBattle = false
      if #H.mimics > nm0 then cur.plan = H.mimics[nm0 + 1] end
      H.log(string.format("[mimic] battle %d: Mimic plans %d; copies %d; %s", #H.outcomes - n0, #H.mimics - nm0,
        cur.copies, cur.copy and string.format("first copy cmd $%02X atk $%02X, MP %d -> %s, pending %d, bank %d",
          cur.copy.cmd, cur.copy.atk, cur.copy.mp, tostring(cur.copy.mpEnd), cur.copy.pend, cur.copy.bank) or "no copy"))
      if cur.plan and cur.copy and cur.copy.mpEnd and done == nil then done = cur end
    end
    if done then return not inBattle and H.worldMode() and H.worldSettled() end
    if #H.outcomes - n0 > BUDGET then
      error(string.format("no Mimic planned and copied within %d battles on Thamasa's plain", BUDGET))
    end
    return false
  end, 800000, {
    H.worldNavTo(B[1], B[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
    H.worldNavTo(A[1], A[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
  }, "battles until GOGO's Mimic is measured"),
  H.call(function()
    local p, c = done.plan, done.copy
    H.log(string.format("[mimic] measured: plan copy cmd $%02X atk $%02X at %d BP (bank %d); engine copy cmd $%02X "
      .. "atk $%02X, pending %d, MP %d -> %d", p.cmd, p.atk, p.boost, p.bp, c.cmd, c.atk, c.pend, c.mp, c.mpEnd))
    H.assertEq(done.copies >= 1, true, "1. mimicreplace ran for GOGO's seat after the plan")
    H.assertEq(H.MIMIC_COPY[c.cmd] ~= nil, true, string.format("1. the engine's copy (cmd $%02X) is one the line copies",
      c.cmd))
    H.assertEq(c.mpEnd, c.mp, "2. GOGO's MP when his copy ends is his MP at the copy: Mimic is free")
    H.assertEq(c.pend, math.min(p.boost, p.bp, 3), "3. the pips pending at the copy are the plan's boost")
  end),
  -- the control: the same driver with the line off
  H.call(function()
    MIMIC_OFF = true
    done, n0 = nil, #H.outcomes
  end),
  H.driveUntil(function()
    local b = H.battleLoadStarted()
    if b and not inBattle then
      inBattle, cur = true, fresh()
    elseif not b and inBattle and H.worldMode() and H.worldSettled() then
      inBattle = false
      done = cur
      H.log(string.format("[mimic] control battle: copies for GOGO %d", cur.copies))
    end
    return done ~= nil
  end, 400000, {
    H.worldNavTo(B[1], B[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
    H.worldNavTo(A[1], A[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
  }, "a control battle with MIMIC_OFF"),
  H.call(function() H.assertEq(done.copies, 0, "control: with the line off GOGO never Mimics") end),
})
