-- probe_narshe_spike.lua -- SPIKE, not a fixture: capability probe for the
-- Battle for Narshe.  Boots locke_done, POKES the other two scenario flags
-- ($0021/$0044) and the event PC onto _caad4c -- the hub-return dispatcher
-- whose if_all (event_main.asm:26654) is the reunion gate -- and rides the
-- reunion cutscene _ccb4da to the map-22 staging.  Then talks to BANON
-- {20,7} (_ccc605), answers "Prepared?", and characterizes the
-- `party_menu 3, RESET` machine EMPIRICALLY: state dumps + a scripted
-- button trace with per-press RAM logs.  NO COMMIT here -- the driver is
-- written from this probe's log, not guessed.
--
-- POKED means: never wired into FRONTIER, and the states it emits carry the
-- spike_ prefix.  The honest boot is the stacked chain (OT6_STACK, the t2_
-- rules); this probe only proves the mechanisms downstream of the reunion.
--
-- WHY POKING THE EVENT PC IS SOUND: the interpreter idles parked at
-- EventScript_NoEvent with the call stack EMPTY ($e8=0, InitEvent
-- field/event.asm:28-47), and a real scenario ending reaches _caad4c by a
-- plain `call` from that same interpreter.  Writing {$e5,$e6,$e7}=CA:AD4C
-- with $e8/$e1/$e3 zeroed reproduces the dispatch state exactly; the
-- script runs the identical opcodes from there, including the if_all that
-- reads the (poked) $1E80 bitfield.
--
-- KNOWN DELTA FROM THE HONEST BOOT: locke_done has never run SABIN's
-- scenario, so CYAN and GAU are not in the roster and the party-select
-- pool will show 5 characters, not 7.  Structure (states, cursor
-- geometry, commit rule) is what this probe is after; the driver written
-- from it must therefore be POSITION-AGNOSTIC (state-fed, not a canned
-- press list) so the 7-char honest run drives the same.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local BOOT = "/Users/mtklein/ot6/build/states/locke_done.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function swSet(id)
  local a = 0x1e80 + (id >> 3)
  H.writeByte(a, H.readByte(a) | (1 << (id & 7)))
end

