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
-- two weapons), so the signature must not leave that cut on a member it gives one weapon (G and S below).
--
-- Continue post-opera-v1.  Three seated members are picked from the save (S below): G holds a two-hand-capable weapon and D,
-- another, holds a weapon in the main hand and something else in the off hand, with a weapon D can wear in the bag.
-- G's off hand is emptied through Equip -> Rmove (play).  A snapshot there; then two branches from it, which differ
-- only in Crusader's count on G, D and S (staged, declared in state_write_waivers.txt: a signature takes 500 Magic
-- Points in one stone): 499 (rank 4: every rung but the signature, so the same stats and the same Red Cap) and 500.
-- In each, D's off hand is offered the bag's weapon through the Equip menu (play), then the branch walks into
-- random battles until G and D have each Fought (unboosted, through the real menu, the others Defending).  Every
-- physical damage pass of G's and D's is read at CalcDmg's end (Ot6BoostDmg's entry: before variance, defense and
-- boost, so it is a function of the attacker alone) with the hand that swung (Ot6WeaponClass, X odd for the off hand).
--   rank 4:  the menu refuses D's second weapon; D's Fight computes damage for the main hand only; G's swing has
--            no grip;
--   rank 5:  the menu takes it; D's Fight computes damage for both hands; G's swing has the grip, from the same
--            battle power, vigor and level, and more damage than rank 4's; and S, a third member holding a weapon
--            and a shield (the common kit), loses nothing to the signature.
-- Every claim is logged as ok or NOT before the verdict, so a red run names each one that fails.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM",
  "SETZER", "MOG", "GAU" }
local LIVE, CRUSADER = 0x317C00, 14
local CMD_FIGHT = 0x00
local function seated(c) local b = H.readByte(0x1850 + c); return b ~= 0 and (b & 7) == H.readByte(0x1A6D) end
local function stage(a, n)
  local addr = LIVE + 0x10 + (a * 26 + CRUSADER) * 2
  emu.write(addr, n & 0xFF, emu.memType.snesMemory)
  emu.write(addr + 1, n >> 8, emu.memType.snesMemory)
end
local IP
local function prop(item, off) return H.readRomByte(IP + item * 30 + off) end
local function wearable(item, c) return ((prop(item, 1) | (prop(item, 2) << 8)) >> c) & 1 == 1 end
local function slot(c, s) return H.readByte(0x1600 + 37 * c + 0x1F + s) end
local function hex(v) return string.format("$%02X", v) end

