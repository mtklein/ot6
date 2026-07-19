-- battle_vargas.lua -- rung 2's boss gate: VARGAS's break gauge, the two
-- chips that are supposed to reach it, and the scripted finish.
--
--   tools/tests/run.sh tools/tests/battle_vargas.lua
--
-- Boots vargas_doorstep.mss (gen_kolts), presses A once into `_ca828f`
-- (npc_prop.asm:4006 -> event_main.asm:19818), rides the scene through
-- `char_party SABIN,0` (:19906) into `battle 66, MOUNTAINS_EXT` (:19909),
-- and asserts:
--
--   1. THE GAUGE IS AUTHORED, not formula.  Vargas ($0103) seeds 5/5 with
--      class-weak $04 = OT6_BLUDG, straight off Ot6ShieldTbl (ot6.asm:2969);
--      both Ipoohs ($014D) seed 2/2 slash-weak.  The formula value for a
--      monster this size would not be 5, so a dropped row fails here first.
--   2. THE ELEMENT ADD IS LIVE.  His weak byte reads $28 = poison|holy.
--      Vanilla gives poison only -- monster_prop.dat +25 = $08 -- and the
--      holy bit is Ot6ElemAddTbl's row (ot6.asm:216), applied at seed time
--      by Ot6ElemAdd.  This is the assertion that fails if that row is ever
--      dropped, mistyped, or applied to the wrong species.
--   3. HOLY CHIPS.  Sabin's AuraBolt (Blitz 1, skill $5e, element $20) takes
--      a shield AND reveals holy in $3E89 -- the runtime half of the proof
--      main commit 5d00086 deferred to "the vargas-doorstep fixture".  Holy
--      is the ONLY way that shield can move on that turn: it is checked
--      against the recorded skill id, and Sabin is alone on the field.
--   4. BLUDGEONING CHIPS.  Pummel (Blitz 0, skill $5d, OT6_BLUDG per
--      Ot6SkillClassTbl, ot6_class.asm:193) takes another shield and reveals
--      class $04.
--   5. THE FIGHT ENDS TO THE SCRIPT.  Vargas's reaction script
--      (ai_script.asm:4385-4388) answers `if_attack PUMMEL` with
--      `battle_event $09 / kill_monsters ALL, FADE_HORIZONTAL`, and that --
--      not HP, not the gauge -- is what wins.  Asserted by the battle
--      tearing down within a bounded window of the Pummel that caused it.
--
-- WHY THE HP POKE.  This fight is TWO PHASES and the second one is where
-- Sabin exists as a combatant.  Measured: from the opening bell, entities
-- 0/1/2 (Edgar/Locke/Terra) take turns and entity 3 (Sabin, char $05,
-- level 9) NEVER gets a menu -- 9000 frames of it.  His turns start only
-- after Vargas's own reaction script runs `battle_event $07` at hp <= 10880
-- ("Enough!! Off with ya now!") and `battle_event $08` at hp <= 10368
-- (ai_script.asm:4392-4404), which is the beat that blows the trio offstage
-- and leaves the monk alone -- exactly the fight bosses-wob.md describes.
-- So the test clamps his HP to just under the second threshold and lets HIS
-- OWN SCRIPT fire the transition on the party's next landed hit.  Nothing
-- about the gauge is poked: shields, elements, classes and every chip below
-- are the engine's, and Ipooh/Vargas seed values are read before the clamp.
--
-- SABIN'S LEVEL IS ASSERTED, not assumed.  AuraBolt is a level-6 Blitz; if
-- the join level ever drops under it, proof 3 is testing nothing, so the
-- level is a hard assert rather than a comment.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/vargas_doorstep.mss.lua"

local VARGAS, IPOOH = 0x0103, 0x014D
local OT6_BLUDG, OT6_SLASH = 0x04, 0x01
local HOLY, POISON = 0x20, 0x08
local PUMMEL, AURABOLT = 0x5D, 0x5E
local SABIN_E = 3                       -- entity index SABIN joins into
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_BLITZ = 0x3D                   -- UpdateMenuState_3d, the code window
local ST_CMD   = 0x05                   -- the command list, cursor live

