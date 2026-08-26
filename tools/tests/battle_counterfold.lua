-- battle_counterfold.lua -- a counter's boosted-fold behavior, simulated
-- since the in-play trigger (a raged GAU countering with a tier-family
-- spell) cannot be produced on cue.
-- @suite savestate=battle_entry

-- The reachable in-play instance is a raged GAU whose species counters
-- with a tier-family spell -- choreography nobody can produce on cue --
-- so this is a focused unit-style test in the battle_steal mold: the
-- counter's BOOKKEEPING is simulated exactly (a write-callback mirrors
-- CreateNormalAction's $32CC,x pointer into the counter slot $32CD,x and
-- raises $b1.0, which is precisely the state CreateRetalAction leaves,
-- battle_main.asm:13206-13211), and the same cast is made twice:

-- Isolation writes (waived, labeled): the pending-boost byte $3E9D,x
-- (the precondition both arms need), the counter slot $32CD,x and flag
-- $b1 (the simulation itself).  Reads and pad presses otherwise.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_TGT, ST_TRANS, ST_MAGIC = 0x05, 0x38, 0x01, 0x0E
local MLISTPTR, CURMP = 0x302C, 0x3C08
local CMD_MAGIC, FIRE = 0x02, 0x00

local terra = 0                       -- battle_entry: TERRA is slot 0
local function mp() return H.readWord(CURMP + terra * 2) end
local function fireCell()
  local base = H.readWord(MLISTPTR + terra * 2)
  if base < 0x2000 or base > 0x2600 then return nil end
  for cell = 0, 53 do
    local at = base + (cell + 1) * 4
    if H.readByte(at) == FIRE then return cell, H.readByte(at + 3) end
  end
  return nil
end
local function cmdRowOf(a, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + a * 12 + i * 3) == cmd then return i end
  end
  return nil
end

-- the counter simulation: mirror CreateNormalAction's pointer write into
-- the counter slot the instant it lands, and raise $b1.0 -- one shot
local simArmed, simFired = false, false
emu.addMemoryCallback(function()
  if not simArmed or simFired then return end
  simFired = true
  local ptr = H.readByte(0x32CC + terra * 2)
  H.writeByte(0x32CD + terra * 2, ptr)
  H.writeByte(0xB1, H.readByte(0xB1) | 0x01)
end, emu.callbackType.write, 0x7E32CC + terra * 2, 0x7E32CC + terra * 2)

-- one Fire cast through the real menu; returns after the debit is seen.
-- basePrice is captured before the boost goes up (Ot6FoldPrices moves the
-- DISPLAYED price once it is pending, so the menu shows the folded cost).
local function castFire(tag, sim)
  local mf, mpAt, delta = 0, nil, nil
  return H.driveUntil(function()
    if mpAt and mp() ~= mpAt then delta = mpAt - mp() end
    return delta ~= nil
  end, 12000, {
    H.call(function()
      mf = mf + 1
      if mf % 600 == 0 then
        H.log(string.format("  [%s] mf=%d menu=%02X st=%02X act=%d mp=%d",
          tag, mf, H.readByte(MENU), H.readByte(MSTATE),
          H.readByte(ACTOR), mp()))
      end
      if H.readByte(MENU) == 0 then H.setPad({}); return end
      if mf % 10 >= 5 then H.setPad({}); return end
      local a = H.readByte(ACTOR)
      local st = H.readByte(MSTATE)
      if st == ST_TRANS then H.setPad({}); return end
      if a ~= terra then
        H.setPad(st == ST_CMD and (mf % 8 < 4 and { x = true } or {})
                 or { b = true })
        return
      end
      local btn = nil
      if st == ST_CMD then
        if mpAt then H.setPad({}); return end
        local row = cmdRowOf(a, CMD_MAGIC)
        if row == nil then error(tag .. ": TERRA has no Magic row", 0) end
        local cur = H.readByte(CMDROW + a) & 3
        btn = (cur == row) and "a" or (cur < row and "down" or "up")
      elseif st == ST_MAGIC then
        local cell = fireCell()
        if cell == nil then error(tag .. ": Fire not in the list", 0) end
        local wantRow, wantCol = cell // 2, cell % 2
        local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
        local col = H.readByte(0x8917 + a)
        if absRow ~= wantRow then
          btn = (absRow < wantRow) and "down" or "up"
        elseif col ~= wantCol then
          btn = (col < wantCol) and "right" or "left"
        else
          if mpAt == nil then
            mpAt = mp()
            simArmed, simFired = sim, false
          end
          btn = "a"
        end
      elseif st == ST_TGT then
        btn = "a"
      else
        btn = "b"       -- #90
      end
      H.setPad(btn and { [btn] = true } or {})
    end),
  }, tag), function() return delta end
end

local basePrice = nil
local ctrlStep, ctrlDelta = castFire("control: boosted Fire folds", false)
local armStep, armDelta = castFire("arm: the counter must not fold", true)

H.run({ maxFrames = 100000 }, {
  H.loadState(STATE),
  H.waitFrames(20),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    local cell, cost = fireCell()
    H.assertEq(cell ~= nil, true, "TERRA knows Fire")
    basePrice = cost
    H.log(string.format("[fold] Fire base price (menu, unboosted): %d MP",
      basePrice))
    -- the pending boost, both arms' precondition (waived write)
    H.writeByte(0x3E9D + terra * 2, 1)
  end),
  ctrlStep,
  H.call(function()
    local d = ctrlDelta()
    H.log(string.format("[fold] control: boosted Fire debited %d MP " ..
      "(base %d)", d, basePrice))
    H.assertEq(d > basePrice, true,
      "control: the pending boost folded the cast and charged the " ..
      "folded tier's price (#64) -- the discriminator discriminates")
    -- re-arm the boost for the second cast
    H.writeByte(0x3E9D + terra * 2, 1)
  end),
  armStep,
  H.call(function()
    local d = armDelta()
    H.log(string.format("[fold] arm: counter-flagged Fire debited %d MP " ..
      "(base %d)", d, basePrice))
    H.assertEq(d, basePrice,
      "the counterattack arm held: an action whose queue pointer matches " ..
      "$32CD,x while $b1.0 is up is NOT folded and NOT re-priced")
    -- clear the simulated flag before the run ends
    H.writeByte(0xB1, H.readByte(0xB1) & 0xFE)
  end),
})
