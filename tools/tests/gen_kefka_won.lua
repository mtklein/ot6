-- gen_kefka_won.lua -- boot kefka_entry, win battle 57 with real input on
-- one attempt (a loss is the runner's to count and retry).  Then ride the
-- whole win tail (the esper cliff on map 23, TERRA's morph, the flight
-- across the world, the regroup in Arvis's house) through the party-select
-- menu to the first controllable frame, and generate kefka_won.mss on map
-- 30 at (60,37).  Then walk out of Narshe by its item shop and save on the
-- world outside the south gate: the kefka-won-v1 cut gen_zozo1_submerge
-- boots from.

-- After the menu: _ccc1b5 reloads map 30 at {60,37} facing DOWN, sets
-- $0602/$010B/$0048, set_parent_map 0 {84,33}, player_ctrl_on, return
-- (event_main.asm:107272,107193-107208).  That calm is where the state is
-- generated.
local H = dofile("tools/tests/lib/ot6.lua")

-- the esper-zap species set
local TRITOCH = { [0x0114] = true, [0x0115] = true, [0x0144] = true }

local function map() return H.mapId() & 0x1ff end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ANTIDOTE, REMEDY = 0xF2, 0xF5
local TINCTURE = 0xEB
local SHOP_PROP = H.sym("ShopProp") & 0x3FFFFF   -- shop_prop.dat: 9 bytes per shop, items at +1
local function shopRow(shop, row) return H.readRomByte(SHOP_PROP + shop * 9 + 1 + row) end

-- ------------------------------------------------------------ the fighter --
-- KEFKA, with P1 = TERRA+EDGAR+CELES, is fought by the library's driver
-- with FIGHT below, the table battle_kefka and gen_narshe_battle carry
-- verbatim (#257; the lab and its first-attempt rate are under
-- build/attempts/wt/kefka-lab/).  It replaced a private fighter with no heal
-- line, whose Tools turn named whatever Tool the cursor sat on (the Bio
-- Blaster, $A4) and whose fallback to Fight dropped the boost, and which
-- won only through a three-attempt reload ladder with the "tier" raised.
-- The KEFKA fighter (#257), verbatim in battle_kefka, gen_narshe_battle and
-- gen_kefka_won.  Each lever was measured in build/attempts/wt/kefka-lab/:
--   runic   CELES holds Runic.  KEFKA's script is Fight plus spells, and a
--           spell that lands unabsorbed can take a member in one action:
--           every attributed [death] in the lab was Ice 2 (atk $06) or Drain
--           ($04) on one member, from 282-349 HP.
--   cure    false.  Runic absorbs the party's own casts too: with it up,
--           TERRA's Cure never landed ("restores ?" on every cast, her HP
--           falling while her MP paid).  The heal line is the bag.
--   healer  TERRA (0) takes the one care turn a round, with Potions (the
--           driver's own choice in battle), so CELES's turn stays Runic and
--           EDGAR, the harder hitter, keeps swinging.  The top-up fraction is
--           the driver's healPercent; 85 bought no margin over 70 and spent
--           2-7 Potions a fight.
--   tool    AutoCrossbow, from the ROM's data: $AA is OT6_PIERCE
--           (Ot6WeapClassTbl), power 125, ignores defence, 4 MP
--           (Ot6AbilityCostTbl), and pierce is one of KEFKA's shield classes
--           (row $03).  The Bio Blaster ($A4) the old fighter's cursor named
--           resolves as spell $7D (ThrowToolsItemTbl): power 20 poison, 8 MP.
--           The driver names the tool by id, and the boost it cannot pay for
--           stays on the Fight it falls back to.
--   boost   banked to 2 and spent, up to 3; a member inside one priced round
--           of death spends every pip first (the driver's spend rule).
local FIGHT = { tactical = true, boost = true, bank = 2, items = true,
  cure = false, runic = true, healer = 0, healPercent = 70,
  tool = H.AUTOCROSSBOW }
local BCHP, BCMAXHP = 0x3bf4, 0x3c1c
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2),
      H.readWord(BCMAXHP + e * 2))
  end
  return table.concat(p, " ")
end
-- ---------------------------------------------------------- menu driving --
-- State-fed party-menu driver, on the 1-party layout: pool rows 8 wide
-- (cells 0-15), party 0's four slots at cells $10-$13.
local function mst() return H.readByte(0x0026) end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function cell9d(c) return H.readByte(0x7E9D89 + c) end
-- the seats themselves are H.partySelect (lib/ot6_field.lua): each member
-- found in the pool, walked to its group's lowest empty seat, both cells
-- asserted, START to commit
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

-- calm-arrival pred: n consecutive controllable full-bright frames on map m
local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

-- --------------------------------------------------------- the KEFKA fight --
-- Activation by clean edge-A, the fight played once with real input, the
-- verdict read off the scripted branch (the win scene on the stage vs the
-- {25,5} lose-path save point).  No ladder: a wipe ends the attempt through
-- the run canary (class=wipe), and the segment runner's standard bounded
-- retry -- the boot snapshot, a moved seed, `[retry] attempt n/3 FAILED`,
-- audit_retries.py -- is the only reload, as for every generator.
local function kefkaFight()
  local F = H.newFightDriver("kefka", FIGHT)
  local battN, postN, evN = 0, 0, 0
  return H.driveUntil(function()
    if battN > 0 or H.battleLoadStarted() then return false end
    if H.fieldX() == 25 and H.fieldY() == 5 then
      error(string.format("LOST: battle 57 at f%d -- the lose path parked " ..
        "the party at the {25,5} save point", H.frame), 0)
    end
    postN = postN + 1
    evN = (H.eventRunning() or H.dialogWaiting()) and evN + 1 or evN
    return postN >= 600 and evN >= 60
  end, 90000, {
    H.call(function()
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        postN, evN = 0, 0
        if battN == 3 then
          H.log(string.format("[kefka] battle up f%d party [%s]", H.frame,
            partyLine()))
        end
        F.frame()
        return
      end
      F.idle()
      if H.dialogWaiting() then
        H.setPad(H.frame % 8 < 4 and { "a" } or {})
        return
      end
      H.setPad({})
    end),
  }, "the KEFKA fight, played once")
end

-- No allowGameOver: nothing here survives a lost battle 57 on purpose.
H.run({ maxFrames = 400000 }, {
  H.loadState("build/states/kefka_entry.mss.lua"),
  H.waitFrames(30),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
  }, "clean A into KEFKA -> battle 57"),
  H.waitUntil(function() return H.battleActive() end, 3000, "Kefka up", 10),
  kefkaFight(),
  H.call(function()
    H.log(string.format("[kefka] battle 57 WON at f%d", H.frame))
  end),

  (function()
    local aPh, zapN, battN, hb = 0, 0, 0, -600
    return H.driveUntil(function()
      return menuUp() and mst() == 0x2d and H.readByte(0x0200) == 4
    end, 30000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        zapN = TRITOCH[H.readWord(0x57C0)] and zapN + 1 or 0
        battN = H.battleLoadStarted() and battN + 1 or 0
        if H.frame - hb >= 600 then
          hb = H.frame
          H.log(string.format(
            "tail f%d map=%d (%d,%d) dlg=%s ev=%s zapN=%d battN=%d evpc=%02X%02X%02X",
            H.frame, map(), H.fieldX(), H.fieldY(),
            tostring(H.dialogWaiting()), tostring(H.eventRunning()),
            zapN, battN,
            H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5)))
        end
        if zapN > 0 then
          -- the morph set-piece: silence through the load, then edge-tap
          -- its battle-event text; it ends itself (end_battle)
          H.setPad(zapN > 300 and aPh < 4 and { "a" } or {})
          return
        end
        if battN >= 3 then
          H.setPad(aPh < 4 and { "a" } or {})
          return
        end
        if H.dialogWaiting() then
          H.setPad(aPh < 4 and { "a" } or {})
          return
        end
        H.setPad({})
      end),
    }, "the win tail to the party menu")
  end)(),

  -- party_menu 1, RESET: TERRA is deleted, so the pool is LOCKE CYAN EDGAR
  -- SABIN CELES GAU at cells 0-5.  LOCKE+CELES+EDGAR+SABIN form the party.
  H.waitUntil(function() return mst() == 0x2d end, 900, "menu at $2d", 5),
  H.waitFrames(20),
  H.call(function()
    local pool = {}
    for c = 0, 15 do pool[#pool + 1] = string.format("%02X", cell9d(c)) end
    H.log("[assign] pool: " .. table.concat(pool, " "))
    for i, want in ipairs({ 0x01, 0x02, 0x04, 0x05, 0x06, 0x0B }) do
      H.assertEq(cell9d(i - 1), want,
        string.format("pool cell %d is char $%02X", i - 1, want))
    end
  end),
  H.partySelect({ 0x01, 0x06, 0x04, 0x05 },  -- LOCKE CELES EDGAR SABIN
    { tag = "assign", menuWait = 600 }),
  H.logStep("party committed; riding _ccc1b5's reload to control"),

  -- the remainder: NPC creates, load_map 30 {60,37}, fade_in, ctrl on
  H.advanceStory(landed(30, 60), 8000, { playBattles = true }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 30, "landed in Arvis's house (map 30)")
    H.assertEq(H.fieldX() == 60 and H.fieldY() == 37, true,
      "party at {60,37}, _ccc1b5's reload spot")
    H.assertEq(partyOf(0x01), 1, "LOCKE in the party")
    H.assertEq(partyOf(0x06), 1, "CELES in the party")
    H.assertEq(partyOf(0x04), 1, "EDGAR in the party")
    H.assertEq(partyOf(0x05), 1, "SABIN in the party")
    H.assertEq(partyOf(0x02), 0, "CYAN stays to guard Narshe")
    H.assertEq(partyOf(0x0B), 0, "GAU stays to guard Narshe")
    H.assertEq(partyOf(0x00), 0, "TERRA is gone")
    H.assertEq(sw(0x0139), 1, "$0139 SET -- the battle-won flag")
    H.assertEq(sw(0x0612), 0, "$0612 clear -- KEFKA gone")
    H.assertEq(sw(0x061D), 0, "raiders retired")
    -- the tail-completion flags are set only once _ccc1b5's caller runs
    -- to its return
    H.assertEq(sw(0x0602), 1, "$0602 SET -- the post-menu stretch ran")
    H.assertEq(sw(0x010B), 1, "$010B SET -- ditto")
    H.assertEq(sw(0x0048), 1, "$0048 SET -- ditto")
    H.log(string.format("[kefka_won] f%d map=%d (%d,%d)",
      H.frame, H.mapId(), H.fieldX(), H.fieldY()))
    H.screenshot("kefka_won")
  end),

  H.openChest{ stand = { 55, 31 }, face = "up", bit = 2, what = "Elixir",
               nav = { playBattles = "tactical" } },
  -- back to the reload spot, approached from the north so the saved facing
  -- stays DOWN, the way _ccc1b5's reload left it
  H.navTo(60, 36, { playBattles = "tactical" }),
  H.navTo(60, 37, { playBattles = "tactical" }),
  H.call(function()
    H.assertEq(map() == 30 and H.fieldX() == 60 and H.fieldY() == 37, true,
      "back at {60,37} for the exit contract")
  end),
  H.saveState("kefka_won.mss"),
  H.logStep(function()
    return string.format("kefka_won generated at frame %d -- v0.4's first link", H.frame)
  end),

  -- ===================================================================== --
  -- Out of Narshe, by its item shop, and a world save outside the south
  -- gate: the cut gen_zozo1_submerge boots from (savestate_graph.py;
  -- lib/ot6_contract.lua "kefka-won-v1").  This walk was gen_zozo1's first
  -- two steps.
  -- ===================================================================== --

  -- 1. Arvis's house -> Narshe town by the front door (55,35) -> map 20
  --    {49,14}.  Tier 1's invisible door-NPC no longer stands there
  --    (probe_n30: reachable in 9, tile unoccupied), and the tier-1
  --    corridor exit's (53,8) clifftop position is isolated after the
  --    battle (probe_n20 survey after full settle: zero reachable tiles),
  --    so the front door is now the only way to the streets.
  H.navTo(55, 35, { arrive = function() return map() == 20 end,
                    maxFrames = 12000, playBattles = "tactical" }),
  H.waitUntil(landed(20, 10), 1200, "landed on the streets", 1),
  H.waitFrames(150),

  -- 1b. Narshe's item shop on the way out (#176): the door (41,22) is eight
  --     tiles from Arvis's front door, shop 3 on map 26 (shopkeeper (44,8);
  --     _ccd28c opens 3 while $006B/$00A4 are clear, both clear here), rows
  --     TONIC 0 / POTION 1 / FENIX DOWN 4.  Every town tops up, and this is
  --     the last TONIC counter before the post-opera checkpoint: Jidoor's
  --     shop 22 (gen_zozo2_arrival's stop after the L18 grind) sells none,
  --     and the #158 chain walked the grind and the Zozo climb from 82 Tonics
  --     to 14 (zozo_arrival attempt 3 "[west landing] ... tonic=82";
  --     zozo_done "[care before leaving Zozo] ... tonic=14").  No Potion
  --     line: Nikeah's stop (gen_sabin_trench) now carries 27 to here
  --     (kefka_won potion=27, over the L14 band of 21) and Jidoor buys the
  --     L18 band after the grind, so a POTION line here buys nothing.
  H.call(function()
    H.vars.shopStart = H.frame
    H.assertEq(sw(0x006B), 0, "$006B clear -- the item shop opens as shop 3")
    H.assertEq(sw(0x00A4), 0, "$00A4 clear -- the item shop opens as shop 3")
    H.log(string.format("[shop] Narshe stop begins f%d: gil=%d tonic=%d potion=%d fenix=%d",
      H.frame, H.gil(), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN)))
  end),
  H.crossDoor(41, 22, 26, 44, 13, "item shop door 20(41,22)->26(44,13)"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 2400,
    "shop interior settled", 10),
  H.waitFrames(60),
  H.shopTalk(44, 8, "Narshe item shop"),
  H.call(function()
    -- event command $9b parks the shop number at $0201 (field/event.asm:3656);
    -- the rows come from the ROM table, since the menu fills its $7E9D89 row
    -- list only once the buy list is drawn.
    H.assertEq(H.readByte(0x0201), 3, "the counter opened shop 3 ($0201)")
    H.assertEq(shopRow(3, 0), TONIC, "shop 3 row 0 is Tonic")
    H.assertEq(shopRow(3, 1), POTION, "shop 3 row 1 is Potion")
    H.assertEq(shopRow(3, 4), FENIX_DOWN, "shop 3 row 4 is Fenix Down")
    H.assertEq(shopRow(3, 2), TINCTURE, "shop 3 row 2 is Tincture")
  end),
  H.buyItem(FENIX_DOWN, 4, function() return 15 - H.invCountOf(FENIX_DOWN) end,
    "FENIX DOWN to 15"),
  -- TINCTURE to 4 (#231): the MP column of the supply band, ~level / 4 at
  -- the L14 this party holds (docs/design/supply.md).  This is the first
  -- Tincture counter whose purse can carry them (Figaro Castle's could
  -- not), and nothing from here to Jidoor sells one.  6000 gil of the
  -- 16,871 kefka_won holds; after the revives and before the Tonic soak,
  -- so a short purse shorts Tonics first.
  H.buyItem(TINCTURE, 2, function() return 4 - H.invCountOf(TINCTURE) end,
    "TINCTURE to 4"),
  H.buyItem(TONIC, 0, function() return 99 - H.invCountOf(TONIC) end, "TONIC to 99"),
  H.call(function()
    H.log(string.format("[shop] Narshe item shop done: tonic=%d potion=%d fenix=%d tincture=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN),
      H.invCountOf(TINCTURE), H.gil(), H.frame))
  end),
  H.shopClose("Narshe item shop"),
  -- #197: the combat items back on top of the bag after every purchase
  -- (the fight driver found the Potion at row 43 downstream of a stop
  -- that did not re-arrange)
  H.bagArrange({ POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY }, { tag = "bag: combat items on top (Narshe item shop)" }),
  H.call(function()
    H.assertEq(H.invCountOf(FENIX_DOWN) >= 15, true, "Fenix Downs at 15 for the Zozo stretch")
    H.assertEq(H.invCountOf(TINCTURE) >= 4, true, "Tinctures at 4, the L14 MP band (#231)")
    H.assertEq(H.invCountOf(TONIC) >= 90, true, "Tonics topped up for the field care")
    H.log(string.format("[shop] leaving the shop: gil=%d tonics=%d potions=%d fenix=%d",
      H.gil(), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN)))
  end),
  H.crossDoor(44, 14, 20, 41, 24, "item shop door 26(44,14)->20(41,24), return"),
  H.call(function()
    H.log(string.format("[shop] Narshe stop cost %d frames (f%d -> f%d)",
      H.frame - H.vars.shopStart, H.vars.shopStart, H.frame))
  end),

  -- 2. the south gate at (38,61) (gen_worldmap's verified tile), then one
  --    held step south onto the y=62 exit row -> the world
  H.navTo(38, 61, { maxFrames = 20000, playBattles = "tactical" }),
  H.driveUntil(function() return H.worldMode() end, 900, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "off the south edge to the world"),
  H.waitWorldSettled("world control", 1200),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[world] at (%d,%d)", H.worldX(), H.worldY()))
  end),
  H.saveAtCheckpoint("kefka-won-v1"),
})
