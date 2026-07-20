-- gen_sabin_falls.lua -- leg 9 of SABIN's scenario: Baren Falls.  Mints:
--   falls_done.mss   map 159 (the Veldt shore), SABIN+CYAN, $003C/$003F set
--                    -- SHADOW left at the overlook, GAU named but NOT
--                    joined (he grabs nothing and runs; recruitment is the
--                    next leg's Veldt work).
--
-- THE ROUTE (entrances decoded from trigger/*.dat; events read at the
-- cited lines):
--   world (178,93) -- train_done's landing -- walk E to (185,93)
--     -> map 166 (9,13)                       [world short-entrance]
--   166 (7,4)  -> map 155 (11,11)             [long entrance, len 1]
--   155 (10,4) -> map 156 (15,20)             [short entrance; (10,5) is a
--                                              sound trigger, harmless]
--   156: walking UP crosses the y=12 row -> _cbbef1/_cbbfa5
--     (event_main.asm:66235/66317): "This must be Baren Falls", $003C=1,
--     and SHADOW LEAVES ("I have served my purpose…", char_party SHADOW,0,
--     $02F3=0) -- the party is SABIN+CYAN from here.
--   156 y=10 row, facing up -> _cbc03f (:66422): "Jump?"; option 0
--     (_cbc058) rides the fall.  The $01B5 once-latch is per-standing --
--     player.asm:529 clears it every step -- so no stale-state hazard.
--   battle 18 fires mid-fall (:66479) and its tail is _ca5ea9's win-bit
--     check, so the fight runs REAL (party pinned, monsters clamped to
--     1 hp, tap-A -- the engine's own swing wins).  RIZOPAS ($0155) HIDES
--     IN SLOT 5 behind two visible Piranhas and is surfaced by the
--     piranhas' own death script, so the watch below KEYS ON THE
--     SURFACING (slot-5 present bit), never on battle-up formation words.
--     Its authored row (Ot6ShieldTbl: 5 shields, SLASH|BLUDG) is read the
--     frame it surfaces.
--   Then the shore: load 159 {15,0}, the wash-ashore cinematic, GAU's
--     intro (dlg $02E6), `name_menu GAU` -- driven by the menu module's own
--     state ($0026/$0027 == $5F -> press START, gen_sabin_camp's idiom) --
--     "And you are?", GAU runs off, $003F=1, control returns.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/train_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local CH_SEL, CH_MAX, NAME_MENU = 0x056E, 0x056F, 0x0200
local RIZOPAS = 0x0155
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function pinParty()
  for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
end

local rizo = { seen = false, species = 0, shields = 0, smax = 0, wkc = 0,
               mask0 = nil }

-- ride/walk driver: choices steered by CH_SEL, name menu by menu state,
-- battles per fightMode ("real": pin+clamp -- the win bit is earned;
-- "killbit": the house trash idiom), dialogs tap-A, else hold `dir` (or
-- hands-off when dir is nil).
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
        if fightMode == "real" then
          pinParty()
          -- the rizopas watch: record the seed row THE FRAME IT SURFACES,
          -- before the clamp below can touch it
          if not rizo.mask0 and H.battleLoadStarted() then
            local m = 0
            for s = 0, 5 do if monPresent(s) then m = m | (1 << s) end end
            rizo.mask0 = m
            H.log(string.format("[falls] battle-up present mask=$%02X", m))
          end
          if not rizo.seen and monPresent(5) then
            rizo.seen = true
            rizo.species = H.readWord(0x57C0 + 10)
            rizo.shields = H.readByte(0x3E38 + 8 + 10)
            rizo.smax    = H.readByte(0x3E39 + 8 + 10)
            rizo.wkc     = H.readByte(0x3E9C + 8 + 10)
            H.log(string.format(
              "[falls] slot 5 SURFACED: species=$%04X shields=%d/%d wkc=$%02X",
              rizo.species, rizo.shields, rizo.smax, rizo.wkc))
          end
          for s = 0, 5 do
            if monPresent(s) and H.readWord(0x3BFC + s * 2) > 1 then
              H.writeWord(0x3BFC + s * 2, 1)
            end
          end
        else
          if H.monstersPresent() > 0 then
            for s = 0, 5 do
              if monPresent(s) then
                H.writeByte(0x3eec + s * 2,
                  H.readByte(0x3eec + s * 2) | 0x80)
              end
            end
          end
        end
        H.setPad(phase < 4 and { "a" } or {})
        return
      end

      -- choice prompts: steer to choiceWant then confirm
      if H.readByte(CH_MAX) >= 2 and H.dialogWaiting() then
        local sel, want = H.readByte(CH_SEL), choiceWant or 0
        if sel < want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      end

      -- the name menu, on the menu module's own state (gen_sabin_camp)
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

-- world walk: the lib's verified-step walker (kill-bits trash inline and
-- stalls out the post-battle world reload); the entrance firing mid-plan
-- is the arrival
local function worldToMap(tx, ty, what, budget)
  return H.worldNavTo(tx, ty, { maxFrames = budget or 30000,
    arrive = function() return not H.worldMode() end })
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the World of Balance")
    H.assertEq(sw(0x3B), 1, "$003B set -- the train is behind us")
    H.log(string.format("[falls] start world (%d,%d)", H.worldX(), H.worldY()))
  end),

  -- world -> the falls cave 166 -> the overlook 155 -> the falls 156
  worldToMap(185, 93, "falls cave (185,93)", 20000),
  settle(166, "cave 166"),
  H.navTo(7, 5, { maxFrames = 6000 }),
  ride("up", function() return mapIdx() == 155 end, "-> 155", 3000),
  settle(155, "overlook 155"),
  H.navTo(10, 5, { maxFrames = 6000 }),
  ride("up", function() return mapIdx() == 156 end, "-> 156", 3000),
  settle(156, "falls top 156"),

  -- up into the y=12 row: the arrival scene; SHADOW leaves
  ride("up", function()
    return sw(0x3C) == 1 and H.hasControl() and H.tileAligned()
  end, "arrival scene ($003C)", 15000),
  H.call(function()
    H.assertEq(sw(0x3C), 1, "$003C -- Baren Falls named")
    H.assertEq(inParty(3), false, "SHADOW left at the overlook")
    H.log(string.format("[falls] post-arrival at (%d,%d)", H.fieldX(),
      H.fieldY()))
  end),

  -- onto the jump row facing up; "Jump?" option 0; the fall; battle 18
  -- (real, with the rizopas watch); the shore cinematic + GAU's name menu
  H.navTo(13, 11, { maxFrames = 5000 }),
  ride("up", function()
    return mapIdx() == 159 and sw(0x3F) == 1 and H.hasControl()
       and H.tileAligned() and bright() >= 15
  end, "jump + battle 18 + the shore", 40000, "real", 0),

  H.call(function()
    H.assertEq(mapIdx(), 159, "washed ashore on map 159")
    H.assertEq(sw(0x3F), 1, "$003F -- GAU met and named")
    H.assertEq(rizo.seen, true, "RIZOPAS surfaced in slot 5 (the piranhas' "..
      "death script ran)")
    H.assertEq(rizo.species, RIZOPAS, "slot 5 was RIZOPAS ($0155)")
    H.assertEq(rizo.shields, 5, "RIZOPAS seeds 5 shields (Ot6ShieldTbl)")
    H.assertEq(rizo.wkc, 0x05, "RIZOPAS class row SLASH|BLUDG ($05)")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq(inParty(3), false, "SHADOW gone")
    H.assertEq(inParty(11), false, "GAU did NOT join here")
    H.log(string.format("[falls_done] f%d map=%d (%d,%d) mask0=$%02X",
      H.frame, mapIdx(), H.fieldX(), H.fieldY(), rizo.mask0 or -1))
    H.screenshot("falls_done")
  end),
  H.saveState("falls_done.mss"),
  H.logStep(function()
    return string.format("falls_done minted at frame %d map 159 (%d,%d)",
      H.frame, H.fieldX(), H.fieldY())
  end),
})
