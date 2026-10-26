-- @suite slow savestate=wor_colosseum_in
-- battle_colosseum.lua -- the World of Ruin Colosseum's wager, played through the real menus (H.colosseumBet;
-- docs/design/route-wor-colosseum.md section 2).
--
--   tools/tests/run.sh tools/tests/battle_colosseum.lua
--
-- Boots wor_colosseum_in (gen_wor_colosseum: CELES, RELM, CYAN and TERRA inside the Colosseum, before the
-- guard, the bag as wor-ancient-v1 left it and Kohlingen's counter topped it) and wagers the Regal Crown, the
-- route's own wager against the Opinicus:
--   1. the guard's prompt, the wager list and the fighter: the Regal Crown taken ($0205), the opponent the
--      Colosseum's record names ($0206: the Opinicus, $C8), its prize ($0207: the Genji Helmet), and the
--      fighter a player sends (the seated member of the highest level, then the most HP) sent ($0208);
--   2. the fight is the Colosseum's: formation $23F, the fighter alone in seat 0 with the colosseum mode set
--      ($3A97), and nothing pressed;
--   3. the outcome is read right: a Colosseum battle pays no experience, so the outcome's reward is 0 and the
--      fighter's experience does not move ("paid as due", M.lastOutcome.ok);
--   4. the wager is spent, and a win adds the prize while a loss adds nothing and leaves the fighter down.
-- Nothing is written.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_colosseum_in.mss.lua"
local REGAL_CROWN, GENJI_HELMET, OPINICUS = 0x7B, 0x81, 0xC8
local inBattle = nil
local had, prizeHad, xp0, fighter = 0, 0, 0, nil

emu.addMemoryCallback(function()
  if inBattle ~= nil then return end
  inBattle = { form = H.readWord(0x11E0), mode = H.readByte(0x3A97), seat0 = H.readByte(0x3ED8),
    seat1 = H.readByte(0x3EDA), f = H.frame }
end, emu.callbackType.exec, H.sym("UpdateSRAM"), H.sym("UpdateSRAM"))

H.run({ maxFrames = 120000 }, {
  H.loadState(STATE),
  H.call(function()
    H.assertEq(H.mapId() & 0x1FF, 413, "in the Colosseum (map 413)")
    H.assertEq(H.invCountOf(REGAL_CROWN) > 0, true, "the bag holds the Regal Crown")
    had, prizeHad = H.invCountOf(REGAL_CROWN), H.invCountOf(GENJI_HELMET)
    -- the fighter a player sends, read here on its own: the seated, standing member of the highest level, then
    -- the most HP
    local bl, bh = -1, -1
    for c = 0, 13 do
      local up = H.readWord(0x1600 + 37 * c + 9) > 0 and (H.readByte(0x1600 + 37 * c + 0x14) & 0x80) == 0
      if (H.readByte(0x1850 + c) & 7) == 1 and up then
        local l, h = H.readByte(0x1600 + 37 * c + 8), H.readWord(0x1600 + 37 * c + 11) & 0x3FFF
        if l > bl or (l == bl and h > bh) then fighter, bl, bh = c, l, h end
      end
    end
    xp0 = H.readByte(0x1600 + 37 * fighter + 0x11) | (H.readByte(0x1600 + 37 * fighter + 0x12) << 8)
      | (H.readByte(0x1600 + 37 * fighter + 0x13) << 16)
    H.log(string.format("[colosseum] the fighter: char %d L%d, %d experience", fighter,
      H.readByte(0x1600 + 37 * fighter + 8), xp0))
  end),
  H.colosseumBet(REGAL_CROWN, { what = "battle_colosseum: the Regal Crown" }),
  H.call(function()
    -- 1. the menus (read by H.colosseumBet as they closed: the field menu's care reuses the cells after)
    local b = H.colosseumLog[#H.colosseumLog]
    H.assertEq(b ~= nil and b.item, REGAL_CROWN, "1. the wager taken ($0205)")
    H.assertEq(b.opponent, OPINICUS, "1. the opponent the record names ($0206: the Opinicus)")
    H.assertEq(b.prize, GENJI_HELMET, "1. the prize ($0207: the Genji Helmet)")
    H.assertEq(b.fighter, fighter, "1. the fighter sent is the seated member of the highest level, then HP ($0208)")
    -- 2. the Colosseum's fight
    H.assertEq(inBattle ~= nil, true, "2. a battle ran")
    H.assertEq(inBattle.form, 0x23F, "2. the Colosseum's formation ($11E0)")
    H.assertEq(inBattle.mode ~= 0, true, "2. the colosseum mode ($3A97) is set in it")
    H.assertEq(inBattle.seat0, fighter, "2. the fighter alone in seat 0 ($3ED8)")
    H.assertEq(inBattle.seat1, 0xFF, "2. seat 1 empty ($3EDA)")
    -- 3. the outcome
    local o = H.lastOutcome
    H.assertEq(o ~= nil and o.form & 0x3FF, 0x23F, "3. the outcome read is the Colosseum battle's")
    H.assertEq(o.due, 0, "3. a Colosseum battle pays no experience (the outcome's reward)")
    H.assertEq(o.ok, true, "3. the outcome reads paid as due")
    local xp1 = H.readByte(0x1600 + 37 * fighter + 0x11) | (H.readByte(0x1600 + 37 * fighter + 0x12) << 8)
      | (H.readByte(0x1600 + 37 * fighter + 0x13) << 16)
    H.assertEq(xp1, xp0, "3. the fighter's experience does not move")
    -- 4. the wager and the prize
    H.assertEq(H.invCountOf(REGAL_CROWN), had - 1, "4. the wager is spent")
    if b.won then
      H.assertEq(H.invCountOf(GENJI_HELMET), prizeHad + 1, "4. a win adds the prize")
    else
      H.assertEq(H.invCountOf(GENJI_HELMET), prizeHad, "4. a loss adds nothing")
      H.assertEq(H.readWord(0x1600 + 37 * fighter + 9), 0, "4. a loss leaves the fighter down")
    end
    H.log(string.format("[colosseum] PASS: the wager %s", b.won and "won" or "lost"))
  end),
})
