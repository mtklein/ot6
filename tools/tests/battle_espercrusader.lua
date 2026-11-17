-- @suite slow
-- battle_espercrusader.lua -- Crusader's signature, the Gauntlet's two-handed grip and the Genji Glove's two
-- weapons with neither relic worn (#534; docs/design/esper-rework.md; ot6_esper.asm Ot6LadderTbl row 14, rung 5:
-- relic effects 4, $11D8, bits $08 and $10, folded into UpdateEquip by Ot6EsperFold), proved in the menu and in a
-- battle against the same members one rank short of it.
--
-- What the two bits do (vanilla, read off the ROM): the Genji bit lets the Equip menu put a weapon in the off hand
-- beside one in the main hand (CheckCanEquipItem); the battle then swings that hand too, because a hand swings when
-- it has battle power, not because of the bit.  The Gauntlet bit keeps a two-hand-capable weapon's grip ($40 in
-- ItemProp+19) when the other hand is empty (UpdateEquipBattle; Disable2Hand clears it otherwise), and the grip
-- raises the swing's battle power by 3/4 (CalcDmg: $B2 bit 14 clear).  A Genji bit left on a member who does not
-- hold two weapons also cuts the swing's damage by 1/4 (CalcDmg's $3C58 bit $10; UpdateEquip_03 clears it only for
-- two weapons).  The signature is a pure upgrade, so Ot6LadderGenji clears a Genji bit no worn gear carries before
-- the battle reads it; a real Genji Glove keeps vanilla's cut (#534: without the gate the grip holder's swing fell
-- x0.982 and a weapon-and-shield holder's x0.751, build/attempts/wt/v044-crusader/real_rom.log).
--
-- Continue post-opera-v1.  The gear is the suite's to have (#535): when no seated member wears a Genji Glove, or none
-- holds a two-hand-capable weapon, the bag's goes on through the Relic / Equip menus (H.equipKit under H.keepGear,
-- H.equipWeapon), and a save whose bag cannot supply one fails at that precondition, named.  Then four seated
-- members are picked: G holds a two-hand-capable weapon; D holds
-- a weapon in the main hand and none in the off hand, with a weapon D can wear in the bag; S holds a weapon and a
-- shield; J wears a real Genji Glove.  G's off hand, and J's if it holds anything, are emptied through Equip ->
-- Rmove (play).  A snapshot there; then two branches from it, which differ only in Crusader's count on all four
-- (staged, declared in state_write_waivers.txt: a signature takes 500 Magic Points in one stone): 499 (rank 4:
-- every rung but the signature, so the same stats and the same Red Cap) and 500.  In each, D's off hand is offered
-- the bag's weapon through the Equip menu (play), then the branch walks into random battles until all four have
-- Fought (unboosted, through the real menu).  Every physical damage pass of theirs is read at CalcDmg's end
-- (Ot6BoostDmg's entry: before variance, defense and boost, so it is a function of the attacker alone) with the hand
-- that swung (Ot6WeaponClass, X odd for the off hand).
--   rank 4:  the menu refuses D's second weapon; D's Fight computes damage for the main hand only; G's swing has
--            no grip; J's takes the real Glove's cut;
--   rank 5:  the menu takes it; D's Fight computes damage for both hands; G's swing has the grip and no cut, from
--            the same battle power, vigor and level, and more damage than rank 4's; S's swing takes no cut and
--            loses nothing; J's still takes the real Glove's cut.
-- J also holds Ragnarok (499 / 500): at rank 5 its Fight is one aimed hit and its vigor is rank 4's (#534: the
-- signature was the Offering's four strikes; then the Hyper Wrist's vigor x1.5; since #550 the Hero Ring, whose
-- Fight +1/4 is the Atlas bit, $3C44 bit 0, set at rank 5; its earring piece is battle_esperearring's).
-- Every claim is logged as ok or NOT before the verdict, so a red run names each one that fails.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM",
  "SETZER", "MOG", "GAU" }