local G, D, W, S                      -- the grip member, the two-weapon member, the bag's weapon for D, and a
                                      -- member with a weapon and a shield
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
    if a == G or a == D or a == S then
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
    r.passes = { [G] = {}, [D] = {}, [S] = {} }
    cur = r
    stage(G, count)
    stage(D, count)
    stage(S, count)
    H.log(string.format("[crusader] %s: Crusader's count on %s, %s and %s staged at %d", name, NAMES[G], NAMES[D],
      NAMES[S], count))
  end)
  steps[#steps + 1] = H.equipWeapon(function() return (H.readByte(0x1850 + D) >> 3) & 3 end, W,
    { slot = 1, refusable = true, result = r.equip, tag = name .. ": " .. "D's off hand" })
  steps[#steps + 1] = H.call(function()
    r.offHand = slot(D, 1)
    H.log(string.format("[crusader] %s: %s's hands now %s / %s (the menu %s the %s)", name, NAMES[D],
      hex(slot(D, 0)), hex(r.offHand), r.equip.refused and "refused" or "took", hex(W)))
  end)
  local function all() return have(r, G) and have(r, D) and have(r, S) end
  steps[#steps + 1] = H.driveUntil(all, 300000, {
    open(name),
    H.call(function()
      r.battles = r.battles + 1
      H.assertEq(r.battles <= 6, true, name .. ": G, D and S have all Fought within six battles")
      seatRead(string.format("%s battle %d", name, r.battles))
    end),
    H.cond(function() return ent[G] ~= nil and ent[D] ~= nil and ent[S] ~= nil end, {
      H.kitBattle({ { who = G, cmd = CMD_FIGHT, boost = 0 }, { who = S, cmd = CMD_FIGHT, boost = 0 },
        { who = D, cmd = CMD_FIGHT, boost = 0 } },
        { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = all }),
      H.waitFrames(60),
    }, {}),
    H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(40000) }, {}),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 2),
    H.fieldCare({ tag = name .. ": care between battles" }),
  }, name .. ": G, S and D Fight")
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
    local m = {}
    for c = 0, 11 do if seated(c) then m[#m + 1] = c end end
    for _, c in ipairs(m) do
      H.log(string.format("[crusader] seated %s: hands %s / %s", NAMES[c], hex(slot(c, 0)), hex(slot(c, 1))))
    end
    -- G: a two-hand-capable weapon in the main hand
    for _, c in ipairs(m) do
      local w = slot(c, 0)
      if G == nil and H.isWeapon(w) and (prop(w, 19) & 0x40) ~= 0 and not H.isWeapon(slot(c, 1)) then G = c end
    end
    H.assertEq(G ~= nil, true, "a seated member holds a two-hand-capable weapon, one hand only")
    -- D: another, a weapon in the main hand and none in the off hand, and a weapon in the bag D can wear
    for _, c in ipairs(m) do
      if D == nil and c ~= G and H.isWeapon(slot(c, 0)) and not H.isWeapon(slot(c, 1)) then
        for i = 0, 255 do
          local it = H.readByte(0x1869 + i)
          if W == nil and it ~= 0xFF and H.readByte(0x1969 + i) > 0 and H.isWeapon(it) and wearable(it, c) then
            D, W = c, it
          end
        end
      end
    end
    H.assertEq(D ~= nil, true, "another seated member with one weapon and a weapon in the bag to wear")
    -- S: a third, a weapon in the main hand and a shield in the off hand (the common kit)
    for _, c in ipairs(m) do
      if S == nil and c ~= G and c ~= D and H.isWeapon(slot(c, 0)) and slot(c, 1) ~= 0xFF
          and (prop(slot(c, 1), 0) & 0x07) == 3 then S = c end
    end
    H.assertEq(S ~= nil, true, "a third seated member with a weapon and a shield")
    H.log(string.format("[crusader] G = %s (%s, weapon effects $%02X), D = %s (bag weapon %s), S = %s (%s / %s)",
      NAMES[G], hex(slot(G, 0)), prop(slot(G, 0), 19), NAMES[D], hex(W), NAMES[S], hex(slot(S, 0)), hex(slot(S, 1))))
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
      local p = { hand = lastHand[e], dmg = H.readWord(0x11B0), bp = H.readByte(0x11A6), vig = H.readByte(0x11AE),
        lvl = H.readByte(0x11AF), grip = (H.readByte(0xB3) & 0x40) == 0, genji = (H.readByte(0x3C58 + e) & 0x10) ~= 0 }
      table.insert(cur.passes[a], p)
      H.log(string.format("[crusader] %s: %s's damage pass, %s hand: battle power %d, vigor x2 %d, level %d, grip %s, "
        .. "Genji's one-weapon cut %s: damage before variance %d", cur.name, NAMES[a], p.hand == 1 and "off" or "main",
        p.bp, p.vig, p.lvl, tostring(p.grip), tostring(p.genji), p.dmg))
    end, emu.callbackType.exec, bd, bd)
  end),
  H.removeEquip(function() return G end, 1, { tag = "G's off hand" }),
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
    check(g5.dmg > g4.dmg, "rank 5: G's swing does more damage than rank 4's (the grip's bonus)")
    H.log(string.format("[crusader] S's damage before variance: rank 4 %d, rank 5 %d (x%.3f); Genji's one-weapon cut "
      .. "%s at rank 5", s4.dmg, s5.dmg, s5.dmg / math.max(1, s4.dmg), tostring(s5.genji)))
    check(s5.dmg >= s4.dmg, "rank 5: S's swing (a weapon and a shield) loses nothing to the signature")
    H.assertEq(#bad, 0, "Crusader's signature's claims that failed: " .. table.concat(bad, "; "))
  end),
  H.logStep("[crusader] PASS: Crusader's signature gives a second weapon in the menu and its swing in battle, and "
    .. "the two-handed grip with one hand empty"),
})
