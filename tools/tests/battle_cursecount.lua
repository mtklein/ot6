-- @suite slow savestate=wor_colosseum
-- battle_cursecount.lua -- the Cursed Shield's count: two for a won random battle, one for an event battle, and
-- the wrap past 255 that lifts the curse (#387, ot6_gear.asm).
--
--   tools/tests/run.sh tools/tests/battle_cursecount.lua
--
-- The rule.  The Cursed Shield becomes the Paladin Shield when the count LearnItemMagic keeps ($3EC0 in battle,
-- $1DD5 between battles) wraps past 255; vanilla adds one a won battle for each living wearer.  OT6 halves the
-- random encounters a step and doubles their reward (Ot6DangerMulW, Ot6RewardMulW), and Ot6CurseCount gives the
-- count the same pair: a won random battle adds two, an event battle one, and a sum past 255 lifts the curse
-- (the count then reads what is left over).
--
-- Boots wor_colosseum (the Falcon's tile by Maranda; the Cursed Shield in the bag since Narshe) for each arm,
-- puts a Ribbon on SHADOW first, as a player wearing the shield would (the shield sets Condemned, Mute,
-- Berserk, Muddle and Sap, ItemProp $66 +25 $79, and holds the four the Ribbon guards past any cure: a
-- Muddled, Berserk SHADOW kills his own party, the 2026-11-03 play's wipe, where the party's one Ribbon was
-- TERRA's and the suite had leaned on the earlier play's second one sitting on SHADOW), then the shield through
-- the real Equip screen, and walks the plain's pool (world group 49) with the
-- route's fight driver until a random battle is won with SHADOW standing (a battle he falls in counts nothing):
--   A. played: the count moves by exactly two, the shield still cursed;
--   B. declared (a waiver): the count staged at 254 before the walk ($1DD5): 254 + 2 lifts the curse, the count
--      0 and the shield the Paladin Shield;
--   C. declared: staged at 255, and the battle read as an event battle (Ot6RandBtl's flag, $57BD, cleared at
--      Ot6CurseCount's entry, the only reader there): 255 + 1 lifts it, the count 0;
--   D. declared: staged at 100, read as an event battle: the count 101, the shield still cursed;
--   E. declared: staged at 255: 255 + 2 lifts it with one left over, the count 1.
-- The event battle is staged because the route's play has no event battle with the shield worn (no wearer on
-- the route: route-wor-colosseum.md section 5), and the wrap because 128 battles is not a suite.
local H = dofile("tools/tests/lib/ot6.lua")
local SHADOW, CURSED, PALADIN = 3, 0x66, 0x67
-- GUARD (a global a lab sets ahead of the lib; the Ribbon in the suite): the relic that goes on SHADOW first
local RIBBON = type(GUARD) == "number" and GUARD or 0xCA
local STATE = "build/states/wor_colosseum.mss.lua"
local FIGHT = {}
local K = H.worLegKit({ fight = FIGHT, links = {}, names = { [0] = "TERRA", [2] = "CYAN", [3] = "SHADOW", [6] = "CELES" } })
local ends, eventArm, n0, c0 = {}, false, 0, 0

emu.addMemoryCallback(function()
  -- the battle's end, while its cells are still the battle's: the random flag, and SHADOW's seat
  local seat, hp = nil, 0
  for e = 0, 3 do if H.readByte(0x3ED8 + e * 2) == SHADOW then seat = e end end
  if seat then hp = H.readWord(0x3BF4 + seat * 2) end
  ends[#ends + 1] = { random = H.readByte(0x57BD) ~= 0, shadowHp = hp, f = H.frame }
end, emu.callbackType.exec, H.sym("UpdateSRAM"), H.sym("UpdateSRAM"))
emu.addMemoryCallback(function()
  if eventArm then H.writeByte(0x57BD, 0) end   -- the declared staging: this battle read as an event's
end, emu.callbackType.exec, H.sym("Ot6CurseCount"), H.sym("Ot6CurseCount"))

local function shield() return H.readByte(0x1600 + 37 * SHADOW + 0x20) end
local function relic(ch, slot) return H.readByte(0x1600 + 37 * ch + 0x1F + slot) end

-- The Ribbon onto SHADOW: from the bag, or off the seated member who wears it (the Relic menu's Remove, then
-- SHADOW's Equip).  SHADOW's slot is an empty one, else one that holds no two-weapon relic.  The party owning
-- a Ribbon is the precondition (the WoB's, worn since); without one the suite stops here and says so.
local function guard(name)
  local from, fromSlot, slot
  return H.seqStep({
    H.call(function()
      from, fromSlot, slot = nil, nil, nil
      if relic(SHADOW, 4) == RIBBON or relic(SHADOW, 5) == RIBBON then
        H.log(string.format("[curse] %s: SHADOW wears the Ribbon $%02X already", name, RIBBON)); return
      end
      if H.invCountOf(RIBBON) < 1 then
        local active = H.readByte(0x1A6D) & 7
        for ch = 0, 13 do
          if ch ~= SHADOW and (H.readByte(0x1850 + ch) & 7) == active and from == nil then
            for s = 4, 5 do if from == nil and relic(ch, s) == RIBBON then from, fromSlot = ch, s end end
          end
        end
      end
      H.assertEq(H.invCountOf(RIBBON) >= 1 or from ~= nil, true, string.format(
        "%s: the party owns the guard $%02X (a Ribbon; in the bag or on a seated member) for the shield's wearer", name, RIBBON))
      for s = 5, 4, -1 do if slot == nil and relic(SHADOW, s) == 0xFF then slot = s end end
      for s = 5, 4, -1 do
        local cl = H.relicClass(relic(SHADOW, s))
        if slot == nil and not (cl and cl.hands) then slot = s end
      end
      H.assertEq(slot ~= nil, true, name .. ": SHADOW has a relic slot without a two-weapon relic")
      H.log(string.format("[curse] %s: the Ribbon $%02X %s, onto SHADOW's slot %d (over $%02X)", name, RIBBON,
        from and string.format("off char %d's slot %d", from, fromSlot) or "from the bag", slot, relic(SHADOW, slot)))
    end),
    H.lazy(function()
      if from == nil then return H.seqStep({}) end
      return H.unequipRelics(from, { fromSlot }, { tag = name .. ": the Ribbon off char " .. from })
    end),
    H.lazy(function()
      if slot == nil then return H.seqStep({}) end
      return H.equipKit(SHADOW, { { slot, RIBBON } }, { tag = name .. ": SHADOW: the Ribbon on" })
    end),
    H.call(function()
      H.assertEq(relic(SHADOW, 4) == RIBBON or relic(SHADOW, 5) == RIBBON, true, name .. ": SHADOW wears the Ribbon")
    end),
  })
end
local function counted(i)
  local o = H.outcomes[n0 + i]
  return o ~= nil and o.kind == "won" and ends[i] ~= nil and ends[i].shadowHp > 0
end
local function arm(name, start, event, wantCount, wantShield)
  return H.seqStep({
    H.loadState(STATE),
    -- BURN (a global a lab sets ahead of the lib; 0 in the suite): that many random battles fought first, before
    -- the shield goes on, to vary the encounter history the arm's battle comes from (TESTING.md)
    H.cond(function() return type(BURN) == "number" and BURN > 0 end, {
      H.call(function() n0 = #H.outcomes end),
      K.pace(function() return #H.outcomes - n0 >= BURN end, (type(BURN) == "number" and BURN or 0) + 2,
        name .. ": the encounters BURN uses up"),
      H.fieldCare({ threshold = 1.0, tag = name .. ": after the burned encounters" }),
    }, {}),
    H.call(function()
      H.assertEq(H.readByte(0x1850 + SHADOW) & 7, 1, name .. ": SHADOW is seated")
      H.assertEq(H.invCountOf(CURSED) >= 1, true, name .. ": the bag holds the Cursed Shield")
    end),
    guard(name),
    H.equipKit(SHADOW, { { 1, CURSED } }, { tag = name .. ": SHADOW: the Cursed Shield on" }),
    H.call(function()
      H.assertEq(shield(), CURSED, name .. ": SHADOW wears the Cursed Shield (slot 1)")
      if start then H.writeByte(0x1DD5, start) end   -- the declared staging (the header)
      c0, n0, ends, eventArm = H.readByte(0x1DD5), #H.outcomes, {}, event
      H.log(string.format("[curse] %s: the count before: $1DD5 = %d%s", name, c0, event and "; read as an event" or ""))
    end),
    K.pace(function()
      for i = 1, #H.outcomes - n0 do if counted(i) then return true end end
      return false
    end, 6, name .. ": a random battle won with SHADOW standing"),
    H.call(function()
      eventArm = false
      local c1 = H.readByte(0x1DD5)
      local last = ends[#ends]
      H.log(string.format("[curse] %s: the count after: $1DD5 = %d, shield $%02X, %d battle(s), the last read random %s",
        name, c1, shield(), #ends, tostring(last.random)))
      H.assertEq(last.random, not event, name .. ": the battle read as " .. (event and "an event" or "a random") .. " one")
      H.assertEq(c1, wantCount or ((c0 + 2) & 0xFF), string.format("%s: the count from %d", name, c0))
      H.assertEq(shield(), wantShield, string.format("%s: the shield ($%02X: %s)", name, wantShield,
        wantShield == PALADIN and "the curse lifted" or "still cursed"))
    end),
  })
end

H.run({ maxFrames = 600000 }, {
  arm("A (a random battle)", nil, false, nil, CURSED),
  arm("B (254, a random battle)", 254, false, 0, PALADIN),
  arm("C (255, an event battle)", 255, true, 0, PALADIN),
  arm("D (100, an event battle)", 100, true, 101, CURSED),
  arm("E (255, a random battle)", 255, false, 1, PALADIN),
  H.call(function() H.log("[curse] PASS: two a random battle, one an event, and the wrap lifts the curse") end),
})
