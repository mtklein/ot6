-- @suite slow
-- battle_jackpot.lua -- SETZER's divine, Jackpot (#319, kits.md "Setzer"):
-- the Fixed Dice come up a triple, the boost floors the face, 99 MP, once a
-- battle, and no chip.
--
-- Played, not staged: Continue the wor-tomb-v1 battery (SETZER rejoined in
-- the World of Ruin: event switch $00CA, so Jackpot is learned), walk
-- Darill's Tomb's east room until the game deals a battle (field group
-- 151), and play SETZER's turns through the real menu (H.setzerBattle):
-- two Defends to bank three points, Jackpot at 3 BP, then Jackpot again,
-- which must be refused; a later battle (the first one's refusal may be
-- cut short by the kill) throws it at 1 BP.  Every assertion is derived
-- from the battle's own state, so any formation the room deals is a valid
-- draw; SETZER_SKIP (default 0) battles are fought out first to vary it.
--
-- What it holds, per Jackpot (at Ot6SetzerExec's entry and SETZER's
-- Ot6ActionEnd; the dice as the effect sets the dice animation):
--   * three dice of one face (b7 = face-1 in both nybbles, b6 = face-1),
--     the face at least 6 / 3 for 3 / 1 BP (the floor the boost buys);
--   * the damage set: face^3 x level x 2, times the face for the triple
--     (vanilla's Fixed Dice arithmetic), saturating at 65,535;
--   * the target's HP falls by that, halved while its shields hold, doubled
--     once Broken, capped at 9,999 and at the HP it had;
--   * null-break: the class is special | null-break ($88) and no monster's
--     shields move;
--   * 99 MP, no gil, the bank less the boost, and the once-a-battle flag
--     (OT6_DIVINE_USED) set for SETZER by it;
--   * a second Jackpot in the same battle is refused at the list (three A
--     presses, the list stays up), when the battle lasts that long.
-- Negative controls: the mutant ROMs in build/attempts/wt/kit-setzer/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

SETZER_SKIP = SETZER_SKIP or 0
local JACKPOT = 0x5B
local FLOOR = { [0] = 1, 3, 5, 6 }

local function walkToBattle()
  local wp = 1
  local WPS = { { 124, 26 }, { 120, 11 } }
  return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "a random battle in the east room")
end

local function checkJackpot(r, i, setzerBit)
  H.log(string.format("[jackpot] %d at %d BP, L%d: dice b6=%s b7=%s dmg %s class %s; MP %d -> %d, purse %d -> %d, "
    .. "bank %d -> %d, divine %02X -> %02X", i, r.boost, r.level, tostring(r.b6), tostring(r.b7), tostring(r.dmg),
    tostring(r.class), r.mp0, r.mp1, r.gil0, r.gil1, r.bank0, r.bank1, r.divine0, r.divine1))
  H.assertEq(r.b6 ~= nil, true, string.format("Jackpot %d set the dice animation", i))
  local f = r.b6 + 1
  H.assertEq(r.b7, (r.b6 << 4) | r.b6, string.format("Jackpot %d: three dice of one face", i))
  H.assertEq(f >= FLOOR[r.boost] and f <= 6, true,
    string.format("Jackpot %d: face %d at %d BP is at least %d", i, f, r.boost, FLOOR[r.boost]))
  local dmg = math.min(65535, f * f * f * r.level * 2 * f)
  H.assertEq(r.dmg, dmg, string.format("Jackpot %d: the triple's damage, face %d^4 x level %d x 2", i, f, r.level))
  H.assertEq(r.class, 0x88, string.format("Jackpot %d: special | null-break", i))
  H.assertEq(r.mp0 - r.mp1, 99, string.format("Jackpot %d: 99 MP", i))
  H.assertEq(r.gil1, r.gil0, string.format("Jackpot %d: no gil", i))
  H.assertEq(r.bank1, r.bank0 - r.boost, string.format("Jackpot %d: the bank less the boost", i))
  H.assertEq(r.divine0 & setzerBit, 0, string.format("Jackpot %d: unspent before", i))
  H.assertEq(r.divine1 & setzerBit, setzerBit, string.format("Jackpot %d: spent by it", i))
  local s = nil
  for b = 0, 5 do if (r.targets >> b) & 1 == 1 then H.assertEq(s, nil, "one target"); s = b end end
  H.assertEq(s ~= nil, true, string.format("Jackpot %d hit a monster", i))
  for b = 0, 5 do
    if r.mon0[b].present then
      H.assertEq(r.mon1[b].sh, r.mon0[b].sh, string.format("Jackpot %d: slot %d's shields do not move", i, b))
    end
  end
  local o, m = r.mon0[s], r.mon1[s]
  local d = dmg
  if o.brk == 0 and o.sh > 0 then d = (d * 8) >> 4 elseif o.brk ~= 0 and d < 32768 then d = d * 2 end
  d = math.min(d, 9999, o.hp)
  H.log(string.format("[jackpot]   slot %d: HP %d -> %d (want -%d), shields %d, broken %d", s, o.hp, m.hp, d,
    o.sh, o.brk))
  H.assertEq(o.hp - m.hp, d, string.format("Jackpot %d: the hit on slot %d", i, s))
