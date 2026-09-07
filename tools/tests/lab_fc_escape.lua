-- @manual
-- lab_fc_escape.lua -- the escape-policy lab: from escape_start (first
-- control on the escape map 393 with the 6:00 master clock and Shadow's
-- 5:55 clock running -- gen_fc_escape's second artifact) to Shadow's
-- arrival at the ledge, under ONE declared walking policy:
--
--   POLICY = "fight"  every random on 393 is fought through the real
--                     menus (the no-flee directive applied to the escape)
--   POLICY = "run"    the game's own L+R run is held for the walks; a
--                     formation that refuses is fought (gen_fc_escape's
--                     policy)
--
-- Same snapshot, same seed, one variable: whether fighting every random
-- fits inside the clock.  Reads and pad presses only.  A game over (the
-- clock's expiry or a wipe) is the measurement, not a retry.
local H = dofile("tools/tests/lib/ot6.lua")

local POLICY = "fight"

local TERRA, EDGAR = 0x00, 0x04
local function map() return H.mapId() & 0x3ff end
local function mapIs(m) return map() == m end
local function nerapaUp() return (H.readByte(0x1EEC) >> 1) & 1 == 1 end    -- $0361
local function shadowSaved() return (H.readByte(0x1EEF) >> 5) & 1 == 1 end -- $037D

local FIGHT_ESCAPE = { tactical = true, boost = true, bank = 0, items = true,
                       healPercent = 40, nuke = { 2 },
                       summon = { [TERRA] = { mp = 30 }, [EDGAR] = { mp = 27 } } }
local FE = H.newFightDriver("Nerapa", FIGHT_ESCAPE)
local FW = H.newFightDriver("ledge", FIGHT_ESCAPE)
local WALK
if POLICY == "fight" then
  WALK = { playBattles = "tactical", bank = 0, healPercent = 60, care = false,
           nuke = { 2 }, summon = FIGHT_ESCAPE.summon }
else
  WALK = { playBattles = "mustflee", fleeCap = 600, bank = 0, healPercent = 60, care = false }
end

local function clock(tag)
  return H.call(function()
    local f0, c0 = H.readByte(0x1188), H.readWord(0x1189)
    local f2, c2 = H.readByte(0x1188 + 12), H.readWord(0x1189 + 12)
    H.log(string.format("[escape clock] %s: master=%d frames (%d:%02d) flags=%02X | shadow=%d flags=%02X | at (%d,%d) f%d",
      tag, c0, c0 // 3600, (c0 % 3600) // 60, f0, c2, f2, H.fieldX(), H.fieldY(), H.frame))
  end)
end

local battles = 0
local function countBattles()
  local last = false
  return H.call(function()
    local a = H.battleActive()
    if a and not last then
      battles = battles + 1
      H.log(string.format("[lab] battle %d starts at f%d, master clock %d", battles, H.frame, H.readWord(0x1189)))
    end
    last = a
  end)
end

local function absorb(pred, cap, tag, driver)
  local t = 0
  return H.driveUntil(function()
    t = t + 1
    if (H.gameOverFired or 0) > 0 then
      error(string.format("%s: the party was LOST (game over) -- the measurement", tag), 0)
    end
    return t >= cap or pred()
  end, cap + 500, {
    H.call(function()
      if H.battleLoadStarted() or H.battleActive() then driver.frame(); return end
      local mx = H.readByte(0x056F)
      if mx > 0 then
        local want, sel, ph = mx - 1, H.readByte(0x056E), t % 24
        if sel < want then H.setPad(ph < 3 and { down = true } or {})
        elseif sel > want then H.setPad(ph < 3 and { up = true } or {})
        else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
        return
      end
      if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
      else H.setPad({}) end
    end),
  }, tag)
end

local function talk(face, cap, tag)
  local t = 0
  return H.driveUntil(function()
    t = t + 1
    return t >= cap or H.battleActive() or H.battleLoadStarted()
  end, cap + 300, {
    H.call(function()
      local c = t % 48
      if c < 4 then H.setPad({ [face] = true })
      elseif c >= 24 and c < 28 then H.setPad({ a = true })
      else H.setPad({}) end
    end),
  }, tag)
end

H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/escape_start.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIs(393), true, "escape_start is on the escape map (393)")
    H.log(string.format("[lab] POLICY=%s at (%d,%d)", POLICY, H.fieldX(), H.fieldY()))
  end),
  clock("lab start"),
  H.navTo(106, 15, { maxFrames = 30000, playBattles = WALK.playBattles, fleeCap = WALK.fleeCap,
    bank = WALK.bank, healPercent = WALK.healPercent, care = false, nuke = WALK.nuke,
    summon = WALK.summon }),
  clock("at Nerapa's doorstep"),
  H.release(),
  H.waitFrames(30),
  talk("right", 4000, "Nerapa engaged"),
  absorb(function()
    return not nerapaUp() and not H.battleActive() and not H.battleLoadStarted()
  end, 30000, "Nerapa falls ($0361 clears)", FE),
  H.call(function() H.assertEq(nerapaUp(), false, "Nerapa defeated") end),
  clock("post-Nerapa"),
  H.navTo(112, 15, { maxFrames = 12000, playBattles = WALK.playBattles, fleeCap = WALK.fleeCap,
    bank = WALK.bank, care = false, nuke = WALK.nuke, summon = WALK.summon }),
  (function()
    local near = false
    return H.navTo(115, 17, { maxFrames = 12000, playBattles = WALK.playBattles, fleeCap = WALK.fleeCap,
      bank = WALK.bank, care = false, nuke = WALK.nuke, summon = WALK.summon,
      arrive = function()
        if H.fieldX() == 115 and H.fieldY() == 17 then near = true end
        return near
      end })
  end)(),
  clock("at the ledge"),
  (function()
    local t = 0
    return H.driveUntil(function()
      t = t + 1
      if (H.gameOverFired or 0) > 0 then error("the wait was LOST (game over) -- the measurement", 0) end
      return t >= 26000 or shadowSaved()
    end, 26500, {
      H.call(function()
        if t % 2400 == 0 then
          H.log(string.format("  [wait] t=%d (%d,%d) t0=%d t2=%d", t, H.fieldX(), H.fieldY(),
            H.readWord(0x1189), H.readWord(0x1189 + 12)))
        end
        if H.battleLoadStarted() or H.battleActive() then FW.frame(); return end
        local mx = H.readByte(0x056F)
        if mx > 0 then
          local want, sel, ph = mx - 1, H.readByte(0x056E), t % 24
          if sel < want then H.setPad(ph < 3 and { down = true } or {})
          elseif sel > want then H.setPad(ph < 3 and { up = true } or {})
          else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
          return
        end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        if x == 115 and y == 17 then H.setPad({}); return end
        local ph = t % 24
        if ph >= 3 then H.setPad({}); return end
        if x < 115 then H.setPad({ right = true })
        elseif x > 115 then H.setPad({ left = true })
        elseif y < 17 then H.setPad({ down = true })
        else H.setPad({ up = true }) end
      end),
    }, "the humane wait ($037D)")
  end)(),
  H.call(function()
    H.assertEq(shadowSaved(), true, "$037D set -- Shadow saved under POLICY=" .. POLICY)
    H.log(string.format("[lab] POLICY=%s: Shadow saved at f%d", POLICY, H.frame))
  end),
})
