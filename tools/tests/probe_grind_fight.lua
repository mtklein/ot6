-- probe_grind_fight.lua -- one Chimera-pocket fight.
--
-- From wob_grind.mss (party on foot at world (116,25), the decoded grind
-- pocket), pace until a random encounter fires and fight it with the
-- tactical driver, then report XP/level/HP deltas.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end

local CHAR, REC = 0x1600, 37
local function party()
  local out = {}
  for slot = 0, 5 do
    local base = CHAR + slot * REC
    local hp = H.readWord(base + 9)
    local actor = H.readByte(base)
    if actor < 16 and hp > 0 then
      out[#out + 1] = { slot = slot, actor = actor,
        level = H.readByte(base + 8), hp = hp,
        maxhp = H.readWord(base + 0xb),
        xp = H.readByte(base + 0x11) | (H.readByte(base + 0x12) << 8)
             | (H.readByte(base + 0x13) << 16) }
    end
  end
  return out
end
local function logParty(tag, ps)
  for _, c in ipairs(ps) do
    H.log(string.format("  %s slot%d actor%02d L%d hp=%d/%d xp=%d",
      tag, c.slot, c.actor, c.level, c.hp, c.maxhp, c.xp))
  end
end

local before = nil
local tactical = H.newFightDriver("grind_fight",
  { tactical = true, boost = true, items = true, healPercent = 55 })
local paceDir = "left"
local battN, sawBattle, fought = 0, false, false
local function frame()
  battN = H.battleLoadStarted() and battN + 1 or 0
  if battN == 0 then tactical.idle() end
  if battN >= 3 then
    sawBattle = true
    if battN == 3 then
      local w = H.formationWords()
      H.log(string.format("fight up: species %04X %04X %04X %04X %04X %04X",
        w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    tactical.frame()
    return
  end
  if sawBattle and battN == 0 and H.worldHasControl() then
    fought = true
    H.setPad({})
    return
  end
  if not H.worldHasControl() then H.setPad({}); return end
  local x = H.worldX()
  if x <= 114 then paceDir = "right" elseif x >= 118 then paceDir = "left" end
  H.setPad({ [paceDir] = true })
end

H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/wob_grind.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    before = party()
    logParty("before", before)
  end),
  H.driveUntil(function() return fought end, 28000,
    { H.call(frame) }, "one pocket encounter fought tactically"),
  H.waitFrames(30),
  H.call(function()
    local after = party()
    logParty("after ", after)
    local dxp = 0
    if before and before[1] and after[1] then dxp = after[1].xp - before[1].xp end
    H.log(string.format("RESULT xp-gain(slot %d)=%d survivors=%d/%d",
      after[1] and after[1].slot or -1, dxp, #after, #before))
    H.screenshot("grind_fight_done")
  end),
  H.logStep(function() return "done" end),
})
