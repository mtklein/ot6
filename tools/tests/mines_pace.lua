-- mines_pace.lua -- Measurement #4: encounter-rate and reward parity on
-- the mines chase map (map 50). Companion to bal_mines.lua; same fixture
-- (mines_chase.mss: Terra L5 alone at the map entry), same two-tile
-- pacing route (78,58)<->(77,58), same seeded RNG discipline.
--
-- Two arms, selected by the ARM knob (one arm per run, like whelkbal's
-- POLICY):
--   vanilla  the three OT6 balance knobs are poked to identity IN THE
--            LOADED ROM IMAGE before every sample (emu.write to
--            snesPrgRom; verified by readback and by the danger-counter
--            delta): Ot6HpMulTbl band0 = $10 (1x trash HP), Ot6DangerMulW
--            = $10 (1x per-step danger), Ot6RewardMulW = $10 (1x
--            rewards). With all three at identity the encounter
--            arithmetic, fight HP, and rewards are vanilla's exactly
--            (the scale routines are exact at $10).
--   ours     the shipped values ($20 = 2x HP, $08 = 0.5x danger, $20 =
--            2x rewards); the ROM bytes are re-poked to shipped values
--            defensively in case a vanilla run preceded in this process.
--
-- Per sample: loadState -> poke arm -> seed $1fa1/$1fa2 -> pace until a
-- random encounter fires (steps counted) -> mash A (baseline policy) to
-- victory -> read the exp/gil the save data actually gained (character
-- exp $1611-13 delta, party gil $1860-62 delta -- ground truth, after
-- AddExp/gil clamps). Greppable lines: [ot6] [pace] b=<k> <key>=<value>.
--
-- ROM knob offsets are BUILD-SPECIFIC (bank F0 layout): derived from
-- ff6/rom/ff6-en.dbg for the build under test. The GUARD bytes below
-- fail the run loudly if the offsets drift.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

-- ------------------------------------------------------------- knobs --
local ARM = "vanilla"
local STATE = "/Users/mtklein/ot6/build/states/mines_chase.mss.lua"
local NSAMPLES = 8
local ROM_HPMUL  = 0x300173        -- Ot6HpMulTbl (band0 byte)
local ROM_DANGER = 0x300177        -- Ot6DangerMulW (word)
local ROM_REWARD = 0x300179        -- Ot6RewardMulW (word)
local SHIP = { hp = 0x20, danger = 0x08, reward = 0x20 }
local PACE_FRAMES = 9000
local BATTLE_FRAMES = 9000
-- $1fa1 spread (encounter-step roll) x $1fa2 (formation slot, the
-- bal_mines mix: slot0 Vaporite x2 / slot1 Were-Rat x2 / slot2/3
-- RepoMan+Vaporite). Same seeds both arms: paired samples.
local SEEDS = {
  { },                              -- natural state values
  { fa1 = 0x20, fa2 = 0x00 },
  { fa1 = 0x40, fa2 = 0x06 },
  { fa1 = 0x60, fa2 = 0x01 },
  { fa1 = 0x80, fa2 = 0x02 },
  { fa1 = 0xa0, fa2 = 0x03 },
  { fa1 = 0xc0, fa2 = 0x04 },
  { fa1 = 0xe0, fa2 = 0x0b },
}

-- --------------------------------------------------------- addresses --
local PHP   = 0x3bf4               -- party cur hp, +slot*2
local MHP   = 0x3bfc               -- monster cur hp, +slot*2
local ALIVE = 0x3aa8
local MSTAT = 0x3eec
local EXP0  = 0x1611               -- char 0 (Terra) exp, 3 bytes
local GIL0  = 0x1860               -- party gil, 3 bytes
local DANGER = 0x1f6e              -- random battle counter (word)

local function read24(a)
  return H.readByte(a) + (H.readByte(a+1) << 8) + (H.readByte(a+2) << 16)
