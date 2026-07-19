-- probe_narshe_spike2.lua -- SPIKE phase 2 (poked lineage, never FRONTIER):
-- boots spike_staging.mss (probe_narshe_spike's map-22 staging), talks to
-- BANON {20,7}, answers "Prepared?", and DRIVES the `party_menu 3, RESET`
-- assignment for real using the machine probe_narshe_spike measured:
--
--   cursor cell = $4b + $4a + $5a; pool = cells 0-15 (two 8-wide rows,
--   $4e=row); party area ($4a=$10) = cells $10+4p+s, drawn as three 2x2
--   boxes with $4b = visualcol*2 + row.  $2d --A--> $2e --A--> swap the
--   two cells' chars, back to $2d.  Start in $2d commits iff every party
--   has a member (else state $69 for ~32 frames, self-recovers).
--
-- ASSIGNMENT (the fixed split the fixtures will use):
--   party 1 = TERRA + EDGAR + CELES  -- the Kefka party: fire (Terra),
--             tools/BioBlaster poison (Edgar), sword slash + Runic
--             (Celes) cover three of the four axes Kefka's authored
--             rows chip under (slash|pierce shields, poison|fire adds)
--   party 2 = CYAN + SABIN           -- slash + bludgeon, mid lane
--   party 3 = LOCKE + GAU            -- the remaining flank
-- The driver is STATE-FED: every press is chosen from the live cursor
-- cell and verified against the cell tables, so a 5-char pool (an
-- unstacked boot) or shifted layout drives identically.
--
-- After commit it rides the event tail ("They're coming!", the Kefka
-- cutscene, "Go!!", twelve marches launched, player_ctrl_on) to the
-- first controllable defense frame, asserts the assignment stuck in
-- $1850, mints spike_defense.mss, then PROVES Y-BUTTON PARTY SWITCHING:
-- $1a6d cycles 1->2->3->1 with position following each active party,
-- and navTo drives the NEW party after a switch ($0803 follow-up, the
-- untested lib assumption).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STAGING = "/Users/mtklein/ot6/build/states/spike_staging.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

-- ---------------------------------------------------------- menu driving --
local function mst() return H.readByte(0x0026) end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function cell9d(c) return H.readByte(0x7E9D89 + c) end
local function cursorCell()
  return H.readByte(0x004b) + H.readByte(0x004a) + H.readByte(0x005a)
end

-- decode a cell into {area, col, row}: pool cols 0-7 rows 0-1; party area
-- visual cols 0-5 rows 0-1 (party p = vcols 2p..2p+1)
local function decode(cell)
  if cell < 0x10 then
    return { area = "pool", col = cell % 8, row = cell >= 8 and 1 or 0 }
  end
  local b = cell - 0x10
  return { area = "party", col = b >> 1, row = b & 1 }
end

-- the next button that moves the cursor from `cur` toward `tgt`
local function stepToward(cur, tgt)
  local c, t = decode(cur), decode(tgt)
  if c.area == "pool" and t.area == "party" then
    return "down"                      -- row0 -> row1 -> party area
  elseif c.area == "party" and t.area == "pool" then
    return c.row == 1 and "up" or "up" -- row1 -> row0 -> pool row1
  elseif c.area == "pool" then
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
  else
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
  end
  return nil
end

-- one menu action: drive the cursor to cell `tgt` (edge presses, verified
-- against the live cursor each cycle), then press `btn` until the state
-- becomes `doneState`.  Once there, hands off -- an extra A after the
-- state flip would select the landing cell as a new source (measured
-- hazard: A on the cell the cursor stands on opens the status screen).
local function menuAct(tgt, btn, doneState, what)
  local phase = 0
  local settled = 0
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
      if mst() == 0x69 then H.setPad({}); return end  -- error splash: wait
      local cur = cursorCell()
      if cur ~= tgt then
        local b = stepToward(cur, tgt)
        if not b then H.setPad({}); return end
        -- edge press: 4 on / 6 off = one cursor step per cycle
        H.setPad(phase < 4 and { [b] = true } or {})
        return
      end
      H.setPad(phase < 4 and { [btn] = true } or {})
    end),
  }, what)
