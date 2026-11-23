-- @suite savestate=gau_joined slow
-- battle_sixgau.lua -- GAU's own body is his fangs: his bare-handed Fight and
-- his raging plain attack carry Dagger, while SABIN's bare hand is Blunt
-- (#566, the regrouping of 2026-11-23).
--
-- Ot6WeaponClass (ot6_break.asm) loads a swing's class from the swinging
-- hand's item through Ot6WeapClassTbl, where the empty hand ($FF) is Blunt.
-- GAU is the exception: his empty hand, and either hand while he rages (his
-- hands then hold the rage monster's graphics code, SetRage, not an item),
-- load OT6_CLS_FANG, Dagger.
--
-- Boots gau_joined (SABIN, CYAN and GAU on the Veldt; GAU joins bare-handed)
-- and plays, through the real menus:
--   0. on the world map SABIN's weapon goes back to the bag through Equip ->
--      Rmove, so his main hand is empty too;
--   1. a Veldt encounter; GAU Fights and SABIN Fights (H.kitBattle), the
--      others Defend;
--   2. GAU picks Rage, and in its list a rage whose monster's hand code
--      (MonsterProp+26, what SetRage puts in his hands) is not $FF and is
--      not a Dagger by the item table -- chosen from the rages he knows
--      ($1D2C) and the ROM, the d-pad steered to it by the list's cursor
--      cells -- so the empty-hand rule and the item table would both give
--      another class; the party Defends while he rages, until a plain attack
--      of his has swung;
--   a battle that ends before all three were seen is followed by another.
-- Read at the ROM's own store: every write of the attack's class byte
-- (OT6_ATKCLASS) made from inside Ot6WeaponClass, with the swinging entity,
-- its hand's item and whether it rages.  Asserted:
--   a. GAU's bare-handed swings (hand $FF, not raging) each load Dagger $02;
--   b. SABIN's bare-handed swings (hand $FF) each load Blunt $04, which is
--      Ot6WeapClassTbl[$FF]: the same empty hand, the other class;
--   c. GAU's raging swings each load Dagger $02, with his hand holding the
--      rage's code, for which the item table says another class;
--   d. every other swing seen loads its hand's Ot6WeapClassTbl byte.
--
-- One declared write (tools/state_write_waivers.txt): on the Veldt GAU's
-- first row is Leap, not Fight (Ot6VeldtRow), and gau_joined's whole
-- walkable component is Veldt, so his bare-handed Fight cannot be reached by
-- geography from here.  As battle_gaufight's battle B does, an exec callback
-- on InitCmdList clears $11E4 bit 1 as the lists are built, so his row 0 is
-- Fight.  The rage, the swings and the classes are the game's own.
--
-- What it relies on other suites for: that a Dagger hit chips a Dagger-weak
-- body (battle_sixchip); GAU's rows on and off the Veldt (battle_gaufight).
-- Mutants (build/attempts/wt/v051-six-classes/newsuites/): the GAU test
-- comparing against SABIN; the raging test removed.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local DAGGER, BLUNT = 0x02, 0x04          -- the design: GAU's fangs, an empty hand
local SABIN, GAU = 0x05, 0x0B
local CMD_FIGHT, CMD_RAGE = 0x00, 0x10
local MENU, ACTOR, MSTATE, ST_RAGE = 0x7BCA, 0x62CA, 0x7BC2, 0x1E
local VELDT = 0x11E4
local ATKCLASS = H.sym("OT6_ATKCLASS")
local P_WC, P_WC_END = H.sym("Ot6WeaponClass"), H.sym("Ot6ItemClass")
assert(P_WC < P_WC_END and P_WC_END - P_WC < 0x80, "Ot6ItemClass follows Ot6WeaponClass (the class load's pc range)")

local function hand(c) return H.readByte(0x1600 + 37 * c + 0x1F) end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) == (H.readByte(0x1A6D) & 0x07) and (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function seatOf(c)
  for e = 0, 3 do if H.readByte(0x3ED8 + e * 2) == c then return e end end
  return nil
end
local function raging(e) return (H.readByte(0x3EF9 + e * 2) & 0x01) ~= 0 end

-- every class Ot6WeaponClass loaded: who swung, with what, raging or not
local swings, armed, cleared = {}, false, 0
local function count(kind)
  local n = 0
  for _, w in ipairs(swings) do if w.kind == kind then n = n + 1 end end
  return n
end
local function arm()
  emu.addMemoryCallback(function(_, value)
    if not armed then return end
    local st = emu.getState()
    local pc = ((st["cpu.k"] & 0xFF) << 16) | (st["cpu.pc"] & 0xFFFF)
    if pc < P_WC or pc >= P_WC_END then return end
    local x = st["cpu.x"] & 0xFF
    if x >= 8 then return end
    local e = x >> 1
    local w = { c = H.readByte(0x3ED8 + e * 2), item = H.readByte(0x3CA8 + x), rage = raging(e), class = value,
      f = H.frame }
    w.kind = (w.c == GAU and w.rage) and "gau raging" or (w.c == GAU and w.item == 0xFF) and "gau bare"
      or (w.c == SABIN and w.item == 0xFF) and "sabin bare" or "other"
    swings[#swings + 1] = w
    H.log(string.format("[sixgau] f%d swing: c%d (%s) hand $%02X%s -> class $%02X (the item table alone: $%02X)",
      H.frame, w.c, w.kind, w.item, w.rage and ", raging" or "", value,
      H.readRomByte((H.sym("Ot6WeapClassTbl") & 0x3FFFFF) + w.item)))
  end, emu.callbackType.write, 0x7E0000 + ATKCLASS, 0x7E0000 + ATKCLASS)
  -- the declared write: GAU's row 0 is Fight in this battle
  emu.addMemoryCallback(function()
    local v = H.readByte(VELDT)
    if (v & 0x02) ~= 0 then
      H.writeByte(VELDT, v & 0xFD)
      cleared = cleared + 1
    end
  end, emu.callbackType.exec, H.sym("InitCmdList"), H.sym("InitCmdList"))
end

-- the rage to pick: the first he knows whose monster's hand code is an item
-- of another class than Dagger.  The list shows the known rages in id order,
-- two columns.  -> index in the list, species, code
local function pickRage()
  local mp, tbl, k = H.sym("MonsterProp") & 0x3FFFFF, H.sym("Ot6WeapClassTbl") & 0x3FFFFF, 0
  for sp = 0, 255 do
    if (H.readByte(0x1D2C + (sp >> 3)) >> (sp & 7)) & 1 == 1 then
      local code = H.readRomByte(mp + sp * 32 + 26)
      local cls = H.readRomByte(tbl + code)
      if code ~= 0xFF and cls ~= DAGGER and cls ~= 0 then return k, sp, code end
      k = k + 1
    end
  end
  return nil
end
local RAGE = {}

local function seen() return count("gau bare") >= 1 and count("sabin bare") >= 1 and count("gau raging") >= 1 end

-- one Veldt battle: the two bare Fights, then the rage
local function battle(i)
  local flip, mark = false, nil
  local tag = "battle " .. i
  return H.cond(function() return not seen() end, {
    H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldAligned() end, 6000,
      tag .. ": world control on the Veldt"),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() or not H.worldHasControl() then H.setPad({}); return end
        if not H.worldAligned() then return end
        flip = not flip
        H.setPad({ [flip and "left" or "right"] = true })
      end),
    }, tag .. ": a Veldt encounter fires"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 5),
    H.waitFrames(90),
    H.call(function()
      local g, sb = seatOf(GAU), seatOf(SABIN)
      H.assertEq(g ~= nil and sb ~= nil, true, tag .. ": GAU and SABIN are seated")
      H.assertEq(H.readByte(0x202E + g * 12), CMD_FIGHT, tag .. ": GAU's row 0 is Fight (the declared write at "
        .. "InitCmdList; on the Veldt it is Leap)")
      H.assertEq(H.readByte(0x3CA8 + g * 2), 0xFF, tag .. ": GAU's main hand is empty")
      H.assertEq(H.readByte(0x3CA8 + sb * 2), 0xFF, tag .. ": SABIN's main hand is empty")
      armed = true
      mark = #swings
    end),
    -- 1. the bare Fights
    H.kitBattle({ { who = GAU, cmd = CMD_FIGHT, boost = 0 }, { who = SABIN, cmd = CMD_FIGHT, boost = 0 } },
      { idle = "defend", care = false, untilPlanDone = true, maxFrames = 20000,
        planDone = function() return count("gau bare") >= 1 and count("sabin bare") >= 1 end }),
    -- 2. the rage: Rage's window, then A on whatever GAU has open until he rages
    H.cond(function() return H.battleLoadStarted() end, {
      H.kitBattle({ { who = GAU, cmd = CMD_RAGE, boost = 0 } }, { idle = "defend", care = false, maxFrames = 20000,
        giveUp = function() return H.readByte(MSTATE) == ST_RAGE or raging(seatOf(GAU) or 0) end }),
      -- the list's cursor to the chosen rage (scroll $892B, column $892F, row $8933, by seat)
      H.driveUntil(function()
        local g = seatOf(GAU)
        return H.readByte(MSTATE) ~= ST_RAGE or (H.readByte(0x892B + g) + H.readByte(0x8933 + g) == RAGE.k // 2
          and H.readByte(0x892F + g) == RAGE.k % 2)
      end, 3000, {
        H.call(function()
          local g = seatOf(GAU)
          if H.readByte(MSTATE) ~= ST_RAGE then H.setPad({}); return end
          local absRow, col = H.readByte(0x892B + g) + H.readByte(0x8933 + g), H.readByte(0x892F + g)
          if col ~= RAGE.k % 2 then H.setPad({ [col < RAGE.k % 2 and "right" or "left"] = true })
          elseif absRow ~= RAGE.k // 2 then H.setPad({ [absRow < RAGE.k // 2 and "down" or "up"] = true })
          else H.setPad({}) end
        end),
        H.waitFrames(2),
        H.call(function() H.setPad({}) end),
        H.waitFrames(8),
      }, tag .. ": the rage list's cursor on the chosen rage"),
      H.driveUntil(function() return raging(seatOf(GAU) or 0) or not H.battleLoadStarted() end, 4000, {
        H.call(function()
          local g = seatOf(GAU)
          H.setPad((H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == g and H.frame % 16 < 4) and { a = true } or {})
        end),
      }, tag .. ": GAU rages"),
      H.release(),
      H.kitBattle({}, { idle = "defend", care = false, maxFrames = 30000,
        giveUp = function() return count("gau raging") >= 1 end }),
    }, {}),
    H.release(),
    H.call(function()
      H.log(string.format("[sixgau] %s: %d swing(s) seen this battle; so far gau bare %d, sabin bare %d, gau raging "
        .. "%d; the battle %s", tag, #swings - mark, count("gau bare"), count("sabin bare"), count("gau raging"),
        H.battleLoadStarted() and "is still up" or "has ended"))
    end),
    -- the battle fought out, and the field's care after it
    (function()
      local F = H.newFightDriver("sixgau" .. i, { tactical = true, boost = true, items = true, bank = 0, healPercent = 55 })
      return H.driveUntil(function() return not H.battleLoadStarted() end, 40000, {
        H.call(function() F.frame() end),
      }, tag .. ": fought out")
    end)(),
    H.release(),
    H.call(function() armed = false end),
    H.waitFrames(60),
    H.cond(function() return not seen() end, { H.careStop("care after " .. tag) }, {}),
  }, {})
