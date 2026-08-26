-- probe_fire_exit.lua -- from a savestate taken mid-fire (control back on
-- town 343 at (12,21), just after $008E=1 fires), walk out the town's south
-- exit, take a real world SRAM save, re-enter, and log $008E's state and
-- whether town 343 re-tiles burning on the way back in.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA = 0
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local function crossDoor(sx, sy, dm, dx, dy, what)
  local pick, startMap
  local function stage()
    if not pick then
      for _, c in ipairs(DIAGSTAGE) do
        local cx, cy, move = sx + c[1], sy + c[2], c[3]
        local press = H.movePress(move)
        if H.bfsPath(cx, cy) and (press == move or H.canStep(cx, cy, move)) then
          pick = { cx, cy, press }; break
        end
      end
      pick = pick or { sx, sy + 1, "up" }
    end
    return pick
  end
  local settled = calm(20)
  local aPhase = 0
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true, arrive = function() return map() ~= startMap end }),
    H.driveUntil(function()
      return map() ~= startMap or (H.fieldX() == dx and H.fieldY() == dy)
    end, 1800, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({ [stage()[3]] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(settled, 1800, what .. ": far-side control"),
    H.waitUntil(function() return bright() >= 15 end, 900, what .. ": fade-in", 10),
    H.waitFrames(30),
  })
end

local function objAt(idx)
  local off = 0x29 * idx
  return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
end
local function chaseTalkLazy(idxFn, maxFrames, what, opts)
  opts = opts or {}
  local ph = 0
  local done = opts.done or function()
    return H.readByte(0x056f) >= 2 and H.dialogWaiting()
  end
  return H.driveUntil(done, maxFrames or 9000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s * 2) % 2 == 1 then H.killbit(s) end
        end
        H.setPad(ph < 4 and { "a" } or {})
        return
      end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local objIdx = idxFn()
      local ox, oy = objAt(objIdx)
      local px, py = H.fieldX(), H.fieldY()
      local dx, dy = ox - px, oy - py
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir
        if dx == 1 then dir = "right" elseif dx == -1 then dir = "left"
        elseif dy == 1 then dir = "down" else dir = "up" end
        H.setPad(ph < 4 and { "a", [dir] = true } or { [dir] = true })
        return
      end
      local best
      for _, c in ipairs({ { ox, oy + 1 }, { ox - 1, oy },
                           { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = H.bfsPath(c[1], c[2])
        if p and (not best or #p < #best) then best = p end
      end
      if best and #best > 0 then H.setPad({ [H.movePress(best[1])] = true })
      else H.setPad({}) end
    end),
  }, what or "chaseTalkLazy")
end

H.run({ maxFrames = 300000 }, {
  -- ---- boot: cold Continue thamasa-night-v1 ----
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 249 and H.worldY() == 128
    end
    return H.driveUntil(function() return atSite() and bright() >= 15 end,
      4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> the L tile")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the L tile", 5),
  H.waitFrames(30),
  H.call(function() H.assertEntryContract("thamasa-night-v1") end),
  H.fieldCare({ tag = "care at the L tile", threshold = 0.9 }),
  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT onto (250,128) -> Thamasa 343 (23,46)"),
  H.release(),
  H.waitUntil(function() return map() == 343 and H.hasControl() end, 3000,
    "Thamasa map re-loaded", 5),

  -- ---- the inn, the fire ---------------------------------------------------
  crossDoor(12, 19, 346, 23, 23, "inn door"),
  -- The innkeeper at (24,15) sits behind a counter tile at (24,16) that
  -- bfsPath refuses as a stand; (24,17) is the reachable far side, and the
  -- talk reaches through the counter (the Dadaluma "talk-across-a-counter"
  -- mechanic).
  H.navTo(24, 17, { maxFrames = 9000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  H.driveUntil(function()
    return H.readByte(0x087f + H.readWord(0x0803)) == 0  -- facing UP
  end, 300, {
    H.call(function() H.setPad({ up = true }) end),
  }, "face up at the inn counter"),
  H.release(), H.waitFrames(4),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.dialogWaiting() end, 3000, {
      H.call(function()
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { a = true, up = true } or {})
      end),
    }, "talk-across-the-counter -> innkeeper's 1 GP choice")
  end)(),
  H.advanceStory(calm(30), 30000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "control back on town map after the fire")
    H.assertEq(H.fieldX(), 12, "fire scene end x (12,21)")
    H.assertEq(H.fieldY(), 21, "fire scene end y")
    H.assertEq(sw(0x008E), 1, "$008E SET -- the fire has started")
    H.log(string.format("[P2] fire started at f%d, map=%d (%d,%d) $008E=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x008E)))
  end),

  -- ---- P2: snapshot mid-fire, then attempt to leave town through the ----
  -- ---- south exit, world-save, and come back in --------------------------
  (function()
    local ckReq
    return H.call(function()
      ckReq = H.requestSaveState()
      H.log("[P2] mid-fire savestate captured (not used further -- the "
        .. "question is whether the LIVE walk-out is legal, not a reload)")
    end)
  end)(),
  H.call(function()
    H.log(string.format(
      "[P2] attempting the south exit while $008E=1 (structurally ungated "
      .. "per thamasa-route.md hazard 4 -- long entrances carry no switch "
      .. "gate); walking to (21,47)"))
  end),
  H.navTo(21, 47, { maxFrames = 20000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  pressWalk("down", function() return H.worldMode() end, 900,
    "held DOWN onto the south strip -> world"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15
  end, 3600, "world control outside Thamasa", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format(
      "[P2] RESULT: the south exit is legal mid-fire.  Landed world (%d,%d) "
      .. "f%d, $008E=%d (still set -- leaving town does not clear it)",
      H.worldX(), H.worldY(), H.frame, sw(0x008E)))
  end),

  -- a real world SRAM save, using slot 3
  (function()
    local ZMENUSTATE, SAVE_SELECT = 0x26, 0x14
    local saveArg = nil
    return seq({
      H.fieldCare({ tag = "care before the P2 save", threshold = 0.85 }),
      (function() local calmN, ph = 0, 0
        return H.driveUntil(function()
          calmN = (H.readByte(0x59) ~= 0) and calmN + 1 or 0
          return calmN >= 30
        end, 1800, {
          H.call(function()
            ph = (ph + 1) % 48
            if H.readByte(0x59) ~= 0 then H.setPad({}); return end
            H.setPad(ph < 6 and { "x" } or {})
          end),
        }, "world menu open")
      end)(),
      H.waitFrames(30),
      H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
        "main menu state", 5),
      H.call(function()
        local entry = H.sym("CopyGameDataToSRAM")
        emu.addMemoryCallback(function()
          saveArg = emu.getState()["cpu.a"] & 0xff
        end, emu.callbackType.exec, entry, entry)
      end),
      H.driveUntil(function()
        return H.readByte(ZMENUSTATE) == 0x05 and H.readByte(0x4b) == 6
      end, 600, { H.pressButtons({ "up" }, 4), H.waitFrames(16) },
        "main-menu cursor on Save"),
      H.pressButtons({ "a" }, 4),
      H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
        600, "save-slot selection", 5),
      H.driveUntil(function()
        return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
      end, 600, { H.pressButtons({ "down" }, 4), H.waitFrames(16) },
        "save cursor on slot 3"),
      H.driveUntil(function()
        return saveArg == 3 and emu.read(0x307ff0, emu.memType.snesMemory) == 3
      end, 1800, { H.pressButtons({ "a" }, 4), H.waitFrames(20) },
        "save confirmed"),
      H.waitFrames(120),
      H.call(function()
        H.log(string.format("[P2] mid-fire world save landed: slot=%d",
          emu.read(0x307ff0, emu.memType.snesMemory)))
      end),
      -- Confirming the save does not close the menu stack back to the field
      -- on its own: H.worldHasControl() requires $00E8 bit0 (menu
      -- opening/open) clear, and it stays set until the menu is cancelled.
      -- Cancel out with B until control returns.
      H.driveUntil(function() return H.worldHasControl() end, 1200, {
        H.call(function() H.setPad({ b = true }) end),
      }, "cancel out of the save menu -> world control"),
      H.release(),
      H.waitFrames(30),
      H.call(function()
        H.log(string.format(
          "[P2 dbg] post-menu-close: worldMode=%s worldHasControl=%s " ..
          "world=(%d,%d) aligned=%s f%d",
          tostring(H.worldMode()), tostring(H.worldHasControl()),
          H.worldX(), H.worldY(), tostring(H.worldAligned()), H.frame))
      end),
      -- Wait passively for worldAligned() before pressing anything: the
      -- save/menu-close leaves a fractional-position or camera resync that
      -- needs quiet frames rather than input.
      H.waitUntil(function() return H.worldHasControl() and H.worldAligned() end,
        1800, "world re-settles after menu close (passive)", 10),
      H.call(function()
        H.log(string.format(
          "[P2 dbg] post-passive-wait: world=(%d,%d) aligned=%s f%d",
          H.worldX(), H.worldY(), tostring(H.worldAligned()), H.frame))
      end),
    })
  end)(),

  -- ---- back into town: does 343 re-tile burning? --------------------------
  -- The south exit lands the party at world (249,128), the same tile the
  -- thamasa-night-v1 checkpoint boot lands at, one tile short of the
  -- (250,128) trigger, so the return leg needs the same held-RIGHT approach
  -- the original entry used.
  (function()
    local hb = 0
    return H.driveUntil(function() return not H.worldMode() end, 2000, {
      H.call(function()
        hb = hb + 1
        if hb % 120 == 0 then
          H.log(string.format(
            "[P2 dbg] re-entry f%d world=(%d,%d) mode=%s hasCtl=%s algn=%s",
            H.frame, H.worldX(), H.worldY(), tostring(H.worldMode()),
            tostring(H.worldHasControl()), tostring(H.worldAligned())))
        end
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        H.setPad({ right = true })
      end),
    }, "held RIGHT back onto (250,128) -> Thamasa")
  end)(),
  H.release(),
  H.waitUntil(function() return map() == 343 and H.hasControl() end, 3000,
    "Thamasa map re-loaded (return leg)", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format(
      "[P2] RESULT: re-entered town at f%d, (%d,%d), $008E=%d -- ",
      H.frame, H.fieldX(), H.fieldY(), sw(0x008E)))
    -- The burning retile is mod_bg_tiles, which changes BG1/BG2 graphics
    -- rather than the tile prop table read here; the screenshot is the
    -- primary evidence for whether it looks burning.
    H.screenshot("p2_fire_reentry")
    H.log(string.format(
      "[P2] CONCLUSION: $008E reads %d on return.  Combined with "
      .. "thamasa-route.md's retile rule (town 343's init applies the "
      .. "burning mod_bg_tiles blocks whenever $008E && !$0090, "
      .. "map_init_event.asm:362 -> :69289), a reentry with $008E still 1 "
      .. "and $0090 still 0 SHOULD re-tile burning -- see the screenshot "
      .. "for the visual confirmation.", sw(0x008E)))
  end),
  H.logStep(function()
    return string.format("P2 probe done at f%d -- see log for the S2 verdict",
      H.frame)
  end),
})