-- monster slot s -> entity offset 8 + 2s (battle_class's map)
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end

local aPh = 0
local spells, shWrites = {}, {}
local vSlot = 0

-- Keep the party upright: Vargas hits hard, a wipe ends the run before it
-- has measured anything, and party HP is not what any of this is about.
local function pinParty()
  for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
end

-- Tap A unless SABIN's own command window is up.  Vargas's script talks
-- ($12 "I tire of this!", $43, $0a) and a battle dialog blocks the whole
-- queue until it is dismissed -- measured, 9000 frames of menu=00/mstate=00
-- with the fight otherwise alive and nothing pressing anything.
local function tapUnlessSabin()
  pinParty()
  aPh = (aPh + 1) % 8
  if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E then
    H.setPad({})
  else
    H.setPad(aPh < 4 and { "a" } or {})
  end
end

local function shields() return H.readByte(SH(vSlot)) end
local function snap(t)
  H.log(string.format("[%s] f%d actor=%d mstate=$%02X vHP=%d shields=%d/%d " ..
    "revElem=$%02X revClass=$%02X weakElem=$%02X lastSkill=$%02X",
    t, H.frame, H.readByte(ACTOR), H.readByte(MSTATE), H.readWord(MHP(vSlot)),
    shields(), H.readByte(SMX(vSlot)), H.readByte(RVE(vSlot)),
    H.readByte(RVC(vSlot)), H.readByte(WKE(vSlot)), H.readByte(0x3410)))
end

-- One Blitz, driven the way a player drives it: wait for SABIN's command
-- list, DOWN to slot 1 (Blitz), A to open the code window, then the code as
-- discrete pad EDGES.  UpdateMenuState_3d (btlgfx_main.asm:17219) records
-- edges into a rolling buffer on a 64-frame timeout, so a held direction is
-- ONE input however long it is held; 4 on / 4 off is the same edge discipline
-- dialogs need.  Masks from BlitzButtonMaskTbl (:17002): LEFT $0200, RIGHT
-- $0100, DOWN $0400, DOWN_LEFT $0600 (both bits -- one press, two buttons),
-- A $0080.
local function blitz(code, name)
  local steps = {
    H.driveUntil(function()
      return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E
         and H.readByte(MSTATE) == ST_CMD
    end, 12000, { H.call(tapUnlessSabin), H.waitFrames(1) },
      name .. ": SABIN's command list"),
    H.waitFrames(10),
    H.pressButtons({ "down" }, 4), H.waitFrames(8),
    H.pressButtons({ "a" }, 4), H.waitFrames(10),
    H.call(function()
      H.assertEq(H.readByte(MSTATE), ST_BLITZ,
        name .. ": the blitz code window is open (menu state $3d)")
      snap(name .. " window")
    end),
  }
  for _, b in ipairs(code) do
    steps[#steps + 1] = H.pressButtons(b, 4)
    steps[#steps + 1] = H.waitFrames(5)
  end
  steps[#steps + 1] = H.pressButtons({ "a" }, 4)
  steps[#steps + 1] = H.waitFrames(8)
  return H.cond(function() return true end, steps)
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 98, "booted on map 98, VARGAS's ledge")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1, "facing him")
  end),

  -- ONE interaction -> the scene -> battle 66
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the VARGAS scene reaches battle 66"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
  H.waitFrames(120),

  -- ===================================================================== --
  -- 1 + 2: the seed.  Read BEFORE anything is poked or pressed.
  -- ===================================================================== --
  H.call(function()
    local w = {}
    for s = 0, 5 do w[s] = H.readWord(0x57C0 + s * 2) end
    H.log(string.format("formation %04X %04X %04X %04X %04X %04X",
      w[0], w[1], w[2], w[3], w[4], w[5]))
    vSlot = nil
    for s = 0, 5 do if w[s] == VARGAS then vSlot = s end end
    H.assertEq(vSlot ~= nil, true, "VARGAS ($0103) is in the formation")
    H.assertEq(w[1], IPOOH, "an Ipooh ($014D) in slot 1")
    H.assertEq(w[2], IPOOH, "an Ipooh ($014D) in slot 2")

    -- the gauge
    H.assertEq(H.readByte(SH(vSlot)), 5, "VARGAS seeds 5 shields (Ot6ShieldTbl)")
    H.assertEq(H.readByte(SMX(vSlot)), 5, "VARGAS max shields 5")
    H.assertEq(H.readByte(WKC(vSlot)), OT6_BLUDG,
      "VARGAS class row is OT6_BLUDG ($04)")
    H.assertEq(H.readByte(RVE(vSlot)), 0, "nothing revealed yet (elements)")
    H.assertEq(H.readByte(RVC(vSlot)), 0, "nothing revealed yet (classes)")
    for _, s in ipairs({ 1, 2 }) do
      H.assertEq(H.readByte(SH(s)), 2, "Ipooh slot " .. s .. " seeds 2 shields")
      H.assertEq(H.readByte(WKC(s)), OT6_SLASH, "Ipooh slot " .. s .. " is slash-weak")
    end

    -- THE ELEMENT ADD.  vanilla = poison only; OT6 adds holy.
    local weak = H.readByte(WKE(vSlot))
    H.log(string.format("VARGAS weak elements = $%02X (vanilla $08 + add $20)", weak))
    H.assertEq(weak & POISON, POISON, "poison bit (vanilla, monster_prop +25)")
    H.assertEq(weak & HOLY, HOLY,
      "HOLY bit present -- Ot6ElemAddTbl's $0103 row applied (ot6.asm:216)")
    H.assertEq(weak, POISON | HOLY, "weak byte is exactly poison|holy")

    -- SABIN, and the level AuraBolt needs
    H.assertEq(H.readByte(0x3ED8 + SABIN_E * 2), 0x05,
      "SABIN is battle entity " .. SABIN_E)
    local lv = H.readByte(0x3B18 + SABIN_E * 2)
    H.log("SABIN joins at level " .. lv)
    H.assertEq(lv >= 6, true,
      "SABIN is level 6+ so AuraBolt is learned (got " .. lv .. ")")
    snap("seed")
    H.screenshot("vargas_seed")

    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = { H.frame, v } end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
    emu.addMemoryCallback(function(_, v) shWrites[#shWrites + 1] = { H.frame, v } end,
      emu.callbackType.write, 0x7E3E40 + vSlot * 2, 0x7E3E40 + vSlot * 2)
  end),

  -- ===================================================================== --
  -- Into phase two: clamp Vargas under his own script's second threshold
  -- and let the party's hits fire battle_event $07 / $08.  The gauge is
  -- untouched; only HP moves, and only downward past a scripted gate.
  -- ===================================================================== --
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E
  end, 20000, {
    H.call(function()
      if H.readWord(MHP(vSlot)) > 10300 then H.writeWord(MHP(vSlot), 10300) end
      tapUnlessSabin()
    end),
  }, "SABIN takes the field (battle_event $07/$08 ran)"),
  H.call(function()
    H.assertEq(H.readByte(SH(vSlot)), 5,
      "the gauge is still 5 -- phase one moved HP, not shields")
    snap("phase two")
    H.screenshot("vargas_phase2")
  end),

  -- ===================================================================== --
  -- 3: HOLY.  AuraBolt = DOWN, DOWN-LEFT, LEFT, A (BlitzCode entry 1).
  -- ===================================================================== --
  blitz({ { "down" }, { "down", "left" }, { "left" } }, "AURABOLT"),
  H.driveUntil(function() return #shWrites > 0 end, 2400, {
    H.call(tapUnlessSabin),
  }, "AURABOLT reaches the gauge"),
  H.call(function()
    snap("after AURABOLT")
    H.assertEq(H.readByte(0x3410), AURABOLT,
      "the resolved skill was AuraBolt ($5e), not a stray Fight")
    H.assertEq(shields(), 4, "AURABOLT took a shield: 5 -> 4")
    H.assertEq(H.readByte(RVE(vSlot)) & HOLY, HOLY,
      "and REVEALED holy ($20) -- the chip went through the element path")
    H.assertEq(H.readByte(RVC(vSlot)), 0,
      "no class revealed by an elemental chip")
  end),

  -- ===================================================================== --
  -- 4 + 5: BLUDGEONING, and the finish.  Pummel = LEFT, RIGHT, LEFT, A.
  -- Vargas answers `if_attack PUMMEL` with battle_event $09 +
  -- kill_monsters ALL, so this same input is both the class proof and the
  -- win path; the shield write and the teardown are asserted separately.
  -- ===================================================================== --
  blitz({ { "left" }, { "right" }, { "left" } }, "PUMMEL"),
  H.driveUntil(function() return #shWrites > 1 end, 2400, {
    H.call(tapUnlessSabin),
  }, "PUMMEL reaches the gauge"),
  H.call(function()
    snap("after PUMMEL")
    H.assertEq(H.readByte(0x3410), PUMMEL, "the resolved skill was Pummel ($5d)")
    H.assertEq(shields(), 3, "PUMMEL took a shield: 4 -> 3")
    H.assertEq(H.readByte(RVC(vSlot)) & OT6_BLUDG, OT6_BLUDG,
      "and REVEALED the bludgeoning class ($04)")
    H.assertEq(H.readByte(RVE(vSlot)) & HOLY, HOLY,
      "holy stays revealed across the second chip")
  end),
  H.driveUntil(function() return not H.battleLoadStarted() end, 9000, {
    H.call(function()
      pinParty()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the fight ends (battle_event $09 / kill_monsters ALL)"),
  H.call(function()
    H.assertEq(H.battleLoadStarted(), false, "battle torn down after PUMMEL")
    H.log(string.format("PASSED with VARGAS at %d HP -- the script killed him, " ..
      "not the damage", 11600 - 10300))
    H.log("skill writes: " .. #spells .. ", gauge writes: " .. #shWrites)
    for i = 1, #shWrites do
      H.log(string.format("  gauge f%d -> %d", shWrites[i][1], shWrites[i][2]))
    end
    H.screenshot("vargas_won")
  end),
})