-- menu module RAM (DP=0 absolutes): state $26, cursor cluster $4a/$4b/$5a
-- + party index $99; $0200/$0201 = menu command / parties byte;
-- char cell tables $7E9D89 (chars) and $7EAC8D (selectability).
local function mst() return H.readByte(0x0026) end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function mdump(tag)
  local cells9d, cellsac = {}, {}
  for i = 0, 0x1F do
    cells9d[#cells9d + 1] = string.format("%02X", H.readByte(0x7E9D89 + i))
    cellsac[#cellsac + 1] = string.format("%02X", H.readByte(0x7EAC8D + i))
  end
  H.log(string.format(
    "[menu %s] f%d st=%02X nxt=%02X $49=%02X $4a=%02X $4b=%02X $4d=%02X%02X " ..
    "$4e=%02X $5a=%02X $5b=%02X $99=%02X $0200=%02X $0201=%02X",
    tag, H.frame, mst(), H.readByte(0x0027), H.readByte(0x0049),
    H.readByte(0x004a), H.readByte(0x004b), H.readByte(0x004e),
    H.readByte(0x004d), H.readByte(0x004e), H.readByte(0x005a),
    H.readByte(0x005b), H.readByte(0x0099),
    H.readByte(0x0200), H.readByte(0x0201)))
  H.log("[menu " .. tag .. "] 9D89: " .. table.concat(cells9d, " "))
  H.log("[menu " .. tag .. "] AC8D: " .. table.concat(cellsac, " "))
end

-- one edge press inside the menu, then a settle, then a dump
local function mpress(btn, tag)
  return H.cond(function() return true end, {
    H.hold({ btn }), H.waitFrames(4), H.release(), H.waitFrames(10),
    H.call(function() mdump(tag) end),
  })
end

local function partyOf(c)               -- $1850+c low 3 bits = party number
  return H.readByte(0x1850 + c) & 0x07
end
local function rosterLine(tag)
  local t = {}
  for c = 0, 15 do
    local p = partyOf(c)
    if p ~= 0 or (H.readByte(0x1600 + 37 * c) ~= 0) then
      t[#t + 1] = string.format("c%d:p%d", c, p)
    end
  end
  H.log("[" .. tag .. "] char->party: " .. table.concat(t, " "))
end

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
  H.loadState(BOOT),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 9, "booted at the hub")
    H.assertEq(sw(0x001E), 1, "$001E set (locke_done)")
    -- THE POKE (spike-only): complete the other two scenarios by write,
    -- then dispatch the hub-return event by hand.
    swSet(0x0021)
    swSet(0x0044)
    H.assertEq(sw(0x0021), 1, "$0021 poked")
    H.assertEq(sw(0x0044), 1, "$0044 poked")
    -- Dispatch _caad4c the way CheckEventTriggers::DoTrigger does
    -- (field/event.asm:5787-5815), field for field.  Run 1 poked ONLY the
    -- PC with $e8=0 and the walker froze at the staging (mv=00): the
    -- final top-level `return` (EventCmd_fe:5160) restores the walker's
    -- movement type ONLY when the stack pops back to exactly x=0, and an
    -- un-pushed dispatch underflows past it -- the restore never ran and
    -- TERRA kept movement type 0.  The frame below is what a real trigger
    -- pushes: parking address at level 0, loop count 1 at $05c7, $e8=3,
    -- movement type saved to $087d and set to 4 (event-controlled).
    local y = H.readWord(0x0803)
    H.writeByte(0x00e5, 0x4C)   -- event pc = $CA:AD4C = _caad4c
    H.writeByte(0x00e6, 0xAD)
    H.writeByte(0x00e7, 0xCA)
    H.writeByte(0x05f4, 0x4C)   -- subroutine start, level 0
    H.writeByte(0x05f5, 0xAD)
    H.writeByte(0x05f6, 0xCA)
    H.writeWord(0x0594, 0x0000) -- return-to: EventScript_NoEvent
    H.writeByte(0x0596, 0xCA)
    H.writeByte(0x05c7, 1)      -- loop count for the pushed frame
    H.writeWord(0x00e8, 3)      -- stack pointer past the pushed frame
    H.writeWord(0x0871 + y, 0)  -- the trigger's object-field clears
    H.writeWord(0x0873 + y, 0)
    H.writeByte(0x087e + y, 0)
    H.writeByte(0x078e, 1)
    H.writeByte(0x087d + y, H.readByte(0x087c + y))  -- save movement type
    H.writeByte(0x087c + y, 4)                       -- event-controlled
    H.writeByte(0x00e1, 0)      -- not waiting
    H.writeByte(0x00e3, 0)      -- no pause
    H.writeByte(0x00e2, 0x80)   -- no object wait
    H.log("event _caad4c dispatched (full DoTrigger frame); riding the reunion")
  end),
  -- the reunion: maps 9 -> 30 (Arvis) -> 56 -> 19 -> 21 -> 22 staging.
  -- pure cutscene: dialogs to tap, zero battles, zero choices.  Arrival is
  -- judged WITHOUT hasControl -- run 1 sat 45k frames at (20,9) with
  -- ctl=false and starved every later phase of its evidence -- so the
  -- state is minted and the control gates DUMPED before anything is
  -- demanded of them.
  H.advanceStory((function()
    local cnt = 0
    return function()
      local ok = map() == 22 and not H.eventRunning() and H.tileAligned()
             and bright() >= 15 and not H.dialogWaiting()
      cnt = ok and cnt + 1 or 0
      return cnt >= 120
    end
  end)(), 60000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 22, "the reunion ends on map 22, the battlefield")
    H.assertEq(H.fieldX(), 20, "staging spawn x=20")
    H.assertEq(H.fieldY(), 9, "staging spawn y=9")
    H.assertEq(sw(0x0045), 1, "$0045 set by the staging handoff (:106345)")
    rosterLine("staging")
    local po = H.readWord(0x0803)
    H.log(string.format(
      "[staging ctl] $1EB9=%02X $84=%02X $59=%02X $0803=%04X mv=%02X " ..
      "ev=%s batt=%s $1A6D=%02X hasControl=%s",
      H.readByte(0x1eb9), H.readByte(0x0084), H.readByte(0x0059), po,
      H.readByte(0x087c + po), tostring(H.eventRunning()),
      tostring(H.battleLoadStarted()), H.readByte(0x1a6d),
      tostring(H.hasControl())))
    H.screenshot("spike_staging")
  end),
  H.saveState("spike_staging.mss"),
  -- movement reality check: whatever hasControl says, does a held press
  -- move the party?  (If it does, the lib's gate is wrong for this map,
  -- and WHICH byte lied is already in the dump above.)
  H.hold({ "down" }), H.waitFrames(30), H.release(), H.waitFrames(10),
  H.call(function()
    H.log(string.format("[move check] after 30f of down: (%d,%d) ctl=%s",
      H.fieldX(), H.fieldY(), tostring(H.hasControl())))
  end),
  H.hold({ "up" }), H.waitFrames(30), H.release(), H.waitFrames(10),
  H.call(function()
    H.log(string.format("[move check] after 30f of up: (%d,%d)",
      H.fieldX(), H.fieldY()))
  end),

  -- ==================================================================== --
  -- BANON {20,7}: two tiles up.  navTo one short, face up, edge-A, choice
  -- "Prepared? 0:Yes" -> A picks option 0.  Then the map-5 info scene
  -- (its own choice converges either way) and the party menu.
  -- ==================================================================== --
  H.navTo(20, 8, { maxFrames = 4000 }),
  (function()
    local aPh = 0
    return H.driveUntil(menuUp, 6000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        -- at (20,8): face/press up into Banon, then A to activate
        if H.fieldX() == 20 and H.fieldY() == 8 then
          H.setPad(aPh < 4 and { "up" } or (aPh == 4 and { "a" } or {}))
          return
        end
        H.setPad({})
      end),
    }, "Banon -> Prepared? -> party menu")
  end)(),
  H.call(function()
    H.log(string.format("party menu up at f%d ($0059=%02X)", H.frame,
      H.readByte(0x0059)))
  end),

  -- ==================================================================== --
  -- MENU CHARACTERIZATION.  Settle into state $2d, dump, then a scripted
  -- press trace.  Each press logs the full cursor cluster + both tables.
  -- ==================================================================== --
  H.waitUntil(function() return mst() == 0x2d end, 900, "menu state $2d", 5),
  H.waitFrames(30),
  H.call(function() mdump("open") end),
  mpress("right", "r1"), mpress("right", "r2"), mpress("right", "r3"),
  mpress("left", "l1"), mpress("left", "l2"), mpress("left", "l3"),
  mpress("down", "d1"), mpress("down", "d2"),
  mpress("right", "dr1"),
  mpress("up", "u1"),
  -- pick pool char 0 (state should flip $2d -> $2e)
  mpress("a", "a1"),
  H.call(function()
    H.assertEq(mst(), 0x2e, "A in $2d selects a source: state $2e")
  end),
  -- move to the party area and drop (swap): observe what down+A does
  mpress("down", "e_d1"),
  mpress("a", "a2"),
  H.waitFrames(20),
  H.call(function()
    mdump("after-drop")
    rosterLine("mid-menu")
  end),
  -- second pick/drop attempt: next pool char into a different column
  mpress("right", "p2r"), mpress("a", "a3"),
  mpress("down", "e2_d"), mpress("right", "e2_r"), mpress("a", "a4"),
  H.waitFrames(20),
  H.call(function() mdump("after-drop-2") end),
  -- and a START while parties are (likely) still short: the error path
  -- proves the commit rule without committing
  mpress("start", "start-early"),
  H.waitFrames(40),
  H.call(function()
    mdump("post-start")
    H.log("probe complete -- the driver gets written from this trace")
    H.screenshot("spike_menu")
  end),
})
