-- @suite slow
-- battle_economizer.lua -- the Economizer makes every spell its wearer casts cost 1 MP, at any boost (owner,
-- 2026-10-26: "economizer should make spells cost 1 MP").
--
-- Ot6MagicPrice prices every magic surface (the list's number, its grey, the confirm and the charge).  A
-- tier-family head folds and pays its tier's own price through Ot6SpellMP, which vanilla's relic arithmetic
-- already flattens to 1; everything else (Drain, Quake, a summon, a lore) took Ot6BoostPriceFor's x2.5 per
-- pending point on top of that 1, so a boosted Drain cost 3, 6 or 16.  The Economizer now answers first:
-- 1 MP whatever the boost (ot6_boost.asm, Ot6MagicPrice).
--
-- Played: Continue wor-colosseum-v1 (TERRA wears the Colosseum's Economizer, route-wor-colosseum.md section
-- 5), pace on the plain by Maranda's Falcon into a random battle, and cast through the real menu (H.kitBattle;
-- Defends bank the points, everyone else Defends):
--   1. Drain ($04, in no fold family: a multiplied cast) at 1 BP     -> 1 MP (main: 3)
--   2. Drain at 3 BP                                                 -> 1 MP (main: 16)
--   3. Fire ($00, a family head) at 2 BP, folded up two tiers        -> 1 MP (main: 1, Ot6SpellMP's)
--   4. Drain at 0 BP                                                 -> 1 MP (vanilla's rule)
-- Each cast's charge is the pool's own movement, attributed to the cast: the spell's $3410 write opens the
-- record (the pending boost and MP then), TERRA's Ot6ActionEnd closes it.  A battle where TERRA cannot cast
-- is fought out and the next one taken; a cast the battle's end cuts off, or one that charged nothing (it
-- did not resolve), is not counted.  Nothing is written.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CMD_MAGIC = 0x00, 0x02
local DRAIN, FIRE = 0x04, 0x00
local ECONOMIZER = 0xCE

local terraSeat, recs, rec = nil, {}, nil
local function arm()
  emu.addMemoryCallback(function(_, v)
    if terraSeat == nil or rec ~= nil or not (v == DRAIN or v == 0x00 or v == 0x05 or v == 0x09) then return end
    if H.readByte(0x3A7C) ~= CMD_MAGIC then return end
    local e = terraSeat * 2
    rec = { spell = v, pend = H.readByte(0x3E9D + e), mp0 = H.readWord(0x3C08 + e), f = H.frame }
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or terraSeat == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == terraSeat * 2 then rec.ended = H.frame end
  end, emu.callbackType.exec, ae, ae)
end
local function close()
  if rec == nil or not rec.ended or H.frame <= rec.ended + 1 then return false end
  rec.mp1 = H.readWord(0x3C08 + terraSeat * 2)
  recs[#recs + 1] = rec
  H.log(string.format("[econ] cast %d (f%d): spell $%02X at %d BP: MP %d -> %d", #recs, rec.f, rec.spell, rec.pend,
    rec.mp0, rec.mp1))
  rec = nil
  return true
end

local CASTS = {
  { spell = DRAIN, boost = 1, what = "Drain at 1 BP" },
  { spell = DRAIN, boost = 3, what = "Drain at 3 BP" },
  { spell = FIRE, boost = 2, what = "Fire at 2 BP (folded)" },
  { spell = DRAIN, boost = 0, what = "Drain at 0 BP" },
}
local nDone, cur, mode, nrec, turns = 0, nil, nil, 0, 0
local plan = {}
-- TERRA can cast: standing (no Wound, Petrify, Imp or Zombie) and not Mute, Sleep, Muddle or Berserk
local function terraCasts()
  local e = terraSeat * 2
  return H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and (H.readByte(0x3EE5 + e) & 0xB8) == 0
end
local function decide()
  turns = turns + 1
  H.assertEq(turns <= 16, true, "the four counted casts within 16 tries")
  terraSeat = nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then terraSeat = s end end
  H.assertEq(terraSeat ~= nil, true, "TERRA is seated")
  H.assertEq(H.readByte(0x3C45 + terraSeat * 2) & 0x40, 0x40,
    "TERRA's relic effects carry the Economizer ($3C45 bit $40)")
  plan, nrec, mode = {}, #recs, "cast"
  if not terraCasts() then
    mode = "fightout"
    H.log("[econ] TERRA cannot cast here: this battle is fought out and the next one taken")
    return
  end
  cur = CASTS[nDone + 1]
  H.log(string.format("[econ] %s; TERRA seat %d, MP %d, bank %d", cur.what, terraSeat,
    H.readWord(0x3C08 + terraSeat * 2), H.readByte(0x3E9C + terraSeat * 2)))
  plan = { { who = TERRA, cmd = CMD_MAGIC, spell = cur.spell, boost = cur.boost } }
end
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })

local A, B = nil, nil
local function pace(what)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, what),
    H.waitUntil(function() return H.battleActive() end, 1200, what .. ": the battle is up", 2),
  })
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("wor-colosseum-v1"),
  H.call(function()
    arm()
    H.assertEq(H.readByte(0x1850 + TERRA) & 7, 1, "TERRA is seated")
    H.assertEq(H.readByte(0x1600 + 37 * TERRA + 0x23) == ECONOMIZER or H.readByte(0x1600 + 37 * TERRA + 0x24)
      == ECONOMIZER, true, "TERRA wears the Economizer")
    for _, sp in ipairs({ DRAIN, FIRE }) do
      H.assertEq(H.readByte(0x1A6E + 54 * TERRA + sp), 0xFF, string.format("TERRA has learned spell $%02X", sp))
    end
    H.assertEq(H.inFoldTbl(DRAIN) and true or false, false, "Drain is in no fold family (a multiplied cast)")
    H.assertEq(H.inFoldTbl(FIRE) and true or false, true, "Fire heads a fold family")
    H.assertEq(H.worldMode(), true, "on the World of Ruin map")
    local x, y = H.worldX(), H.worldY()
    A = { x, y }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if B == nil and H.worldPassable(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(B ~= nil, true, "a passable tile beside the party")
  end),
  H.driveUntil(function() return nDone == #CASTS end, 500000, {
    H.cond(function() return not H.battleActive() end, { pace("a random battle on the plain by Maranda") }, {}),
    H.call(decide),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = close }),
      H.call(function()
        if #recs == nrec then
          H.log("[econ] the battle ended before the cast resolved: not counted")
          return
        end
        local r = recs[#recs]
        if r.mp0 == r.mp1 then
          H.log("[econ] the cast charged no MP (it did not resolve): not counted")
          return
        end
        H.assertEq(r.pend, cur.boost, string.format("%s: the cast ran at the %d BP planned", cur.what, cur.boost))
        H.assertEq(r.mp0 - r.mp1, 1, string.format("%s costs the Economizer's 1 MP", cur.what))
        nDone = nDone + 1
      end),
    }),
  }, "the four counted casts"),
  H.call(function()
    H.log("[econ] PASS: TERRA's Drain at 0, 1 and 3 BP and her Fire folded at 2 BP each cost 1 MP")
  end),
})
