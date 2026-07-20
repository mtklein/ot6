-- gen_kefka_won.lua -- v0.4's FIRST link: boot kefka_doorstep, win battle 57
-- again (kill-bit; the $40 scripted win), ride the whole win tail -- the
-- esper cliff on map 23, TERRA's morph, the flight across the world, the
-- regroup in Arvis's house -- through the party-select menu to the first
-- controllable frame, and mint kefka_won.mss on map 30 at (60,37).
--
-- THE WIN TAIL IS THREE DIFFERENT WAITS, none of them a field dialog with
-- missing flags (issue #3's original theory).  Each one measured
-- (probe_esper_stall + this file's own bring-up, 2026-07-20):
--
--  1. battle 78 at $CCBEB7 (event_main.asm:106707) -- the event PC parks at
--     $CCBEBA, the resume address AFTER the battle command, until the
--     battle returns.  Battle 78 = group $4E -> formation 448 both slots =
--     TRITOCH_MORPH ($0115) alone vs TERRA alone.  Its whole AI is
--     `battle_event $12 / end_battle` on its first main turn
--     (ai_script.asm:5077): the set-piece ends ITSELF, but its battle-event
--     dialogs are BATTLE text -- they never raise the field's $00BA/$00D3
--     (that is the real story behind "dialogs present but flags read 0").
--     And battleLoadStarted() is BLIND to this battle: it reads party
--     battle-HP slot 0, and TERRA alone leaves slot 0 at $FFFF.  So
--     advanceStory neither taps (no dialogWaiting, no battN) nor kill-bits
--     -- hands off forever was the ORIGINAL $CCBEBA stall (632af69).  The
--     set-piece is detected here by its formation word instead ($57C0
--     slot 0 in the TRITOCH set -- $FFFF outside the fight on this route,
--     measured f600..f11600): hands off through the load (A queued during
--     a set-piece load wedges the turn engine -- the intro-Tritoch twin's
--     measured failure, see advanceStory's spare notes), then edge-tap the
--     battle-event text.
--  2. The vehicle flight (map 0, ~900 frames) and every field dialog: the
--     dialogs DO raise $00BA/$00D3 and park the event PC at $CA0001
--     (WaitDlg), so dialogWaiting-gated taps advance them.  Nothing else
--     wants input.
--  3. party_menu 1, RESET at _cacb9f (event_main.asm:31284, called from
--     _ccc1b5) -- the "who hunts TERRA" selection.  632af69's
--     tap-A-at-everything drive DID clear waits 1 and 2, then wedged HERE:
--     blind A walks into the menu and parks on a character's Status page
--     (screenshotted), where A never exits and Start never commits --
--     $0059 stays $81, $0602/$0048/$010B stay clear, timeout.  The menu
--     wants gen_narshe_battle's state-fed driver: cursor cell = $4b+$4a+
--     $5a, cells verified in $7E9D89, Start commits.  LOCKE+CELES+EDGAR+
--     SABIN go in -- the story-canonical search party and a full bench for
--     the Zozo arc this fixture boots.
--
-- After the menu: _ccc1b5 reloads map 30 at {60,37} facing DOWN, sets
-- $0602/$010B/$0048, set_parent_map 0 {84,33}, player_ctrl_on, return
-- (event_main.asm:107272,107193-107208).  That calm is the mint.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

-- the esper-zap species set, same triple gen_arvis spares for the intro twin
local TRITOCH = { [0x0114] = true, [0x0115] = true, [0x0144] = true }

local function map() return H.mapId() & 0x1ff end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

-- ---------------------------------------------------------- menu driving --
-- gen_narshe_battle's state-fed party-menu driver, on the 1-party layout:
-- pool rows 8 wide (cells 0-15), party 0's four slots at cells $10-$13.
local function mst() return H.readByte(0x0026) end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function cell9d(c) return H.readByte(0x7E9D89 + c) end
local function cursorCell()
  return H.readByte(0x004b) + H.readByte(0x004a) + H.readByte(0x005a)
end
local function decode(cell)
  if cell < 0x10 then
    return { area = "pool", col = cell % 8, row = cell >= 8 and 1 or 0 }
  end
  local b = cell - 0x10
  return { area = "party", col = b >> 1, row = b & 1 }
end
local function stepToward(cur, tgt)
  local c, t = decode(cur), decode(tgt)
  if c.area == "pool" and t.area == "party" then return "down"
  elseif c.area == "party" and t.area == "pool" then return "up"
  elseif c.area == "pool" then
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
  else
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
  end
  return nil
end
local function menuAct(tgt, btn, doneState, what)
  local phase, settled = 0, 0
  return H.driveUntil(function()
    return mst() == doneState and cursorCell() == tgt and settled >= 8
  end, 4000, {
    H.call(function()
      phase = (phase + 1) % 10
      if mst() == doneState then
        settled = settled + 1
        H.setPad({})
        return
      end
      settled = 0
      if mst() == 0x69 then H.setPad({}); return end
      local cur = cursorCell()
      if cur ~= tgt then
        local b = stepToward(cur, tgt)
        if not b then H.setPad({}); return end
        H.setPad(phase < 4 and { [b] = true } or {})
        return
      end
      H.setPad(phase < 4 and { [btn] = true } or {})
    end),
  }, what)
end
local function assign(srcCell, dstCell, charId, name)
  return H.cond(function() return true end, {
    H.waitUntil(function() return mst() == 0x2d end, 600,
      name .. ": menu at $2d", 5),
    menuAct(srcCell, "a", 0x2e, name .. ": pick"),
    menuAct(dstCell, "a", 0x2d, name .. ": drop"),
    H.call(function()
      H.assertEq(cell9d(dstCell), charId, name .. " in the party cell")
      H.assertEq(cell9d(srcCell), 0xFF, name .. "'s pool cell empty")
    end),
  })
end
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

H.run({ maxFrames = 90000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/kefka_doorstep.mss.lua"),
  H.waitFrames(30),

  -- the doorstep is one clean edge-A from battle 57 (gen_narshe_battle
  -- minted it there and proved the activation)
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.cond(function() return true end, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }),
  }, "clean A into KEFKA -> battle 57"),
  H.waitUntil(function() return H.battleActive() end, 3000, "Kefka up", 10),
  H.waitFrames(150),
  (function()
    local aPh = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end,
      20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.monstersPresent() > 0 then killBitAll() end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "Kefka down (kill-bit; the $40 win)")
  end)(),

  -- THE WIN TAIL, wait by wait (see the header): dialog-gated taps for the
  -- field dialogs, the zap recipe for battle 78, hands off otherwise, and
  -- STOP at the party menu -- blind A must never reach it.
  -- The menu detector is a COMPOSITE on purpose: $0059 alone rises to $52
  -- during battle 78's transition (measured f3499) and blips $FF/$01 at the
  -- vehicle handoff (f7037), so menuUp() alone fires 7000 frames early.
  -- The real party menu shows $59=$81 with menu mode $0200=4 and the pick
  -- state $26=$2d once interactive -- all three together only there.
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
            "tail f%d map=%d (%d,%d) dlg=%s ev=%s zapN=%d battN=%d",
            H.frame, map(), H.fieldX(), H.fieldY(),
            tostring(H.dialogWaiting()), tostring(H.eventRunning()),
            zapN, battN))
        end
        if zapN > 0 then
          -- the morph set-piece: silence through the load, then edge-tap
          -- its battle-event text; it ends itself (end_battle)
          H.setPad(zapN > 300 and aPh < 4 and { "a" } or {})
          return
        end
        if battN >= 3 then
          -- no other battle exists on this route; kill-bit a stray anyway
          if H.monstersPresent() > 0 then killBitAll() end
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
  assign(0, 0x10, 0x01, "LOCKE -> slot 0"),
  assign(4, 0x11, 0x06, "CELES -> slot 1"),
  assign(2, 0x12, 0x04, "EDGAR -> slot 2"),
  assign(3, 0x13, 0x05, "SABIN -> slot 3"),
  H.waitUntil(function() return mst() == 0x2d end, 600, "menu at $2d for commit", 5),
  H.pressButtons({ "start" }, 6),
  H.waitUntil(function() return not menuUp() end, 1200, "menu closed", 5),
  H.logStep("party committed; riding _ccc1b5's reload to control"),

  -- the remainder: NPC creates, load_map 30 {60,37}, fade_in, ctrl on
  H.advanceStory(landed(30, 60), 8000),
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
    H.assertEq(sw(0x0139), 1, "$0139 SET -- the battle-won latch")
    H.assertEq(sw(0x0612), 0, "$0612 clear -- KEFKA gone")
    H.assertEq(sw(0x061D), 0, "raiders retired")
    -- the tail-completion latches: clear at 632af69's menu wedge, set only
    -- once _ccc1b5's caller ran to its return (event_main.asm:107194-107208)
    H.assertEq(sw(0x0602), 1, "$0602 SET -- the post-menu stretch ran")
    H.assertEq(sw(0x010B), 1, "$010B SET -- ditto")
    H.assertEq(sw(0x0048), 1, "$0048 SET -- ditto")
    H.log(string.format("[kefka_won] f%d map=%d (%d,%d)",
      H.frame, H.mapId(), H.fieldX(), H.fieldY()))
    H.screenshot("kefka_won")
  end),
  H.saveState("kefka_won.mss"),
  H.logStep(function()
    return string.format("kefka_won minted at frame %d -- v0.4's first link", H.frame)
  end),
})