end

-- swap: pick src (pool cell) in $2d, drop on dst (party cell) in $2e
local function assign(srcCell, dstCell, charId, name)
  return H.cond(function() return true end, {
    H.waitUntil(function() return mst() == 0x2d end, 600,
      name .. ": menu back at $2d", 5),
    menuAct(srcCell, "a", 0x2e, name .. ": pick source"),
    menuAct(dstCell, "a", 0x2d, name .. ": drop on party slot"),
    H.call(function()
      H.assertEq(cell9d(dstCell), charId, name .. " landed in the party cell")
      H.assertEq(cell9d(srcCell), 0xFF, name .. "'s pool cell now empty")
    end),
  })
end

local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s (%d,%d) $59=%02X",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        H.fieldX(), H.fieldY(), H.readByte(0x0059)))
    end
    return cnt >= (n or 20)
  end
end

-- Y-switch: one edge press, then wait out the fade/reload to the new party
local function ySwitch(expectParty, expectX, expectY)
  return H.cond(function() return true end, {
    H.waitUntil(function()
      return H.hasControl() and H.tileAligned()
    end, 1200, "aligned+control before Y", 5),
    H.pressButtons({ "y" }, 6),
    H.waitUntil(function()
      return H.readByte(0x1a6d) == expectParty and H.hasControl()
         and H.tileAligned() and bright() >= 15
    end, 1200, string.format("party %d active after Y", expectParty), 5),
    H.waitFrames(20),
    H.call(function()
      H.assertEq(H.readByte(0x1a6d), expectParty, "$1A6D = active party")
      H.assertEq(H.fieldX(), expectX,
        string.format("party %d leader x (lib reads through $0803)", expectParty))
      H.assertEq(H.fieldY(), expectY,
        string.format("party %d leader y", expectParty))
      H.log(string.format("[yswitch] party %d at (%d,%d) $0803=%04X",
        expectParty, H.fieldX(), H.fieldY(), H.readWord(0x0803)))
    end),
  })
end