local LIVE, CRUSADER, RAGNAROK = 0x317C00, 14, 15
local CMD_FIGHT = 0x00
local function seated(c) local b = H.readByte(0x1850 + c); return b ~= 0 and (b & 7) == H.readByte(0x1A6D) end
local function stage(a, n, stone)
  local addr = LIVE + 0x10 + (a * 26 + (stone or CRUSADER)) * 2
  emu.write(addr, n & 0xFF, emu.memType.snesMemory)
  emu.write(addr + 1, n >> 8, emu.memType.snesMemory)
end
local IP
local function prop(item, off) return H.readRomByte(IP + item * 30 + off) end
local function wearable(item, c) return ((prop(item, 1) | (prop(item, 2) << 8)) >> c) & 1 == 1 end
local function slot(c, s) return H.readByte(0x1600 + 37 * c + 0x1F + s) end
local function hex(v) return string.format("$%02X", v) end

-- Staging from the bag, through the menus (#535).  The save's play decides who wears what, so the suite puts the
-- Genji Glove and a two-hand-capable weapon on the party itself when no seated member has them, and fails with the
-- precondition named when the bag cannot supply them either.
local GENJI = 0xD1
local stage_ = {}                     -- { glove = { who, slot }, grip = { who, item } }, as planned
local function seatedList()
  local m = {}
  for c = 0, 11 do if seated(c) then m[#m + 1] = c end end
  return m
end
local function wearsGenji(c)
  for rs = 4, 5 do
    local it = slot(c, rs)
    if it ~= 0xFF and (prop(it, 12) & 0x10) ~= 0 then return true end
  end
  return false
end
-- J's Ragnarok claims (vigor unchanged, no Offering) are the signature's own only when no relic worn
-- already carries the Hyper Wrist's bit (ItemProp+11 $80) or the Offering's (+12 $01): a member wearing one has
-- them at rank 4 too (staged on SABIN, who wears a $D2: vigor 168 at both ranks, glove lab, crusader-v4-glove.log)
local function ragnarokClean(c)
  for rs = 4, 5 do
    local it = slot(c, rs)
    if it ~= 0xFF and ((prop(it, 11) & 0x80) ~= 0 or (prop(it, 12) & 0x01) ~= 0) then return false end
  end
  return true
end
local function twoHand(w) return H.isWeapon(w) and (prop(w, 19) & 0x40) ~= 0 end
local function hasShield(c) return slot(c, 1) ~= 0xFF and (prop(slot(c, 1), 0) & 0x07) == 3 end

local function planGlove()
  IP = IP or (H.sym("ItemProp") & 0x3FFFFF)
  stage_ = {}
  local m = seatedList()
  for _, c in ipairs(m) do
    if wearsGenji(c) and H.isWeapon(slot(c, 0)) then return end
  end
  H.assertEq(H.invCountOf(GENJI) > 0, true, "precondition: a seated member wears a Genji Glove, or the bag holds "
    .. "one to put on (the save supplies neither)")
  -- X: a seated member with a weapon in the main hand and no relic that already carries Ragnarok's bits (J's
  -- claims are about them); one that is no shield-bearer first (the shield-bearer is S's to be), and one without
  -- a two-hand-capable weapon (G's to be)
  local best, bestScore
  for _, c in ipairs(m) do
    if H.isWeapon(slot(c, 0)) then
      local score = (hasShield(c) and 0 or 2) + (twoHand(slot(c, 0)) and 0 or 1)
        + (ragnarokClean(c) and 8 or 0)
      if bestScore == nil or score > bestScore then best, bestScore = c, score end
    end
  end
  H.assertEq(best ~= nil, true, "precondition: a seated member holds a weapon to wear the Genji Glove beside")
  stage_.glove = { who = best, slot = (slot(best, 4) == 0xFF) and 4 or 5 }
end

local function planGrip()
  stage_.grip = nil
  local m = seatedList()
  for _, c in ipairs(m) do
    if twoHand(slot(c, 0)) and not H.isWeapon(slot(c, 1)) then return end
  end
  -- Y: a seated member with no weapon in the off hand to hold it: one with an empty main hand first (the save
  -- left him unarmed), else one holding another weapon, which goes back to the bag
  local best
  for _, pass in ipairs({ "empty", "armed" }) do
    for _, c in ipairs(m) do
      local armed = H.isWeapon(slot(c, 0))
      if best == nil and (pass == "armed") == armed and not H.isWeapon(slot(c, 1)) and not wearsGenji(c)
          and not (stage_.glove and stage_.glove.who == c) then
        for i = 0, 255 do
          local it = H.readByte(0x1869 + i)
          if best == nil and it ~= 0xFF and H.readByte(0x1969 + i) > 0 and twoHand(it) and wearable(it, c) then
            best = { who = c, item = it }
          end
        end
      end
    end
  end
  H.assertEq(best ~= nil, true, "precondition: a seated member holds a two-hand-capable weapon (ItemProp+19 bit "
    .. "$40), or the bag holds one that a seated member with a weapon and an empty or shield off hand can wield "
    .. "(the save supplies neither)")
  stage_.grip = best
end

local G, D, W, S, J                   -- the grip member, the two-weapon member, the bag's weapon for D, a member
                                      -- with a weapon and a shield, and one wearing a real Genji Glove
local snap
local A, B = nil, nil                 -- two plain tiles that roll random battles
local cur                             -- the branch being recorded
local ent = {}                        -- actor -> battle entity offset, this battle
local lastHand, armed = {}, nil

local function open(tag)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 1),
    H.waitFrames(30),
  })
