-- @suite savestate=vargas_entry
-- watchdog_listend.lua -- the list-cursor exemption's negative control
-- (#200): DOWN pressed past the end of a battle list MUST still trip the
-- battle no-effect watchdog.
--
-- The watchdog (lib/ot6.lua, listSig / watchTick) counts a press as
-- answered while the current actor's list-cursor block ($890F..$896E,
-- one byte per actor) moves sample to sample, because a long list scroll
-- changes nothing the older signature read (2779c71b: vector_crash's
-- 43-row walk to the Potion tripped three times).  The rule's narrow half
-- is what this suite holds: once the list has hit its end nothing in the
-- block moves under a DOWN still pressed, and the trip must land 300
-- frames later.  Measured 2026-09-16 with probe_list_scroll.lua on this
-- fixture: the item scroll offset ($8947+actor) moves once per press
-- through every row, then sits.
--
-- A suite cannot expect a red run, so the trip is observed through the
-- segment runner: attempt 1 opens the Vargas fight from vargas_entry,
-- opens the first actor's item list, and presses DOWN (5 on / 5 off,
-- distinct presses, the fight driver's cadence) with the watchdogs
-- enforcing; the trip is a seed-dependent class, so the runner replays
-- the body, and attempt 2 reads H.attemptFailures() and asserts that
-- attempt 1 fell to `no-effect` on DOWN with the list block still for at
-- least the no-effect window.  The verdict of a healthy tree is PASS
-- attempts=2/2.  A widened exemption shows as attempt 1 pressing DOWN for
-- PRESS_MAX frames with no trip, a contract failure (no replay): the suite
-- is red at once, naming the widening.  probe_list_scroll.lua stays the
-- hand-run instrument that traces every cell of every list.
local H = dofile("tools/tests/lib/ot6.lua")

local DOOR = "build/states/vargas_entry.mss.lua"
local MENU, ACTOR, MSTATE, CMDTBL, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x202E, 0x890F
local ST_CMD, ST_ITEM, ST_SCROLL, ST_ITEM2, ST_TGT = 0x05, 0x0A, 0x17, 0x18, 0x38
local CMD_ITEM = 0x01
local ITEM_SCROLL, ITEM_ROW = 0x8947, 0x894F
local END_QUIET = 200      -- the block still this long = the list's end, logged before the
                           -- 300-frame trip lands (probe_list_scroll measured 360 to be sure)
local PRESS_MAX = 4500     -- the item list here walks ~251 rows at 10 frames a press
                           -- (scroll 00 -> FB, measured), then the 300-frame window

local failures = H.attemptFailures()
local attempt = #failures + 1
local aPh, tick = 0, 0
local a0, pressed, lastMove, endFrame, logged = nil, 0, 0, nil, 0
local s0 = { -1, -1 }

local function st() return H.readByte(MSTATE) end
local function actor() return H.readByte(ACTOR) & 3 end
local function inList(s) return s == ST_ITEM or s == ST_SCROLL or s == ST_ITEM2 end
local function cmdRowOf(a, cmd)
  for row = 0, 3 do
    if H.readByte(CMDTBL + a * 12 + row * 3) == cmd then return row end
  end
  return nil
end
local function press(b)
  tick = tick + 1
  H.setPad(tick % 10 < 5 and { [b] = true } or {})
end
local function cells(a)
  return { H.readByte(ITEM_SCROLL + a), H.readByte(ITEM_ROW + a) }
end

