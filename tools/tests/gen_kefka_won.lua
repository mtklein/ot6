-- gen_kefka_won.lua -- boot kefka_entry, win battle 57 with real input on
-- one attempt (a loss is the runner's to count and retry).  Then ride the
-- whole win tail (the esper cliff on map 23, TERRA's morph, the flight
-- across the world, the regroup in Arvis's house) through the party-select
-- menu to the first controllable frame, and generate kefka_won.mss on map
-- 30 at (60,37).

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
})
