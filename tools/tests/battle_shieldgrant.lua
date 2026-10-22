-- @suite slow
-- battle_shieldgrant.lua -- the elemental shields grant their family's base
-- spell while worn, as an equipped esper grants its spells (#431): the Flame
-- Shld Fire, the Ice Shld Ice, the Thunder Shld Bolt (Ot6ItemGrantTbl,
-- battle/ot6_progression.asm).  Never learned: off again, the spell is gone.
--
-- Played: Continue the wor-cyan-v1 battery (World of Ruin, beside Jidoor; the
-- bag holds an Ice Shld and a Thunder Shld).  The wearer and the shield are
-- chosen from the live save: the first party member (in party order) who can
-- wear a granting shield from the bag (ItemProp's equip mask), whose left
-- hand holds some other shield to change back to, and who has the spell
-- neither learned nor from the stone they wear.  Through the real menus only,
-- nothing written:
--   A. the spell is absent from that member's field Magic list;
--   B. Equip puts the shield in the left hand: the spell is in the field
--      Magic list (an attack spell: drawn as the field draws one it cannot
--      cast there), and the learned table still lacks it;
--   C. a random battle on the world map: the spell has a cell in the
--      member's battle Magic list, and the member casts it through the Magic
--      menu at a monster, at its base tier (no boost), paying its MP;
--   D. Equip puts the old shield back: the spell is gone from the field
--      Magic list again, and neither it nor its tiers were learned or
--      began to be (the wearer's learned bytes for the family unchanged:
--      vanilla's shields taught the tier after each battle).
-- Old-ROM red and a mutant: build/attempts/wt/v029-shield-grants/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local GRANTS = { { 0x60, 0x00, "Flame Shld", "Fire" }, { 0x61, 0x01, "Ice Shld", "Ice" },
                 { 0x62, 0x02, "Thunder Shld", "Bolt" } }
local LHAND = 1                                  -- equip slot (R-Hand 0, L-Hand 1)
local CMD_MAGIC = 0x02
local ZM, CUR = 0x26, 0x4B
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_MAGIC = 0x05, 0x06, 0x0A, 0x1A
local MAGIC_LIST, MAGIC_COLOUR = 0x9D89, 0x9E09
local ITEMPROP = H.sym("ItemProp") & 0x3FFFFF
local GENJUPROP = H.sym("GenjuProp") & 0x3FFFFF

local who, shield, spell, sname, iname, oldShield, pos
local function st() return H.readByte(ZM) end
local function rec(o) return H.readByte(0x1600 + 37 * who + o) end
local function learned() return H.readByte(0x1A6E + 54 * H.charActor(who) + spell) end
local function stoneGrants(c, sp)
  local e = H.readByte(0x1600 + 37 * c + 0x1E)
  if e >= 0x80 then return false end
  for _, off in ipairs({ 1, 3, 5, 7, 9 }) do
    if H.readRomByte(GENJUPROP + 11 * e + off) == sp then return true end
  end
  return false
end
-- the wearer's learned-table bytes for the spell's whole family (its
-- Ot6FoldTbl row: the base and the tiers boost folds it to).  Vanilla's
-- shields taught the tier (Ice 2 at learn rate 5, after each battle), which
-- these bytes show; natural magic, which a level-up can add, holds no family
-- member the wearer lacks (choose() and check_spell_grants)
local family
local function familyBytes()
  local fold, row = H.sym("Ot6FoldTbl") & 0x3FFFFF, nil
  for r = 0, 15 do
    if H.readRomByte(fold + 3 * r) == spell then row = r; break end
  end
  H.assertEq(row ~= nil, true, string.format("Ot6FoldTbl has a row headed by $%02X", spell))
  local out = {}
  for k = 0, 2 do
    local id = H.readRomByte(fold + 3 * row + k)
    out[#out + 1] = string.format("$%02X=%02X", id, H.readByte(0x1A6E + 54 * H.charActor(who) + id))
  end
  return table.concat(out, " ")
end
local function isGrantShield(id)
  for _, g in ipairs(GRANTS) do if g[1] == id then return true end end
  return false
end

local function choose()
  local seen = {}
  for _, c in ipairs(H.partyMembers()) do
    local actor = H.charActor(c)
    local lh = H.readByte(0x1600 + 37 * c + 0x1F + LHAND)
    for _, g in ipairs(GRANTS) do
      local mask = H.readRomWord(ITEMPROP + 30 * g[1] + 1)
      local wears = (mask >> c) & 1 == 1
      local knows = H.readByte(0x1A6E + 54 * actor + g[2]) == 0xFF or stoneGrants(c, g[2])
      local otherShield = lh ~= 0xFF and not isGrantShield(lh)
        and (H.readRomByte(ITEMPROP + 30 * lh) & 0x07) == 0x03   -- ItemProp+0 type 3: a shield
      seen[#seen + 1] = string.format("char %d %s: bag %d, wears %s, knows %s, L-hand $%02X", c, g[3],
        H.invCountOf(g[1]), tostring(wears), tostring(knows), lh)
      if actor < 0x0C and H.invCountOf(g[1]) > 0 and wears and not knows and otherShield then
        who, shield, spell, iname, sname, oldShield = c, g[1], g[2], g[3], g[4], lh
        local pb = H.readByte(0x1850 + c)
        pos = (pb >> 3) & 0x03
        H.log(string.format("[shield] wearer char %d (party row %d), %s ($%02X) -> %s ($%02X); "
          .. "left hand holds $%02X", who, pos, iname, shield, sname, spell, oldShield))
        return
      end
    end
  end
  for _, s in ipairs(seen) do H.log("[shield] candidate " .. s) end
  error("no party member can wear a granting shield from the bag over another shield "
    .. "without already having its spell (candidates above)", 0)
end

local function openMagic(tag)
  return H.seqStep({
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, tag .. ": main menu"),
    H.waitFrames(20),
    H.driveUntil(function() return st() == ST_MAIN and H.readByte(CUR) == 1 end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(10) }, tag .. ": cursor on Skills"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300, tag .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function() return st() == ST_CHAR and H.readByte(CUR) == pos end, 600,
      { H.pressButtons({ "down" }, 2), H.waitFrames(10) }, tag .. ": cursor on the wearer"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_SKILLS end, 300, tag .. ": skills submenu", 5),
    H.waitFrames(10),
    H.driveUntil(function() return st() == ST_SKILLS and H.readByte(CUR) == 1 end, 600,
      { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, tag .. ": cursor on Magic"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_MAGIC end, 500, tag .. ": magic list", 5),
    H.waitFrames(120),
  })
end
local function closeMenu(tag)
  return H.seqStep({
    H.driveUntil(function()
      if H.worldMode() then return st() ~= ST_MAGIC and H.worldHasControl() and H.worldSettled() end
      return H.hasControl() and not H.dialogWaiting()
    end, 1500,
      { H.pressButtons({ "b" }, 3), H.waitFrames(20) }, tag .. ": menu closed"),
    H.waitFrames(30),
  })
end
local function fieldIndex()
  for i = 0, 0x35 do
    if H.readByte(MAGIC_LIST + i) == spell then return i end
  end
  return nil
end

-- the battle: every $3410 write of the spell (the spell an attack pass uses)
-- under the Magic command, with its targets and the wearer's MP then
local casts, slot = {}, nil
local function arm()
  emu.addMemoryCallback(function(_, v)
    if v ~= spell or slot == nil or H.readByte(0x3A7C) ~= CMD_MAGIC then return end
    casts[#casts + 1] = { b8 = H.readByte(0xB8), b9 = H.readByte(0xB9), mp = H.readWord(0x3C08 + slot * 2),
                          f = H.frame }
    H.log(string.format("[shield] f%d $3410 <- $%02X under Magic: targets chars $%02X mons $%02X, wearer MP %d",
      H.frame, v, casts[#casts].b8, casts[#casts].b9, casts[#casts].mp))
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
end
local function ownCast()
  for _, c in ipairs(casts) do if c.b9 ~= 0 and c.b8 == 0 then return c end end
end
local plan, battles, BATTLES = { {} }, 0, 6

-- a step built when it is first reached, from what the run has read by then
-- (the wearer and the shield are the live save's, chosen in choose())
local function lazy(build)
  local s = nil
  return {
    tick = function()
      if s == nil then s = H.seqStep({ build() }) end
      return s:tick()
    end,
    reset = function() if s then s:reset() end; s = nil end,
  }
end

local A, B = nil, nil
local function toBattle()
  return H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
    H.call(function()
      if A ~= nil then return end
      local x0, y0 = H.worldX(), H.worldY()
      for _, d in ipairs({ { 0, 2 }, { 0, -2 }, { 2, 0 }, { -2, 0 }, { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }) do
        if H.worldBfs(x0 + d[1], y0 + d[2]) then A, B = { x0, y0 }, { x0 + d[1], y0 + d[2] }; break end
      end
      H.assertEq(A ~= nil, true, string.format("a walkable pace from world (%d,%d)", x0, y0))
      H.log(string.format("[shield] pacing world (%d,%d) <-> (%d,%d)", A[1], A[2], B[1], B[2]))
    end),
    H.worldNavTo(function() return B[1] end, function() return B[2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() A, B = B, A end),
  }, "a random battle on the world map")
end

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("wor-cyan-v1"),
  H.call(function()
    choose()
    arm()
    family = familyBytes()
    H.log("[shield] the wearer's learned bytes for the family: " .. family)
    H.assertEq(learned() ~= 0xFF, true, "before: the wearer has not learned " .. sname)
  end),
  -- care first, as a player would before opening the wearer's menus and
  -- walking into the world map's fights: a wearer felled by an earlier
  -- battle has no Skills submenu to open (#468: a burned encounter left
  -- char 2 at 0/2012, and A timed out on "skills submenu")
  H.waitUntil(function() return H.worldHasControl() end, 3000, "world control before the care", 5),
  H.fieldCare({ tag = "shield: care before A", threshold = 0.95 }),
  H.call(function()
    H.assertEq(H.charHp(who) > 0, true, string.format("the wearer (char %d) stands after the care (HP %d/%d)",
      who, H.charHp(who), H.charMaxHp(who)))
  end),
  -- A. without the shield
  openMagic("A"),
  H.call(function()
    H.assertEq(fieldIndex(), nil, "A: " .. sname .. " is absent from the wearer's field Magic list")
  end),
  closeMenu("A"),
  -- B. the shield on, by the real Equip menu
  lazy(function() return H.equipLoadout(who, { { LHAND, shield } }, { tag = "B equip" }) end),
  H.call(function()
    H.assertEq(rec(0x1F + LHAND), shield, "B: the left hand holds the " .. iname)
  end),
  openMagic("B"),
  H.call(function()
    local i = fieldIndex()
    H.assertEq(i ~= nil, true, "B: " .. sname .. " is in the wearer's field Magic list")
    H.assertEq(learned() ~= 0xFF, true, "B: wearing the " .. iname .. " did not teach " .. sname)
    H.assertEq(H.knowsSpell(who, spell), true, "B: the field planner (H.knowsSpell) sees the shield's grant")
    H.log(string.format("[shield] B: field Magic list index %d holds $%02X, colour $%02X", i, spell,
      H.readByte(MAGIC_COLOUR + i)))
    H.screenshot("battle_shieldgrant_field")
  end),
  closeMenu("B"),
  -- C. battles until the wearer's cast lands (a battle that ends first, or
  -- one where the wearer falls before the turn, is fought out and the next
  -- taken, up to BATTLES)
  H.driveUntil(function() return ownCast() ~= nil and not H.battleLoadStarted() end, 300000, {
    H.cond(function() return not H.battleLoadStarted() end, {
      H.waitUntil(function() return H.worldHasControl() end, 3000, "C: world control", 5),
      -- a wearer felled in the last battle is revived before the next
      H.fieldCare({ tag = "shield: care before a battle", threshold = 0.95 }),
      H.waitUntil(function() return H.worldHasControl() end, 3000, "C: world control after the care", 5),
      toBattle(),
      H.waitUntil(function() return H.battleActive() end, 1200, "C: the battle is up", 2),
      H.waitFrames(30),
    }, {}),
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= BATTLES, true, string.format("C: the cast within %d battles", BATTLES))
      slot = nil
      for s = 0, 3 do
        if H.readByte(0x3ED8 + s * 2) == H.charActor(who) then slot = s end
      end
      H.assertEq(slot ~= nil, true, "C: the wearer is seated")
      H.assertEq(H.readWord(0x3BF4 + slot * 2) > 0, true, "C: the wearer stands at the battle's open (the care "
        .. "before the walk saw to it)")
      local base, cell = H.readWord(0x302C + slot * 2), nil
      for k = 0, 53 do
        if H.readByte(base + (k + 1) * 4) == spell then cell = k end
      end
      H.assertEq(cell ~= nil, true, "C: " .. sname .. " has a cell in the wearer's battle Magic list")
      H.log(string.format("[shield] C: battle %d, seat %d, battle list cell %d holds $%02X, wearer MP %d",
        battles, slot, cell, spell, H.readWord(0x3C08 + slot * 2)))
      plan[1] = { who = H.charActor(who), cmd = CMD_MAGIC, spell = spell, boost = 0 }
    end),
    H.kitBattle(plan, { maxFrames = 60000 }),
    H.call(function()
      local c = ownCast()
      H.log(string.format("[shield] C: battle %d over: %s", battles,
        c and string.format("the wearer cast %s at monsters $%02X (f%d, MP %d then)", sname, c.b9, c.f, c.mp)
          or "no cast of the wearer's landed; the next battle"))
    end),
  }, "C: the wearer casts the granted spell"),
  -- D. the old shield back on: the grant goes
  H.waitUntil(function() return H.worldHasControl() end, 3000, "D: world control", 5),
  lazy(function() return H.equipLoadout(who, { { LHAND, oldShield } }, { tag = "D unequip" }) end),
  H.call(function()
    H.assertEq(rec(0x1F + LHAND), oldShield, "D: the left hand holds the old shield again")
    H.assertEq(H.knowsSpell(who, spell), false, "D: the field planner sees no grant")
  end),
  openMagic("D"),
  H.call(function()
    H.assertEq(fieldIndex(), nil, "D: " .. sname .. " is gone from the wearer's field Magic list")
    H.assertEq(learned() ~= 0xFF, true, "D: wearing and casting taught nothing: " .. sname .. " not learned")
    H.assertEq(familyBytes(), family, "D: the wearer's learned bytes for the family are as they were "
      .. "(the shield teaches no tier)")
  end),
  closeMenu("D"),
  H.logStep(function() return "battle_shieldgrant complete" end),
})
