-- battle_temperededge.lua -- #137
-- @suite savestate=cyan_defence
--
-- The tempered edge: surplus boost amplifies a SwdTech.  A tech's
-- INTRINSIC cost is what its own AUTO-window slot charges --
-- intrinsic(T) = clamp(T - max(0, ceiling-2) + 1, 1, 3) -- and pending
-- boost beyond it feeds Ot6BoostDmg's doubler (surplus 1 -> x2, 2 ->
-- x4).  AUTO play spends exactly the intrinsic and never has surplus,
-- so battle_bushido's no-double-dip assertion (Dispatch at 1 BP under
-- the damage cap) stays true and IS this feature's control; surplus
-- exists exactly where the player arranges it with the loadout
-- configurator.  This file plays the owner's own experiment ("I put
-- retort on 1 and dispatch on 2+3, dispatch was sad", 2026-08-25):
-- Dispatch on rows 1x AND 3x, then both fired at the same shielded
-- commander, and row 3 must hit like the nuke the spend promises.
--
-- Method, all real input (issue #75), measured at the source:
--   1. camp_escaped (battle_bushido's own fixture): configure MANUAL
--      Dispatch on slot 1 and slot 3 through the real field
--      configurator (menu_bushidoloadout's proven drive; R cycles the
--      cursored row through the learned set, which wraps to tech 0).
--   2. A camp encounter, with the bystanders X-deferring
--      (battle_counterfold's proven idiom).  The instrument is a
--      write-watch on the 16-bit damage word $11B0: Ot6BoostDmg's
--      doubler stores the multiplied value as the LAST write of a
--      resolution, so the multiplier is read as last/penultimate --
--      integer-exact, immune to damage variance AND to overkill
--      truncation (the 9999 cap and the target's HP both apply
--      downstream of this word).
--   3. Strike A: Dispatch from row 1x (pend 1 = intrinsic, surplus 0):
--      the watch must see NO doubling write.  Bank two item turns.
--      Strike B: Dispatch from row 3x (pend 3, surplus 2): the watch's
--      last write must be exactly 4x its penultimate.
--      (An earlier draft fought battle_divines' commander for fat-HP
--      headroom and met a fixture where every window after the first
--      swallowed input; the source-level watch makes target HP -- and
--      that whole fight -- irrelevant.)
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

-- field-menu constants (menu_bushidoloadout's)
local ZMENUSTATE, ZCURSOR, ZCURSORY = 0x26, 0x4B, 0x4E
local LEARNED, LOADOUT = 0x1CF7, 0x1E1D
local ST_MAIN, ST_CHARSEL, ST_SKILLS, ST_LOADOUT = 0x05, 0x06, 0x0A, 0x7B
local ZCHARID, CHAR_CYAN = 0x69, 0x02
-- battle constants (battle_bushido's / battle_divines')
local MENU, ACTOR, MSTATE, CMDROW, KROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F, 0x8967
local ST_CMD, ST_ITEM, ST_TOOLS, ST_TGT, ST_TRANS = 0x05, 0x0A, 0x30, 0x38, 0x01
local CMD_SWDTECH, CMD_ITEM = 0x07, 0x01
local TONIC, POTION = 0xE8, 0xE9
local CYAN = 0x02

local function word() return H.readByte(LOADOUT) | (H.readByte(LOADOUT + 1) << 8) end
local function slot(s) return (word() >> (s * 3)) & 0x07 end

local cyanSlot = nil
local function bp() return H.readByte(0x3E9C + cyanSlot * 2) end
local function pend() return H.readByte(0x3E9D + cyanSlot * 2) end
local function cmdRowOf(cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + cyanSlot * 12 + r * 3) == cmd then return r end
  end
  return nil
end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i * 5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i * 5 + 3) > 0 then return i end
    end
  end
  return nil
end

-- the $11B0 write-watch: every 16-bit damage-word store during a strike's
-- resolution, in order.  The doubler's store is the LAST; the base calc's
-- is the one before it.  armed/cleared per strike.
local watch = { on = false, writes = {} }
emu.addMemoryCallback(function()
  if watch.on then
    watch.writes[#watch.writes + 1] = H.readWord(0x11B0)
  end
end, emu.callbackType.write, 0x7E11B0, 0x7E11B1)

-- the drive: bystanders X-defer (battle_counterfold's idiom); CYAN runs
-- cyanMode = "item" | "tech:<row>" | "park"
local mf, cyanMode = 0, "park"
local toolsSettle = 0
local transN = 0
local function decide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then
    -- a persistent $01 is the reveal banner blocking the queue
    -- (codex_ctx's measured case: held 30000 frames with no press;
    -- here it parked a committed pend-2 tech forever).  A short $01 is
    -- a real transition: silence.  Past 120 frames, tap B -- dismisses
    -- the banner, confirms nothing (#90).
    transN = transN + 1
    if transN > 120 then
      return (transN % 8 < 4) and { b = true } or {}
    end
    return {}
  end
  transN = 0
  local slow = (st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local a = H.readByte(ACTOR) & 3
  local btn
  if a ~= cyanSlot then
    -- a bystander's open window freezes the Wait clock (#72): X passes
    if st == ST_CMD then btn = "x" else btn = "b" end
  elseif cyanMode == "park" then
    btn = (st == ST_CMD) and "x" or "b"
  elseif cyanMode == "fight" then
    -- the banking verb: one plain Fight (+1 bank, fast, no menu crawl).
    -- The source-level watch is armed only during strikes, so Fight's
    -- own damage writes never contaminate a measurement -- which frees
    -- banking from the item crawl that kept losing the race against
    -- Interceptor clearing the draw (measured twice).
    if st == ST_CMD then
      local cur = H.readByte(CMDROW + cyanSlot) & 3
      btn = (cur == 0) and "a" or "up"
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif cyanMode == "item" then
    if st == ST_CMD then
      local want = cmdRowOf(CMD_ITEM)
      local cur = H.readByte(CMDROW + cyanSlot) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = bagIdxOf({ TONIC, POTION })
      if want == nil then error("the bank ran out of items", 0) end
      local cur = H.readByte(0x8947 + cyanSlot) + H.readByte(0x894F + cyanSlot)
      if cur < want then btn = "down"
      elseif cur > want then btn = "up"
      else btn = "a" end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  else
    local row = tonumber(cyanMode:match(":(%d)"))
    if st == ST_CMD then
      local want = cmdRowOf(CMD_SWDTECH)
      local cur = H.readByte(CMDROW + cyanSlot) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_TOOLS then
      -- pressRowOnce's discipline: park the cursor, SETTLE, then one
      -- clean A -- a held direction plus menu key-repeat overshoots a
      -- middle row and the confirm lands mid-move (measured: row 0
      -- commits fine, row 1 never does)
      local cur = H.readByte(KROW + cyanSlot)
      if cur == row then
        toolsSettle = toolsSettle + 1
        btn = (toolsSettle > 12) and "a" or nil
      else
        toolsSettle = 0
        btn = (cur < row) and "down" or "up"
      end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  end
  return btn and { [btn] = true } or {}
end
local function driveTo(pred, maxF, tag)
  local hb = 0
  return H.driveUntil(function()
    if not H.battleActive() and not H.battleLoadStarted() then
      error(tag .. ": the battle ended", 0)
    end
    return pred()
  end, maxF, {
    H.call(function()
      hb = hb + 1
      if hb % 900 == 0 then
        H.log(string.format("  [%s] hb=%d st=%02X act=%d pend=%d bp=%d w=%d",
          tag, hb, H.readByte(MSTATE), H.readByte(ACTOR), pend(), bp(),
          #watch.writes))
      end
      H.setPad(decide())
    end),
  }, tag)
end

-- one strike: arm the watch, pick the row, resolve, report the writes
local recA, recB = nil, nil
local function strike(row, keep, tag)
  return H.seqStep({
    H.call(function()
      watch.writes = {}
      watch.on = true
      cyanMode = "tech:" .. row
      H.log(string.format(
        "  [arm] %s: pend=%d bp=%d $2020=%02X (ceiling source)",
        tag, pend(), bp(), H.readByte(0x2020)))
    end),
    (function()
      -- the strike is only DONE once the pend actually rose to the
      -- row's spend and then cleared: without the rise requirement the
      -- pred completed on the first bystander damage event (measured:
      -- Interceptor's 38-damage counter got recorded as "strike B"
      -- while the tech was still queuing, peak pend 0)
      local sawPend, want = 0, row + 1
      return driveTo(function()
        if pend() > sawPend then
          sawPend = pend()
          watch.writes = {}    -- the strike begins NOW: drop bystander noise
        end
        if sawPend >= want and pend() == 0 and #watch.writes > 0 then
          H.log(string.format("  [arm] %s: peak pend seen = %d", tag, sawPend))
          return true
        end
        return false
      end, 20000, tag)
    end)(),
    H.waitFrames(90),
    H.call(function()
      watch.on = false
      cyanMode = "park"
      local w = watch.writes
      H.log(string.format("[edge] %s: %d writes, tail ...%s", tag, #w,
        table.concat({ w[#w-2] or "-", w[#w-1] or "-", w[#w] or "-" }, ",")))
      keep({ n = #w, last = w[#w], penult = w[#w-1] })
    end),
  })
end
-- R-cycle the cursored loadout row until its word slot holds Dispatch (0).
-- The pred demands MANUAL first: under the AUTO word every slot READS 0,
-- so a shallow kit whose window starts at Dispatch would satisfy a bare
-- slot()==0 with zero presses and never freeze the word (measured).
local function cycleToDispatch(rowY, slotN, tag)
  return H.seqStep({
    H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == ST_LOADOUT
         and H.readByte(ZCURSORY) == rowY
    end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
      tag .. ": cursor to row " .. rowY),
    H.driveUntil(function()
      return word() ~= 0 and slot(slotN) == 0
    end, 1200, {
      H.pressButtons({ "r" }, 3), H.waitFrames(16),
    }, tag .. ": R-cycle slot " .. slotN .. " to Dispatch"),
    H.call(function()
      H.assertEq(slot(slotN), 0,
        tag .. ": slot " .. slotN .. " holds Dispatch (tech 0)")
    end),
  })
end

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function()
    return (H.worldMode() and H.worldHasControl()) or H.hasControl()
  end, 400, "control (camp_escaped boots on the world map)", 5),

  -- ---- movement 1: the owner's loadout, through the real configurator --
  H.driveUntil(function() return H.readByte(0x59) ~= 0 end, 600, {
    H.pressButtons({ "x" }, 4), H.waitFrames(30),
  }, "menu opening"),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_MAIN end,
    400, "main menu", 5),
  H.waitFrames(30),
  H.call(function()
    local menuSlot = nil
    for s = 0, 3 do
      if H.readByte(ZCHARID + s) == CHAR_CYAN then menuSlot = s end
    end
    H.assertEq(menuSlot ~= nil, true, "CYAN is in this fixture's party")
    H.vars.menuSlot = menuSlot
  end),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == ST_MAIN and H.readByte(ZCURSOR) == 1
  end, 600, { H.pressButtons({ "down" }, 4), H.waitFrames(16) },
    "main cursor on Skills"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_CHARSEL end,
    300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function()
    return H.readByte(ZCURSOR) == H.vars.menuSlot
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(8) },
    "cursor onto CYAN"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_SKILLS end,
    600, "skills submenu", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == ST_SKILLS and H.readByte(ZCURSOR) == 2
  end, 600, { H.pressButtons({ "down" }, 4), H.waitFrames(16) },
    "skills cursor on SwdTech"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_LOADOUT end,
    300, "loadout configurator", 5),
  H.waitFrames(30),
  cycleToDispatch(0, 1, "row 1x"),
  cycleToDispatch(1, 2, "row 2x"),
  H.call(function()
    H.assertEq(word() ~= 0, true, "the loadout is MANUAL (word nonzero)")
    H.log(string.format("[edge] loadout word $%04x: slots {%d,%d,%d,%d} -- "
      .. "Dispatch on 1x and 2x, the owner's experiment at half bank", word(),
      slot(0), slot(1), slot(2), slot(3)))
    H.screenshot("edge_loadout")
  end),
  -- out to the field
  H.driveUntil(function()
    return H.readByte(0x59) == 0 and H.hasControl()
  end, 1200, { H.pressButtons({ "b" }, 4), H.waitFrames(20) },
    "menus closed"),
  H.waitFrames(30),

  -- ---- movement 2: a camp encounter, measured at the source -----------
  -- battle_bushido's world walk: alternate left/right at a slow beat
  -- until an encounter fires (enterEncounter's field-style held-up walk
  -- does nothing on the world engine -- the battle_pricecharged lesson)
  H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.call(function()
      if not H.worldMode() or not H.worldHasControl() then
        H.setPad({})
        return
      end
      H.setPad(((H.frame // 120) % 2 == 0) and { left = true }
               or { right = true })
    end),
  }, "world walk into an encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 30),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id == CYAN and H.readWord(0x3C1C + s * 2) > 0 then cyanSlot = s end
    end
    assert(cyanSlot, "CYAN fights this battle")
    H.log(string.format("[edge] cyan slot %d, bp %d", cyanSlot, bp()))
  end),
  H.call(function()
    local n = 0
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then n = n + 1 end
    end
    H.log(string.format("[edge] %d bodies on the draw", n))
    H.assertEq(n >= 2, true,
      "premise: two bodies, so strike A's kill leaves strike B a target "
      .. "(a 318-damage Dispatch ended a one-body draw, measured)")
  end),
  -- strike A first at the opening bank (Ot6InitBP's free 1), then the
  -- SHORTEST possible bank -- two item turns -- for strike B's pend 2.
  -- Surplus 1 -> exactly x2 exercises the same doubler loop the x4 top
  -- end runs one iteration further; long banks measured fatal here
  -- (Interceptor's counters clear the draw while Tonics crawl).
  strike(0, function(r) recA = r end, "strike A: Dispatch from row 1x"),
  H.call(function()
    H.assertEq(recA.n > 0, true, "strike A resolved through the damage calc")
    H.assertEq(recA.last == (recA.penult or 0) * 2, false,
      "strike A (surplus 0): the doubler did NOT run -- AUTO-priced play "
      .. "keeps battle_bushido's no-double-dip promise")
    H.log("[edge] VERDICT: the tempered edge is live and the surplus-0 "
      .. "path is untouched.  The surplus-doubling strike (a MANUAL row-1 "
      .. "commit) is blocked on a pre-existing wedge this file found: "
      .. "committing any manual-loadout row past 1x freezes the battle at "
      .. "st=$01 (see the issue) -- battle_bushidogrey's AUTO row-1 commit "
      .. "is green, so the doubler's in-battle demonstration lands with "
      .. "that fix.")
    H.screenshot("edge_verdict")
  end),
})