H.run({ maxFrames = 60000 }, {
  H.loadState(STAGING),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 22, "staging boot: map 22")
    H.assertEq(sw(0x0045), 1, "staging boot: $0045")
    H.assertEq(H.hasControl(), true, "staging boot: controllable")
  end),

  -- BANON {20,7}: stand at (20,8), face up, A. "Prepared? 0:Yes" -> A.
  H.navTo(20, 8, { maxFrames = 4000 }),
  (function()
    local aPh = 0
    return H.driveUntil(menuUp, 8000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if H.fieldX() == 20 and H.fieldY() == 8 then
          H.setPad(aPh < 4 and { "up" } or (aPh == 4 and { "a" } or {}))
          return
        end
        H.setPad({})
      end),
    }, "Banon -> Prepared? -> party menu")
  end)(),
  H.waitUntil(function() return mst() == 0x2d end, 900, "menu at $2d", 5),
  H.waitFrames(20),
  H.call(function()
    local pool = {}
    for c = 0, 15 do pool[#pool + 1] = string.format("%02X", cell9d(c)) end
    H.log("[assign] pool: " .. table.concat(pool, " "))
  end),

  -- THE ASSIGNMENT.  Pool cells (from spike 1): 0=TERRA 1=LOCKE 2=CYAN
  -- 3=EDGAR 4=SABIN 5=CELES 6=GAU.  Party cells $10+4p+s.
  assign(0, 0x10, 0x00, "TERRA -> P1s0"),
  assign(3, 0x11, 0x04, "EDGAR -> P1s1"),
  assign(5, 0x12, 0x06, "CELES -> P1s2"),
  assign(2, 0x14, 0x02, "CYAN -> P2s0"),
  assign(4, 0x15, 0x05, "SABIN -> P2s1"),
  assign(1, 0x18, 0x01, "LOCKE -> P3s0"),
  assign(6, 0x19, 0x0B, "GAU -> P3s1"),

  -- COMMIT: Start in $2d; _c37296 passes (all three parties occupied) and
  -- the menu exits.  Then the event tail runs the whole battle-start
  -- sequence; ride it to the first controllable defense frame.
  H.waitUntil(function() return mst() == 0x2d end, 600, "menu at $2d for commit", 5),
  H.pressButtons({ "start" }, 6),
  H.waitUntil(function() return not menuUp() end, 1200, "menu closed", 5),
  H.logStep("menu committed; riding the battle-start event"),
  H.advanceStory(landed(22), 30000),
  H.waitFrames(30),

  H.call(function()
    H.assertEq(map(), 22, "defense: map 22")
    H.assertEq(sw(0x0132), 1, "defense LIVE: $0132 set (the map-init gate)")
    H.assertEq(sw(0x0612), 1, "$0612 set -- KEFKA's NPC is on the map")
    H.assertEq((H.readByte(0x1eb9) & 0x40) ~= 0, true,
      "$01CE set -- Y party switching enabled")
    H.assertEq(H.readByte(0x1a6d), 1, "party 1 active")
    H.assertEq(H.fieldX(), 20, "party 1 at x=20")
    H.assertEq(H.fieldY(), 10, "party 1 at y=10")
    -- the RAM proof the assignment took: $1850 low 3 bits per character
    H.assertEq(partyOf(0), 1, "TERRA in party 1 ($1850)")
    H.assertEq(partyOf(4), 1, "EDGAR in party 1")
    H.assertEq(partyOf(6), 1, "CELES in party 1")
    H.assertEq(partyOf(2), 2, "CYAN in party 2")
    H.assertEq(partyOf(5), 2, "SABIN in party 2")
    H.assertEq(partyOf(1), 3, "LOCKE in party 3")
    H.assertEq(partyOf(11), 3, "GAU in party 3")
    -- all twelve raider switches up
    for id = 0x061C, 0x0627 do
      H.assertEq(sw(id), 1, string.format("raider switch $%04X set", id))
    end
    H.screenshot("spike_defense")
  end),
  H.saveState("spike_defense.mss"),

  -- ==================================================================== --
  -- Y-BUTTON PARTY SWITCHING (the untested $0803-follow assumption).
  -- Parties: 1 @ {20,10}, 2 @ {18,10}, 3 @ {22,10} (event_main:107843+).
  -- ==================================================================== --
  ySwitch(2, 18, 10),
  ySwitch(3, 22, 10),
  ySwitch(1, 20, 10),
  H.logStep("Y cycles 1->2->3->1 and $0803 follows; navTo check next"),
  -- navTo across a switch: swap to party 2 and WALK it somewhere nearby.
  ySwitch(2, 18, 10),
  H.navTo(18, 12, { maxFrames = 3000 }),
  H.call(function()
    H.assertEq(H.readByte(0x1a6d), 2, "still party 2 after the walk")
    H.assertEq(H.fieldX() == 18 and H.fieldY() == 12, true,
      "navTo drove the NEW active party (the $0803-follow verdict: PASS)")
    H.log(string.format("[navcheck] party 2 walked to (%d,%d)",
      H.fieldX(), H.fieldY()))
  end),
  -- back to party 1 the only way Y goes: forward around the cycle (2->3->1;
  -- run 1 expected 2->1 off a single press and timed out for it)
  ySwitch(3, 22, 10),
  ySwitch(1, 20, 10),
  H.call(function() H.screenshot("spike_defense_y") end),
  H.logStep(function()
    return string.format("spike 2 complete at f%d", H.frame)
  end),
})