end

local function seatRead(tag)
  ent = {}
  for s = 0, 3 do
    local a = H.readByte(0x3ED8 + s * 2)
    if a == G or a == D or a == S or a == J then
      local e = s * 2
      ent[a] = e
      H.log(string.format("[crusader] %s: %s seat %d: battle power main %d off %d, weapon effects main $%02X off "
        .. "$%02X, relic effects 4 $%02X", tag, NAMES[a], s, H.readByte(0x3B68 + e), H.readByte(0x3B69 + e),
        H.readByte(0x3BA4 + e), H.readByte(0x3BA5 + e), H.readByte(0x3C58 + e)))
    end
  end
end

local function have(r, a) return #r.passes[a] > 0 end

-- One branch: stage Crusader's count, offer D the second weapon, then battles until G and D have both Fought.
local function branch(name, count, restore)
  local r = { name = name, count = count, equip = {}, passes = { [G or 0] = {} }, battles = 0 }
  local steps = {}
  if restore then
    local req
    steps[#steps + 1] = H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end)
    steps[#steps + 1] = H.waitFrames(2)
    steps[#steps + 1] = H.call(function() H.checkReq(req, "the snapshot after G's Rmove"); H.rearmInputInjection() end)
  end
  steps[#steps + 1] = H.call(function()
    r.passes = { [G] = {}, [D] = {}, [S] = {}, [J] = {} }
    cur = r
    for _, c in ipairs({ G, D, S, J }) do stage(c, count) end
    stage(J, count, RAGNAROK)
    H.log(string.format("[crusader] %s: Crusader's count on %s, %s, %s and %s, and Ragnarok's on %s, staged at %d",
      name, NAMES[G], NAMES[D], NAMES[S], NAMES[J], NAMES[J], count))
  end)
  steps[#steps + 1] = H.equipWeapon(function() return (H.readByte(0x1850 + D) >> 3) & 3 end, W,
    { slot = 1, refusable = true, result = r.equip, tag = name .. ": " .. "D's off hand" })
  steps[#steps + 1] = H.call(function()
    r.offHand = slot(D, 1)
    H.log(string.format("[crusader] %s: %s's hands now %s / %s (the menu %s the %s)", name, NAMES[D],
      hex(slot(D, 0)), hex(r.offHand), r.equip.refused and "refused" or "took", hex(W)))
  end)
  -- D is done when its second swing has been computed too, if the menu gave it one: the plan used to end on D's
  -- main-hand pass, and on draws where that came last the off hand's never ran (seed shifts 12, 16 and 20,
  -- build/attempts/wt/polish-suites/crusader-old-s12.log)
  local function dDone()
    if r.offHand ~= W then return have(r, D) end
    for _, p in ipairs(r.passes[D]) do if p.hand == 1 then return true end end
    return false
  end
  local function all() return have(r, G) and dDone() and have(r, S) and have(r, J) end
  steps[#steps + 1] = H.driveUntil(all, 300000, {
    open(name),
    H.call(function()
      r.battles = r.battles + 1
      H.assertEq(r.battles <= 6, true, name .. ": G, D, S and J have all Fought within six battles")
      seatRead(string.format("%s battle %d", name, r.battles))
    end),
    H.cond(function() return ent[G] ~= nil and ent[D] ~= nil and ent[S] ~= nil and ent[J] ~= nil end, {
      H.kitBattle({ { who = G, cmd = CMD_FIGHT, boost = 0 }, { who = S, cmd = CMD_FIGHT, boost = 0 },
        { who = J, cmd = CMD_FIGHT, boost = 0 }, { who = D, cmd = CMD_FIGHT, boost = 0 } },
        { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = all }),
      H.waitFrames(60),
    }, {}),
    H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(40000) }, {}),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 2),
    H.fieldCare({ tag = name .. ": care between battles" }),
  }, name .. ": G, S, J and D Fight")
  steps[#steps + 1] = H.call(function() cur = nil end)
  return r, H.seqStep(steps)
end

local R4, R5, steps4, steps5

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("post-opera-v1"),
  H.call(function()
    IP = H.sym("ItemProp") & 0x3FFFFF
    H.assertEq(emu.read(LIVE, emu.memType.snesMemory) | (emu.read(LIVE + 1, emu.memType.snesMemory) << 8), 0x3145,
      "the live esper page is signed ('E1', ot6_esper.asm OT6_ESPER_MAGIC_WORD)")
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A = { x, y }
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(plain(x, y) and B ~= nil, true, "two plain tiles that roll random battles")

    -- the observers: the hand of each swing, and each physical damage pass's numbers at CalcDmg's end
    local wc, cd, bd = H.sym("Ot6WeaponClass"), H.sym("CalcDmg"), H.sym("Ot6BoostDmg")
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xFFFF
      if x < 8 then lastHand[x & 0xFFFE] = x & 1 end
    end, emu.callbackType.exec, wc, wc)
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xFF
      armed = (x < 8 and (H.readByte(0x11A2) & 1) == 1) and x or nil
    end, emu.callbackType.exec, cd, cd)
    emu.addMemoryCallback(function()
      local e = armed
      armed = nil
      if e == nil or cur == nil then return end
      local a = H.readByte(0x3ED8 + e)
      if cur.passes[a] == nil then return end
      -- a Fight's pass only: an item or a physical spell also runs CalcDmg (#534 round 1: a pass with battle
      -- power 0 was recorded for the two-weapon member before his Fight, and ended the plan early)
      if H.readByte(0x3A7C) ~= CMD_FIGHT then return end
      -- each member's first Fight only: a pass from another member closes the one before it, so the fight-out's
      -- later Fights never add to a count
      if cur.last ~= nil and cur.last ~= a then cur.closed = cur.closed or {}; cur.closed[cur.last] = true end
      cur.last = a
      if cur.closed and cur.closed[a] then return end
      local p = { hand = lastHand[e], dmg = H.readWord(0x11B0), bp = H.readByte(0x11A6), vig = H.readByte(0x11AE),
        lvl = H.readByte(0x11AF), grip = (H.readByte(0xB3) & 0x40) == 0, genji = (H.readByte(0x3C58 + e) & 0x10) ~= 0,
        offering = (H.readByte(0x3C58 + e) & 0x01) ~= 0, swings = H.readByte(0x3A70),
        atlas = (H.readByte(0x3C44 + e) & 0x01) ~= 0 }
      table.insert(cur.passes[a], p)
      H.log(string.format("[crusader] %s: %s's damage pass, %s hand: battle power %d, vigor x2 %d, level %d, grip %s, "
        .. "Genji's one-weapon cut %s: damage before variance %d", cur.name, NAMES[a], p.hand == 1 and "off" or "main",
        p.bp, p.vig, p.lvl, tostring(p.grip), tostring(p.genji), p.dmg))
    end, emu.callbackType.exec, bd, bd)
  end),
  -- The gear this suite needs is the party's to have, not the save's: a Genji Glove worn by a member holding a
  -- weapon (J) and a two-hand-capable weapon in a member's main hand (G).  When the save's play left them in the
  -- bag instead (it wears whatever the route's Optimum chose), they go on through the menus, as a player would.
  H.call(function() planGlove() end),
  H.lazy(function()
    if not stage_.glove then return H.logStep("[crusader] a seated member already wears a Genji Glove") end
    local label = string.format("staging the Genji Glove on %s", NAMES[stage_.glove.who])
    H.log("[crusader] " .. label .. " (the save has no seated member wearing one; the bag holds it)")
    return H.keepGear(stage_.glove.who, label, H.equipKit(stage_.glove.who, { { stage_.glove.slot, GENJI } },
      { tag = label }))
  end),
  H.call(function()
    if stage_.glove then
      H.assertEq(slot(stage_.glove.who, stage_.glove.slot), GENJI, "the Genji Glove is worn on " ..
        NAMES[stage_.glove.who])
    end
    planGrip()
  end),
  H.lazy(function()
    if not stage_.grip then return H.logStep("[crusader] a seated member already holds a two-hand-capable weapon") end
    local label = string.format("staging %s (a two-hand-capable weapon) in %s's main hand", hex(stage_.grip.item),
      NAMES[stage_.grip.who])
    H.log("[crusader] " .. label .. " (no seated member holds one; the bag does)")
    return H.equipWeapon(function() return (H.readByte(0x1850 + stage_.grip.who) >> 3) & 3 end, stage_.grip.item,
      { slot = 0, tag = label })
  end),
  H.call(function()
    local m = seatedList()
    for _, c in ipairs(m) do
      H.log(string.format("[crusader] seated %s: hands %s / %s, relics %s %s", NAMES[c], hex(slot(c, 0)),
        hex(slot(c, 1)), hex(slot(c, 4)), hex(slot(c, 5))))
    end
    -- J: wearing a real Genji Glove (a relic whose ItemProp+12 carries $10), a weapon in the main hand; picked first,
    -- as the staged Glove's wearer is the one member the others must not take
    for _, c in ipairs(m) do
      if J == nil and H.isWeapon(slot(c, 0)) and wearsGenji(c) then J = c end
    end
    H.assertEq(J ~= nil, true, "precondition: a seated member wearing a real Genji Glove, a weapon in the main hand")
    H.assertEq(ragnarokClean(J), true, "precondition: J wears no relic carrying the Hyper Wrist's or the Offering's "
      .. "bit (they would be J's at rank 4 too)")
    -- G: another, a two-hand-capable weapon in the main hand
    for _, c in ipairs(m) do
      local w = slot(c, 0)
      if G == nil and c ~= J and twoHand(w) and not H.isWeapon(slot(c, 1)) then G = c end
    end
    H.assertEq(G ~= nil, true, "precondition: a seated member besides J holds a two-hand-capable weapon, one hand only")
    -- D: another, a weapon in the main hand and none in the off hand, and a weapon in the bag D can wear
    for _, c in ipairs(m) do
      if D == nil and c ~= G and c ~= J and H.isWeapon(slot(c, 0)) and not H.isWeapon(slot(c, 1)) then
        for i = 0, 255 do
          local it = H.readByte(0x1869 + i)
          if W == nil and it ~= 0xFF and H.readByte(0x1969 + i) > 0 and H.isWeapon(it) and wearable(it, c) then
            D, W = c, it
          end
        end
      end
    end
    H.assertEq(D ~= nil, true, "precondition: another seated member with one weapon and a weapon in the bag to wear")
    -- S: a fourth, a weapon in the main hand and a shield in the off hand (the common kit)
    for _, c in ipairs(m) do
      if S == nil and c ~= G and c ~= D and c ~= J and H.isWeapon(slot(c, 0)) and hasShield(c) then S = c end
    end
    H.assertEq(S ~= nil, true, "precondition: a fourth seated member with a weapon and a shield")
    H.log(string.format("[crusader] J = %s (%s / %s, relics %s %s)", NAMES[J], hex(slot(J, 0)), hex(slot(J, 1)),
      hex(slot(J, 4)), hex(slot(J, 5))))
    H.log(string.format("[crusader] G = %s (%s, weapon effects $%02X), D = %s (bag weapon %s), S = %s (%s / %s)",
      NAMES[G], hex(slot(G, 0)), prop(slot(G, 0), 19), NAMES[D], hex(W), NAMES[S], hex(slot(S, 0)), hex(slot(S, 1))))
  end),
  H.removeEquip(function() return G end, 1, { tag = "G's off hand" }),
  -- J keeps one weapon only, so the real Glove's vanilla cut applies
  H.cond(function() return slot(J, 1) ~= 0xFF end, { H.removeEquip(function() return J end, 1, { tag = "J's off hand" }) }, {}),
  H.call(function() H.setPad({}); snap = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(snap, "the snapshot after G's Rmove")
    R4, steps4 = branch("rank 4", 499, false)
    R5, steps5 = branch("rank 5", 500, true)
  end),
  H.lazy(function() return steps4 end),
  H.lazy(function() return steps5 end),
  H.call(function()
    local function hands(r, a)
      local t = { [0] = 0, [1] = 0 }
      for _, p in ipairs(r.passes[a]) do t[p.hand or 0] = t[p.hand or 0] + 1 end
      return t
    end
    -- every claim is checked and logged before the verdict, so one red run names all that fail
    local bad = {}
    local function check(ok, what)
      H.log(string.format("[crusader] %s: %s", ok and "ok" or "NOT", what))
      if not ok then bad[#bad + 1] = what end
    end
    -- the menu
    check(R4.equip.refused == true and R4.offHand ~= W, "rank 4: the Equip menu refuses D's second weapon")
    check(R5.equip.refused == false and R5.offHand == W, "rank 5: the Equip menu takes D's second weapon")
    -- D's Fight: the second swing
    local h4, h5 = hands(R4, D), hands(R5, D)
    H.log(string.format("[crusader] D's damage passes: rank 4 main %d off %d; rank 5 main %d off %d",
      h4[0], h4[1], h5[0], h5[1]))
    check(h4[0] >= 1 and h4[1] == 0, "rank 4: D's Fight computes damage for the main hand only")
    check(h5[0] >= 1 and h5[1] >= 1, "rank 5: D's Fight computes damage for both hands (the second swing)")
    -- G's Fight: the grip; S's: a weapon and a shield
    local function same(a, b) return a.bp == b.bp and a.vig == b.vig and a.lvl == b.lvl end
    local g4, g5, s4, s5 = R4.passes[G][1], R5.passes[G][1], R4.passes[S][1], R5.passes[S][1]
    H.assertEq(same(g4, g5) and same(s4, s5), true,
      "G and S each swing from the same battle power, vigor and level at rank 4 and rank 5")
    check(not g4.grip, "rank 4: G's swing has no two-handed grip")
    check(g5.grip, "rank 5: G's swing has the two-handed grip (the Gauntlet's bit, one hand empty)")
    H.log(string.format("[crusader] G's damage before variance: rank 4 %d, rank 5 %d (x%.3f); grip %s, Genji's "
      .. "one-weapon cut %s at rank 5", g4.dmg, g5.dmg, g5.dmg / math.max(1, g4.dmg), tostring(g5.grip),
      tostring(g5.genji)))
    check(not g5.genji, "rank 5: G's swing takes no one-weapon cut (the Genji bit is the ladder's alone)")
    check(g5.dmg > g4.dmg, "rank 5: G's swing does more damage than rank 4's (the grip's bonus)")
    H.log(string.format("[crusader] S's damage before variance: rank 4 %d, rank 5 %d (x%.3f); Genji's one-weapon cut "
      .. "%s at rank 5", s4.dmg, s5.dmg, s5.dmg / math.max(1, s4.dmg), tostring(s5.genji)))
    check(not s5.genji, "rank 5: S's swing takes no one-weapon cut (the Genji bit is the ladder's alone)")
    check(s5.dmg >= s4.dmg, "rank 5: S's swing (a weapon and a shield) loses nothing to the signature")
    -- J: the real Genji Glove and one weapon keep vanilla's cut at both ranks
    local j4, j5 = R4.passes[J][1], R5.passes[J][1]
    H.assertEq(j4.bp == j5.bp and j4.lvl == j5.lvl, true, "J swings from the same battle power and level at rank 4 and rank 5")
    H.log(string.format("[crusader] J's damage before variance: rank 4 %d (cut %s, grip %s), rank 5 %d (cut %s, grip %s)",
      j4.dmg, tostring(j4.genji), tostring(j4.grip), j5.dmg, tostring(j5.genji), tostring(j5.grip)))
    check(j4.genji, "rank 4: J's swing takes the real Genji Glove's one-weapon cut (vanilla)")
    check(j5.genji, "rank 5: J's swing still takes the real Genji Glove's one-weapon cut (vanilla)")
    -- J also holds Ragnarok (499 / 500): its signature is the Hero Ring (#550), one aimed hit, no Offering, and no
    -- Hyper Wrist's vigor x1.5 (the signature before #550)
    local hj4, hj5 = hands(R4, J), hands(R5, J)
    H.log(string.format("[crusader] J's Ragnarok: vigor x2 rank 4 %d, rank 5 %d; atlas bit rank 4 %s, rank 5 %s; "
      .. "damage passes rank 4 %d/%d, rank 5 %d/%d (main/off); Offering's bit rank 5 %s", j4.vig, j5.vig,
      tostring(j4.atlas), tostring(j5.atlas), hj4[0], hj4[1], hj5[0], hj5[1], tostring(j5.offering)))
    check(j5.vig == j4.vig, "rank 5: J's vigor is rank 4's (no Hyper Wrist since #550)")
    check(j5.atlas, "rank 5: J holds the Atlas bit (Ragnarok's signature, the Hero Ring's Fight +1/4)")
    check(not j5.offering and hj5[0] == 1 and hj5[1] == 0,
      "rank 5: J's Fight is one hit, aimed (no Offering: no four strikes, no random target)")
    H.assertEq(#bad, 0, "Crusader's signature's claims that failed: " .. table.concat(bad, "; "))
  end),
  H.logStep("[crusader] PASS: Crusader's signature gives a second weapon in the menu and its swing in battle, and "
    .. "the two-handed grip with one hand empty, with no one-weapon cut; a real Genji Glove keeps vanilla's"),
})
