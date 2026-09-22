-- @manual
-- lab_rizopas_bake.lua -- the Rizopas lab's fixture half (#162).  Boots
-- train_done (gen_sabin_falls' own boot fixture), walks to Baren Falls
-- exactly the way the generator does (the walk below is the generator's,
-- verbatim -- the same copy probe_falls_wedge.lua carries), stands on the
-- post-arrival tile (15,10) on map 156, and banks one savestate there,
-- falls_prejump.mss, for lab_rizopas_template.lua to branch into
-- policy x seed experiments (docs/TESTING.md: one legitimately reached
-- snapshot, many experiments).
--
-- Also logs, read-only, what the party brings to the falls -- the lab
-- header's "what SABIN and CYAN carry" row: levels, HP/MP, every gear
-- slot, the Blitzes known ($1D28) and the SwdTech level ($1CF7), and the
-- bag's care items.
--
-- Then, AFTER the snapshot is banked, it continues along the generator's
-- own path (H.navTo(13,11), hold up, answer "Jump?") with the lib's seed
-- watch armed and stops at battle-up: that measures the seed the
-- qualification run draws in this tree ($be at InitBattle's store),
-- so the lab's declared spread can include it by measurement rather than
-- by guess.  Nothing here fights Rizopas: the run ends at battle-up.
--
-- Pad presses and reads only; complete snapshots only.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/train_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local CH_SEL, CH_MAX, NAME_MENU = 0x056E, 0x056F, 0x0200

-- ===================== verbatim from gen_sabin_falls.lua =====================
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end

local function ride(dir, pred, what, budget, fightMode, choiceWant)
  local phase, hb, quiet = 0, -900, 0
  return H.driveUntil(pred, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format(
          "ride[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s b=%s ch=%d/%d",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle()), H.readByte(CH_SEL), H.readByte(CH_MAX)))
      end

      if inBattle() or H.battleLoadStarted() then
        H.setPad({ l = true, r = true })   -- flee, with real input
        return
      end

      if H.readByte(CH_MAX) >= 2 and H.dialogWaiting() then
        local sel, want = H.readByte(CH_SEL), choiceWant or 0
        if sel < want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      end

      if H.readByte(NAME_MENU) == 1 and H.readByte(0x0059) ~= 0
         and (H.readByte(0x0026) == 0x5F or H.readByte(0x0027) == 0x5F) then
        quiet = quiet + 1
        if quiet >= 30 then
          if quiet == 30 then
            H.log(string.format("[falls] NAME MENU at f%d -- START", H.frame))
          end
          H.setPad(phase < 4 and { "start" } or {})
          return
        end
        H.setPad({})
        return
      end
      quiet = 0

      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad(dir and { [dir] = true } or {})
    end),
  }, what)
end

local function settle(toMap, what)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 5000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[falls] %s: map=%d (%d,%d)", what, mapIdx(),
        H.fieldX(), H.fieldY()))
    end),
  }, {})
end

local function worldToMap(tx, ty, what, budget)
  return H.worldNavTo(tx, ty, { maxFrames = budget or 30000,
    playBattles = "tactical",
    arrive = function() return not H.worldMode() end })
end

local function seq(steps) return H.cond(function() return true end, steps) end

local function walkToFalls()
  return seq({
    worldToMap(185, 93, "falls cave (185,93)", 20000),
    settle(166, "cave 166"),
    H.navTo(7, 5, { maxFrames = 6000, playBattles = "tactical" }),
    ride("up", function() return mapIdx() == 155 end, "-> 155", 3000),
    settle(155, "overlook 155"),
    H.navTo(10, 5, { maxFrames = 6000, playBattles = "tactical" }),
    ride("up", function() return mapIdx() == 156 end, "-> 156", 3000),
    settle(156, "falls top 156"),
    ride("up", function()
      return sw(0x3C) == 1 and H.hasControl() and H.tileAligned()
    end, "arrival scene ($003C)", 15000),
    H.call(function()
      H.assertEq(sw(0x3C), 1, "$003C -- Baren Falls named")
      H.assertEq(inParty(3), false, "SHADOW left at the overlook")
      H.log(string.format("[falls] post-arrival at (%d,%d)", H.fieldX(),
        H.fieldY()))
    end),
  })
end
-- =================== end of the verbatim generator copy ====================