end
local function monsterAlive(slot)
  return (H.readByte(ALIVE + slot*2) & 0x01) == 1
     and (H.readByte(MSTAT + slot*2) & 0xc2) == 0
end
local function calm(n)
  local cnt = 0
  return function()
    cnt = (H.hasControl() and H.tileAligned()) and cnt + 1 or 0
    return cnt >= n
  end
end
local function decodeName(addr, len)
  local s = ""
  for i = 0, len - 1 do
    local b = H.readByte(addr + i)
    if     b >= 0x80 and b <= 0x99 then s = s .. string.char(b - 0x80 + 65)
    elseif b == 0xFF then s = s .. " "
    else s = s .. "." end
  end
  return s
end

local function pokeArm()
  local hp, dg, rw
  if ARM == "vanilla" then hp, dg, rw = 0x10, 0x10, 0x10
  else hp, dg, rw = SHIP.hp, SHIP.danger, SHIP.reward end
  -- guard: the shipped bytes (or a prior poke of ours) must be at the
  -- documented offsets, or the .dbg-derived layout has drifted
  local seen = H.readRomByte(ROM_HPMUL)
  if seen ~= SHIP.hp and seen ~= 0x10 then
    error(string.format("knob layout drift: HpMulTbl byte $%02X", seen), 0)
  end
  emu.write(ROM_HPMUL,  hp, emu.memType.snesPrgRom)
  emu.write(ROM_DANGER, dg, emu.memType.snesPrgRom)
  emu.write(ROM_REWARD, rw, emu.memType.snesPrgRom)
  H.assertEq(H.readRomByte(ROM_HPMUL), hp, "hp knob poked")
  H.assertEq(H.readRomByte(ROM_DANGER), dg, "danger knob poked")
  H.assertEq(H.readRomByte(ROM_REWARD), rw, "reward knob poked")
end

-- ------------------------------------------------------------ report --
local B = 0
local function mline(k, v)
  H.log(string.format("[pace] b=%d %s=%s", B, k, tostring(v)))
end

-- ------------------------------------------------------- per sample --
local paceSteps, voidReason, exp0, gil0, dangerAfterStep
local fightT0, fightFrames, activeSeen

local function paceStep(k)
  local battN, evHold, waited, lastX = 0, 0, 0, nil
  return H.driveUntil(function()
    waited = waited + 1
    battN = H.battleLoadStarted() and battN + 1 or 0
    if battN >= 3 then H.setPad({}) return true end
    if H.eventRunning() or H.dialogWaiting() then
      evHold = evHold + 1
    elseif H.hasControl() then
      evHold = 0
    end
    if evHold >= 600 then voidReason = "event_no_battle" H.setPad({}) return true end
    if H.mapId() ~= 50 then voidReason = "left_map" H.setPad({}) return true end
    if waited >= PACE_FRAMES then voidReason = "pace_timeout" H.setPad({}) return true end
    return false
  end, PACE_FRAMES + 600, {
    H.call(function()
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      local x = H.fieldX()
      if lastX ~= nil and x ~= lastX then
        paceSteps = paceSteps + 1
        if paceSteps == 1 then dangerAfterStep = H.readWord(DANGER) end
      end
      lastX = x
      H.setPad({ [(x >= 78) and "left" or "right"] = true })
    end),
    H.waitFrames(1),
  }, "encounter fires (b=" .. k .. ")")
end

local function fightToVictory(k)
  local aPhase, done = 0, false
  return H.driveUntil(function()
    if not activeSeen and H.battleActive() then
      activeSeen = true
      fightT0 = H.frame
    end
    if activeSeen and fightFrames == nil then
      local aliveM, present = 0, false
      for slot = 0, 5 do
        if (H.readByte(ALIVE + slot*2) & 1) == 1 then present = true end
        if monsterAlive(slot) then aliveM = aliveM + 1 end
      end
      if present and aliveM == 0 then fightFrames = H.frame - fightT0 end
    end
    if not H.battleLoadStarted() then done = true end
    if H.frame - (fightT0 or H.frame) > BATTLE_FRAMES then
      voidReason = "battle_budget"
      done = true
    end
    if done then H.setPad({}) end
    return done
  end, BATTLE_FRAMES + 3000, {
    H.call(function()
      aPhase = (aPhase + 1) % 5
      H.setPad(aPhase == 0 and { "a" } or {})
    end),
    H.waitFrames(6),
  }, "fight resolved (b=" .. k .. ")")