local steps
if attempt == 1 then
  steps = {
    H.waitFrames(20),
    H.loadState(DOOR),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.mapId() & 0x1ff, 98, "booted on map 98, VARGAS's ledge")
    end),
    -- one interaction -> the scene -> battle 66 (battle_vargas.lua's opening)
    H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "the VARGAS scene reaches battle 66"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
    H.waitFrames(120),

    -- the first command window: cursor to Item, open the list
    H.driveUntil(function() return a0 ~= nil end, 3000, {
      H.call(function()
        if H.readByte(MENU) == 0 then
          aPh = (aPh + 1) % 8
          H.setPad(aPh < 2 and { "a" } or {})
          return
        end
        local s, a = st(), actor()
        if s == ST_ITEM then
          a0 = a
          s0 = cells(a0)
          lastMove = H.frame
          H.setPad({})
          H.log(string.format("[listend] item list open at f%d: actor %d, "
            .. "scroll=%02X row=%02X", H.frame, a0, s0[1], s0[2]))
          H.screenshot("listend_open")
          return
        end
        if s == ST_TGT then press("b"); return end
        if s ~= ST_CMD then H.setPad({}); return end
        local row = cmdRowOf(a, CMD_ITEM)
        if not row then H.setPad({}); return end
        local c = H.readByte(CMDROW + a) & 3
        if c ~= row then press(c < row and "down" or "up"); return end
        press("a")
      end),
    }, "the item list is open"),

    -- DOWN, press after press, to the end of the list and past it: the
    -- watchdog is expected to end this attempt inside PRESS_MAX frames
    H.driveUntil(function()
      return pressed >= PRESS_MAX or not H.battleLoadStarted() or not inList(st())
    end, PRESS_MAX + 300, {
      H.call(function()
        pressed = pressed + 1
        press("down")
        if H.frame % 8 ~= 0 then return end
        local s1 = cells(a0)
        if s1[1] ~= s0[1] or s1[2] ~= s0[2] then
          lastMove = H.frame
          logged = logged + 1
          if logged <= 12 or H.frame % 64 == 0 then
            H.log(string.format("[listend] f%d st=%02X scroll %02X->%02X row %02X->%02X",
              H.frame, st(), s0[1], s1[1], s0[2], s1[2]))
          end
          s0 = s1
        elseif not endFrame and H.frame - lastMove >= END_QUIET then
          endFrame = lastMove
          H.log(string.format("[listend] end of the item list reached at f%d "
            .. "(scroll=%02X row=%02X, block still %d frames); DOWN stays pressed",
            endFrame, s0[1], s0[2], END_QUIET))
          H.screenshot("listend_end")
        end
      end),
    }, "DOWN past the end of the item list"),
    H.call(function()
      H.setPad({})
      H.assertEq(H.battleLoadStarted(), true, "the fight is still up under the DOWN presses")
      H.assertEq(inList(st()), true,
        string.format("the DOWN presses never left the item list (menu state %02X)", st()))
      H.assertEq(pressed < PRESS_MAX, true,
        string.format("the no-effect watchdog tripped on %d frames of DOWN past the "
          .. "item list's end (end reached at f%s) -- it did not: the list-cursor "
          .. "exemption has widened past a block that stopped moving",
          pressed, endFrame and tostring(endFrame) or "never"))
    end),
  }
else
  steps = {
    H.call(function()
      local f = failures[1]
      H.log(string.format("[listend] attempt %d ended class=%s at f%d: %s",
        f.attempt, f.class, f.frame, f.msg))
      H.assertEq(#failures, 1, "exactly one attempt fell before this one")
      H.assertEq(f.class, "noeffect",
        "attempt 1 fell to the no-effect watchdog (class)")
      H.assertEq(f.msg:find("no-effect: down for", 1, true) ~= nil, true,
        "the trip names DOWN as the unanswered press")
      local still = tonumber(f.msg:match("The list cursor block %(.-%) last moved (%d+) frames ago"))
      H.assertEq(still ~= nil, true, "the trip reports how long the list cursor block sat still")
      H.assertEq((still or 0) >= H.WATCH.noEffectFrames, true,
        string.format("the list block had been still for the whole no-effect window "
          .. "(%d >= %d frames): the trip came after the list's end, not during the scroll",
          still or 0, H.WATCH.noEffectFrames))
      H.log("[listend] the list-cursor exemption still stops where the block "
        .. "stops: DOWN past a list's end trips no-effect")
    end),
  }
end

H.run({ maxFrames = 30000, retries = 2, watchdog = true }, steps)
