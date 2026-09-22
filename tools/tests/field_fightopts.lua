-- @suite
-- field_fightopts.lua -- #209: a walker's `fight = { ... }` table reaches
-- the fight driver it builds.
--
-- Boots nothing (power-on, the game untouched, like step_reset.lua): what
-- is under test is the option internals, so M.newFightDriver is replaced for
-- the length of the check by a recorder that returns a stub driver and
-- keeps the options table each walker hands it.  Every walker in
-- lib/ot6_field.lua that builds a driver at construction is built once
-- with a `fight` table, and the recorded options must show:
--
--   1. the walker's named options and defaults as before (healPercent 55
--      for navTo, 45 for newWalkFighter, rideOut's bank 3 / cadence 12);
--   2. every `fight` key present, and a `fight` key overriding the named
--      option of the same name;
--   3. a function entry is live: nil before the first frame, the
--      function's value on every F.frame(), called with the driver's tag
--      and a memo table that F.idle() empties.
local H = dofile("tools/tests/lib/ot6.lua")

local seen = {}
local function recorder(tag, opts)
  local F = { tag = tag, opts = opts, frames = 0, idles = 0, focusAt = {} }
  function F.frame()
    F.frames = F.frames + 1
    F.focusAt[F.frames] = opts.focus
  end
  function F.idle() F.idles = F.idles + 1 end
  seen[#seen + 1] = F
  return F
end

local function build(what, ctor)
  local n = #seen
  local lib = H.newFightDriver
  H.newFightDriver = recorder
  local ok, err = pcall(ctor)
  H.newFightDriver = lib
  H.assertEq(ok, true, what .. " constructs: " .. tostring(err))
  H.assertEq(#seen, n + 1, what .. " built exactly one fight driver")
  return seen[#seen]
end

local FOCUS = { { slot = 2, mask = 0x04 } }

H.run({ maxFrames = 600, watchdog = false }, {
  H.waitFrames(10),
  H.call(function()
    local fight = { keyed = false, tools = false, traceTgt = true,
                    focus = FOCUS, healPercent = 80 }
    local cases = {
      { "navTo", function()
          return H.navTo(1, 1, { playBattles = "tactical", bank = 2, fight = fight })
        end, { healPercent = 80, bank = 2 } },
      { "advanceStory", function()
          return H.advanceStory(function() return true end, 10,
            { playBattles = "tactical", healer = 6, fight = fight })
        end, { healPercent = 80, healer = 6 } },
      { "worldNavTo", function()
          return H.worldNavTo(1, 1, { playBattles = "tactical", reserve = { [0xE9] = 3 },
            fight = fight })
        end, { healPercent = 80 } },
      { "phaseWalk", function()
          return H.phaseWalk(1, 1, { switches = { a = 0x01F5, b = 0x01F6 },
            period = 158, region = { w = 17, h = 16 }, hurt = {}, fight = fight })
        end, { healPercent = 80 } },
      { "newWalkFighter", function()
          return H.newWalkFighter("wf", { tool = 0xA3, fight = fight })
        end, { healPercent = 80, tool = 0xA3 } },
      { "rideOut", function()
          return H.rideOut("ride", 10, 1, { fight = fight })
        end, { healPercent = 80, bank = 3, cadence = 12 } },
      { "crossDoor", function()
          return H.crossDoor(1, 1, 2, 3, 4, "door", { fight = fight })
        end, { healPercent = 80, bank = 3 } },
      { "shopTalk", function()
          return H.shopTalk(1, 1, "shop", { fight = fight })
        end, { healPercent = 80, bank = 3 } },
    }
    for _, c in ipairs(cases) do
      local F = build(c[1], c[2])
      local o = F.opts
      H.assertEq(o.tactical, true, c[1] .. ": tactical kept")
      H.assertEq(o.keyed, false, c[1] .. ": fight.keyed reached the driver")
      H.assertEq(o.tools, false, c[1] .. ": fight.tools reached the driver")
      H.assertEq(o.traceTgt, true, c[1] .. ": fight.traceTgt reached the driver")
      H.assertEq(o.focus, FOCUS, c[1] .. ": fight.focus reached the driver")
      for k, v in pairs(c[3]) do
        H.assertEq(o[k], v, string.format("%s: %s", c[1], k))
      end
      H.log(string.format("field_fightopts: %s merged fight options", c[1]))
    end

    -- the defaults without a fight table are the named options' own
    local F = build("navTo (no fight)", function()
      return H.navTo(1, 1, { playBattles = "tactical" })
    end)
    H.assertEq(F.opts.healPercent, 55, "navTo: healPercent default 55 without fight")
    H.assertEq(F.opts.keyed, nil, "navTo: no keyed without fight")
    F = build("newWalkFighter (no fight)", function()
      return H.newWalkFighter("wf")
    end)
    H.assertEq(F.opts.healPercent, 45, "newWalkFighter: healPercent default 45")
    -- fieldCare's own switch spelling: fight = false adds nothing
    F = build("newWalkFighter (fight = false)", function()
      return H.newWalkFighter("wf", { fight = false })
    end)
    H.assertEq(F.opts.fight, nil, "a non-table fight is not a driver option")

    -- 3. a live (function-valued) entry, through worldNavTo
    local calls, memos = {}, {}
    local n = 0
    local function live(tag, memo)
      n = n + 1
      calls[n] = tag
      memos[n] = memo.said      -- by index: a nil must not shift the rest
      memo.said = n
      return n % 2 == 1 and FOCUS or nil
    end
    local W = build("worldNavTo (live focus)", function()
      return H.worldNavTo(1, 1, { playBattles = "tactical", fight = { focus = live } })
    end)
    H.assertEq(W.opts.focus, nil, "a live entry reads nil before the first frame")
    H.assertEq(n, 0, "a live entry is not called at construction")
    -- the walker keeps its wrapped driver private, so the frame/idle half
    -- is driven on one built the way every walker builds it
    local D = (function()
      local lib = H.newFightDriver
      H.newFightDriver = recorder
      local d = H.fightDriverFor("direct", { tactical = true, healPercent = 60 },
                                 { focus = live, keyed = false })
      H.newFightDriver = lib
      return d
    end)()
    local inner = seen[#seen]
    H.assertEq(inner.opts.healPercent, 60, "fightDriverFor: base kept")
    H.assertEq(inner.opts.keyed, false, "fightDriverFor: static entry merged")
    D.frame(); D.frame(); D.idle(); D.frame()
    H.assertEq(inner.frames, 3, "the wrapped frame reached the driver")
    H.assertEq(inner.idles, 1, "the wrapped idle reached the driver")
    H.assertEq(inner.focusAt[1], FOCUS, "frame 1 saw the live value")
    H.assertEq(inner.focusAt[2], nil, "frame 2 saw the live nil (cleared)")
    H.assertEq(inner.focusAt[3], FOCUS, "frame 3 saw the live value again")
    H.assertEq(calls[1], "direct", "the live entry gets the driver's tag")
    H.assertEq(memos[1], nil, "memo starts empty")
    H.assertEq(memos[2], 1, "memo carries across frames")
    H.assertEq(memos[3], nil, "idle empties the memo")
    H.log("field_fightopts: live entries checked")
  end),
  H.logStep(function() return "field_fightopts complete" end),
})