end

local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    arm()
    H.assertEq(inParty(GAU) and inParty(SABIN), true, "gau_joined's party holds GAU and SABIN")
    H.assertEq(hand(GAU), 0xFF, "GAU joins bare-handed (he equips no weapon)")
    H.assertEq(H.weaponClass(0xFF), BLUNT, "Ot6WeapClassTbl[$FF], the empty hand, is Blunt")
    H.assertEq(H.kitClass("fang"), DAGGER, "Ot6KitClassTbl's fang byte is Dagger")
    H.log(string.format("[sixgau] SABIN's weapon ($%02X) goes back to the bag through Equip -> Rmove", hand(SABIN)))
    RAGE.k, RAGE.sp, RAGE.code = pickRage()
    H.assertEq(RAGE.k ~= nil, true, "GAU knows a rage whose monster's hand code is an item of another class than "
      .. "Dagger (the rages gen_sabin_gau's Veldt battles left him)")
    H.log(string.format("[sixgau] the rage: entry %d of his list, species $%03X, hand code $%02X (the item table: "
      .. "class $%02X)", RAGE.k, RAGE.sp, RAGE.code, H.weaponClass(RAGE.code)))
  end),
  H.removeEquip(SABIN, 0, { tag = "sixgau: SABIN's hand emptied" }),
  H.call(function() H.assertEq(hand(SABIN), 0xFF, "SABIN's main hand is empty") end),
}
-- a rage's plain attack is one of its two actions; four battles of Defending
-- turns is far past any run of specials
for i = 1, 4 do steps[#steps + 1] = battle(i) end
steps[#steps + 1] = H.call(function()
  H.assertEq(cleared >= 1, true, "the declared write ran: $11E4 bit 1 was set (a Veldt battle) and was cleared at "
    .. "InitCmdList")
  local n = { ["gau bare"] = 0, ["sabin bare"] = 0, ["gau raging"] = 0, other = 0 }
  local tbl = H.sym("Ot6WeapClassTbl") & 0x3FFFFF
  for _, w in ipairs(swings) do
    n[w.kind] = n[w.kind] + 1
    local what = string.format("f%d c%d hand $%02X", w.f, w.c, w.item)
    if w.kind == "gau bare" then
      H.assertEq(w.class, DAGGER, "GAU's bare-handed Fight carries Dagger, his fangs (" .. what .. ")")
    elseif w.kind == "gau raging" then
      H.assertEq(w.item, RAGE.code, "raging, GAU's hand holds the chosen rage's code (" .. what .. ")")
      H.assertEq(w.class, DAGGER, "GAU's raging plain attack carries Dagger, whatever his hand holds (" .. what .. ")")
    elseif w.kind == "sabin bare" then
      H.assertEq(w.class, BLUNT, "SABIN's bare hand carries Blunt: the fangs are GAU's alone (" .. what .. ")")
    else
      H.assertEq(w.class, H.readRomByte(tbl + w.item), "any other swing carries its hand's Ot6WeapClassTbl byte ("
        .. what .. ")")
    end
  end
  H.assertEq(n["gau bare"] >= 1, true, "a bare-handed Fight of GAU's was seen")
  H.assertEq(n["sabin bare"] >= 1, true, "a bare-handed Fight of SABIN's was seen")
  H.assertEq(n["gau raging"] >= 1, true, "a raging plain attack of GAU's was seen within four battles")
  H.log(string.format("[sixgau] swings: GAU bare %d (Dagger), SABIN bare %d (Blunt), GAU raging %d (Dagger), "
    .. "others %d (their hands' table bytes)", n["gau bare"], n["sabin bare"], n["gau raging"], n.other))
  H.log("[sixgau] PASS")
end)

H.run({ maxFrames = 400000 }, steps)