end

local function seqStepList(steps)
  return {
    i = 1,
    tick = function(self)
      while self.i <= #steps do
        local r = steps[self.i]:tick()
        if r == "frame" then return "frame" end
        self.i = self.i + 1
      end
      return "done"
    end,
  }
end

local function sampleBlock(k)
  local seed = SEEDS[k] or {}
  return seqStepList({
    H.call(function()
      B = k
      paceSteps, voidReason, dangerAfterStep = 0, nil, nil
      fightT0, fightFrames, activeSeen = nil, nil, false
    end),
    H.loadState(STATE),
    H.waitFrames(10),
    H.waitUntil(calm(20), 1200, "field control (b=" .. k .. ")"),
    H.call(function()
      pokeArm()
      if k == 1 then
        mline("arm", ARM)
        mline("hero_name", decodeName(0x1602, 6))
      end
      exp0, gil0 = read24(EXP0), read24(GIL0)
      -- cold danger counter: the fixture carries ~$05B0 accumulated by
      -- the gen walk, and a warm counter near the roll threshold hides
      -- the rate knob (measured: paired steps came out identical).
      -- vanilla zeroes the counter at every battle trigger, so a cold
      -- start IS the steady-state inter-encounter interval.
      H.writeWord(DANGER, 0)
      if seed.fa1 then H.writeByte(0x1fa1, seed.fa1) end
      if seed.fa2 then H.writeByte(0x1fa2, seed.fa2) end
      mline("seed_1fa1", string.format("%02x", H.readByte(0x1fa1)))
      mline("seed_1fa2", string.format("%02x", H.readByte(0x1fa2)))
    end),
    paceStep(k),
    H.cond(function() return voidReason ~= nil end, {
      H.call(function()
        mline("void", voidReason)
        mline("steps", paceSteps)
      end),
    }, {
      H.call(function()
        mline("steps", paceSteps)
        mline("danger_after_step1", string.format("%04x", dangerAfterStep or 0))
      end),
      H.waitUntilSoft(function() return H.battleActive() end, 900,
        "active_b" .. k, 30),
      H.call(function()
        local sp = {}
        for slot = 0, 5 do
          local w = H.readWord(0x57c0 + slot*2)
          if w ~= 0xffff then sp[#sp+1] = string.format("%04X", w) end
        end
        mline("formation", table.concat(sp, ","))
        local hp = {}
        for slot = 0, 5 do
          if monsterAlive(slot) then
            hp[#hp+1] = string.format("s%d:%d", slot, H.readWord(MHP + slot*2))
          end
        end
        mline("monster_hp", table.concat(hp, ","))
        mline("rand_flag", H.readByte(0x57bd))
      end),
      fightToVictory(k),
      H.waitFrames(30),
      H.cond(function() return voidReason ~= nil end, {
        H.call(function() mline("void", voidReason) end),
      }, {
        H.call(function()
          mline("fight_frames", fightFrames or -1)
          mline("exp_gained", read24(EXP0) - exp0)
          mline("gil_gained", read24(GIL0) - gil0)
          mline("terra_hp_end", H.readWord(PHP))
        end),
      }),
    }),
  })
end

local blocks = {}
for k = 1, NSAMPLES do blocks[#blocks + 1] = sampleBlock(k) end
blocks[#blocks + 1] = H.call(function()
  H.log(string.format("[pace] run_done arm=%s samples=%d", ARM, NSAMPLES))
end)

H.run({ maxFrames = 200000 }, blocks)