end

-- battle 1: bank three, Jackpot at 3, then again (refused); battle 2: at 1
local PLANS = {
  { { row = "defend" }, { row = "defend" }, { row = JACKPOT, boost = 3 }, { row = JACKPOT, refused = true } },
  { { row = JACKPOT, boost = 1 }, { row = JACKPOT, refused = true } },
}
local jackpots, refusals, battles = {}, 0, 0
local planNow = nil
local setzerBit = nil

H.run({ maxFrames = 240000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    H.assertEq(H.readByte(0x1E99) & 0x04, 0x04, "SETZER has rejoined in the World of Ruin (switch $00CA)")
  end),
  H.repeatN(SETZER_SKIP, { walkToBattle(), H.setzerBattle({}) }),
  H.driveUntil(function() return #jackpots >= 2 and refusals >= 1 end, 200000, {
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= 3, true, string.format("two Jackpots and a refusal within three battles "
        .. "(%d Jackpot(s), %d refusal(s) so far)", #jackpots, refusals))
      local base = PLANS[math.min(battles, 2)]
      planNow = {}
      for _, p in ipairs(base) do
        local c = {}
        for kk, v in pairs(p) do c[kk] = v end
        planNow[#planNow + 1] = c
      end
    end),
    walkToBattle(),
    (function()
      local step
      return { tick = function()
        step = step or H.setzerBattle(planNow, { shot = "jackpot_table" })
        local r = step:tick()
        if r == "done" then
          for _, rec in ipairs(H.vars.setzer) do
            H.assertEq(rec.row, JACKPOT, "only Jackpots resolve from the plan")
            jackpots[#jackpots + 1] = rec
          end
          H.assertEq(#H.vars.setzer <= 1, true, "at most one Jackpot a battle")
          for _, p in ipairs(planNow) do if p.refusedSeen then refusals = refusals + 1 end end
          step = nil
        end
        return r
      end, reset = function() step = nil end }
    end)(),
  }, "two Jackpots and one refusal"),
  H.call(function()
    H.assertEq(#jackpots >= 2, true, "two Jackpots")
    H.assertEq(refusals >= 1, true, "a second Jackpot in a battle was refused at the list")
    for i, r in ipairs(jackpots) do
      checkJackpot(r, i, r.setzerBit)
    end
    H.assertEq(jackpots[1].boost, 3, "the first Jackpot ran at 3 BP")
    H.assertEq(jackpots[1].b6, 5, "...and 3 BP fixed sixes")
    H.log(string.format("[jackpot] PASSED: %d Jackpots, %d refusal(s), over %d battle(s)", #jackpots, refusals,
      battles))
  end),
})
