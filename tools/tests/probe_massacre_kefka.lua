-- probe_massacre_kefka.lua -- boot ultros-won-v1, climb + ride the massacre
-- chain to solo Leo, stage below the Kefka NPC (24,18) at 341 (24,19), save a
-- reusable savestate, then INSTRUMENT why A does not fire battle 124: scan the
-- object table for the NPC at (24,18), dump its collision/z/activated bits and
-- the $051d gate, and try edge-A activation while watching.  Issue #127.
-- No @suite.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end
local TERRA, WEDGE = 0, 14
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

local function hop(sx, sy, arriveFn, what)
  return seq({
    H.navTo(sx, sy, { maxFrames = 40000, playBattles = "flee", arrive = arriveFn }),
    H.release(),
    H.waitUntil(function()
      return arriveFn() and H.hasControl() and bright() >= 15
         and H.tileAligned() and not H.dialogWaiting()
    end, 6000, what, 10),
    H.waitFrames(45),
  })
end

local function rideScene(pred, maxF, tag)
  local ph = 0
  return H.driveUntil(pred, maxF, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.hasControl() and H.tileAligned() and not H.dialogWaiting()
         and not H.battleLoadStarted() and not H.battleActive() then
        H.setPad({})
      else
        H.setPad(ph < 4 and { "a" } or {})
      end
    end),
  }, tag)
end

-- scan objects $10.. for one standing on (tx,ty); dump its record
local function dumpNpcAt(tx, ty, tag)
  local found = nil
  for i = 16, 47 do
    local off = 0x29 * i
    local ox = H.readWord(0x086a + off) >> 4
    local oy = H.readWord(0x086d + off) >> 4
    if ox == tx and oy == ty then found = i; break end
  end
  if not found then
    H.log(string.format("[kf %s] NO object at (%d,%d); scanning nearby:", tag, tx, ty))
    for i = 16, 47 do
      local off = 0x29 * i
      local ox = H.readWord(0x086a + off) >> 4
      local oy = H.readWord(0x086d + off) >> 4
      if (ox ~= 0 or oy ~= 0) and math.abs(ox - tx) <= 3 and math.abs(oy - ty) <= 4 then
        H.log(string.format("[kf %s]   obj $%02X at (%d,%d) $087c=%02X $0888=%02X",
          tag, i, ox, oy, H.readByte(0x087c + off), H.readByte(0x0888 + off)))
      end
    end
    return
  end
  local off = 0x29 * found
  H.log(string.format("[kf %s] obj $%02X at (%d,%d) coll/act $087c=%02X z $0888=%02X "
    .. "ev=%02X%02X%02X | party(%d,%d) face $087f=%02X $b8=%02X $051d=%d $0521=%d",
    tag, found, tx, ty, H.readByte(0x087c + off), H.readByte(0x0888 + off),
    H.readByte(0x088b + off), H.readByte(0x088a + off), H.readByte(0x0889 + off),
    H.fieldX(), H.fieldY(),
    H.readByte(0x087f + (H.readWord(0x0803))), H.readByte(0x00b8),
    sw(0x051d), sw(0x0521)))
end

H.run({ maxFrames = 6000000, allowGameOver = true }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  (function() local cnt = 0
    return H.waitUntil(function()
      local ok = map() == 375 and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.battleLoadStarted()
      cnt = ok and cnt + 1 or 0
      return cnt >= 10
    end, 4000, "cold Continue to 375", 10)
  end)(),
  H.waitFrames(60),
  -- step off save
  (function() local ph = 0
    return H.driveUntil(function()
      return H.fieldX() <= 7 and H.tileAligned() and not H.dialogWaiting()
    end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ left = true })
      end),
    }, "step LEFT off save")
  end)(),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "settled", 5),
  -- climb
  hop(11, 51, function() return H.fieldX() >= 30 and map() == 375 end, "shortcut"),
  hop(45, 41, function() return map() == 372 end, "->372"),
  hop(40, 19, function() return map() == 375 end, "->pocket"),
  H.navTo(15, 17, { maxFrames = 20000, playBattles = "flee",
    arrive = function() return sw(0x0099) == 1 or map() == 341 end }),
  H.release(),
  H.waitFrames(90),
  -- ride to solo Leo
  rideScene(function()
    return map() == 341 and H.hasControl() and H.tileAligned()
       and bright() >= 15 and not H.dialogWaiting() and not H.battleLoadStarted()
       and partyOf(WEDGE) ~= 0 and partyOf(TERRA) == 0
  end, 120000, "ride to solo Leo"),
  H.waitFrames(45),
  H.call(function()
    H.log(string.format("[kf] solo Leo at (%d,%d) map=%d", H.fieldX(), H.fieldY(), map()))
  end),
  -- stage below Kefka
  H.navTo(24, 19, { maxFrames = 15000, playBattles = "flee",
    avoid = { { 9, 28 }, { 9, 29 }, { 9, 30 }, { 9, 31 }, { 9, 32 }, { 9, 33 },
              { 9, 34 }, { 24, 16 }, { 25, 16 }, { 27, 16 }, { 28, 15 },
              { 24, 15 }, { 25, 15 } } }),
  H.release(),
  H.waitUntil(function()
    return map() == 341 and H.hasControl() and H.tileAligned()
       and bright() >= 15 and not H.dialogWaiting() and not H.battleLoadStarted()
  end, 6000, "staged below Kefka", 10),
  H.waitFrames(30),
  H.saveState("massacre_staged.mss"),
  H.call(function() dumpNpcAt(24, 18, "staged") end),
  -- face up, dump, then edge-A a few times, dumping between
  H.hold({ "up" }), H.waitFrames(6), H.release(), H.waitFrames(8),
  H.call(function() dumpNpcAt(24, 18, "faced-up") end),
  -- drive edge-A for up to 4000 frames, logging state transitions
  (function() local ph, hb = 0, -100
    return H.driveUntil(function()
      return H.battleLoadStarted() or H.battleActive()
    end, 4000, {
      H.call(function()
        ph = (ph + 1) % 16
        H.setPad(ph < 4 and { "a" } or {})
        if H.frame - hb >= 60 then
          hb = H.frame
          H.log(string.format("[kf drive] f%d (%d,%d) map=%d bLoad=%s bAct=%s "
            .. "dlg=%s ctrl=%s evt=%s", H.frame, H.fieldX(), H.fieldY(), map(),
            tostring(H.battleLoadStarted()), tostring(H.battleActive()),
            tostring(H.dialogWaiting()), tostring(H.hasControl()),
            tostring(H.eventRunning and H.eventRunning() or "?")))
        end
      end),
    }, "drive A into battle 124")
  end)(),
  H.call(function() dumpNpcAt(24, 18, "post-A") end),
  H.logStep(function()
    return string.format("kefka probe done map=%d battleLoad=%s",
      map(), tostring(H.battleLoadStarted()))
  end),
})