-- Character record $1600 + 37*c (field-ram.txt:885-927): +8 level, +9 HP,
-- +11 max HP, +13 MP, +15 max MP, +$1E esper, +$1F..+$24 weapon/shield/
-- helm/armor/relic/relic.  $1D28 known Blitzes (bit n = Blitz n),
-- $1CF7 known SwdTechs (field-ram.txt:946-948).
local function probeParty(tag)
  for _, c in ipairs(H.partyMembers()) do
    local b = 0x1600 + 37 * c
    local r, l = H.readByte(b + 0x1F), H.readByte(b + 0x20)
    H.log(string.format("[party] %s char=%d L%d hp=%d/%d mp=%d/%d esper=$%02X "
      .. "gear=%02X,%02X,%02X,%02X,%02X,%02X rclass=$%02X lclass=$%02X",
      tag, c, H.readByte(b + 8), H.readWord(b + 9), H.readWord(b + 11),
      H.readWord(b + 13), H.readWord(b + 15), H.readByte(b + 0x1E), r, l,
      H.readByte(b + 0x21), H.readByte(b + 0x22), H.readByte(b + 0x23),
      H.readByte(b + 0x24), H.weaponClass(r), H.weaponClass(l)))
  end
  H.log(string.format("[skills] %s blitz_known=$%02X swdtech_known=$%02X",
    tag, H.readByte(0x1D28), H.readByte(0x1CF7)))
  H.log(string.format("[bag] %s tonic=%d potion=%d fenix=%d antidote=%d",
    tag, H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0),
    H.invCountOf(0xEB)))
end

-- the seed the gen path draws: read off the `sta $be` store, the way
-- H.newSeedSweep and the Nerapa lab read it
local seedDrawn, seedN = nil, 0
local function armSeedWatch()
  local addr = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    seedN = seedN + 1
    local seed = emu.getState()["cpu.a"] & 0xff
    if seedDrawn == nil then seedDrawn = seed end
    H.log(string.format("[bake] battle %d seeded $be=$%02X from $021e=%d at f%d",
      seedN, seed, H.readByte(0x021E), H.frame))
  end, emu.callbackType.exec, addr, addr)
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the World of Balance")
    H.assertEq(sw(0x3B), 1, "$003B set -- the train is behind us")
    H.log(string.format("[falls] start world (%d,%d)", H.worldX(), H.worldY()))
    probeParty("at train_done")
  end),
  walkToFalls(),
  H.call(function()
    H.log(string.format("[bake] post-arrival phase $021e=%d at f%d", H.readByte(0x021E), H.frame))
  end),
  -- the probe's recipe: ten quiet frames, then the snapshot
  H.waitFrames(10),
  H.call(function()
    H.assertEq(mapIdx(), 156, "on the falls top (156)")
    H.assertEq(H.fieldX() == 15 and H.fieldY() == 10, true, "standing on the post-arrival tile (15,10)")
    H.assertEq(inParty(5) and inParty(2), true, "SABIN and CYAN in the party")
    probeParty("at the falls")
    H.log(string.format("[bake] prejump phase $021e=%d at f%d", H.readByte(0x021E), H.frame))
  end),
  H.saveState("falls_prejump.mss"),
  H.logStep(function() return string.format("[bake] falls_prejump banked at f%d map 156 (%d,%d)", H.frame, H.fieldX(), H.fieldY()) end),

  -- the generator's own continuation, to battle-up only
  H.call(function()
    armSeedWatch()
    H.log(string.format("[bake] gen path: navTo(13,11) begins at phase $021e=%d f%d", H.readByte(0x021E), H.frame))
  end),
  H.navTo(13, 11, { maxFrames = 5000, playBattles = "tactical" }),
  H.call(function()
    H.log(string.format("[bake] gen path: at (%d,%d) phase $021e=%d f%d; holding up", H.fieldX(), H.fieldY(), H.readByte(0x021E), H.frame))
  end),
  ride("up", function() return H.battleLoadStarted() end, "gen path to battle-up", 8000),
  H.release(),
  H.call(function()
    H.log(string.format("[bake] gen path battle-up at f%d: $BE=$%02X $021e=%d store seed=%s nseeds=%d",
      H.frame, H.readByte(0xBE), H.readByte(0x021E),
      seedDrawn and string.format("$%02X", seedDrawn) or "none", seedN))
  end),
})
