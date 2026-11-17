-- @suite savestate=wor_leo
-- save_leo.lua -- the reveal survives a save and the title's Continue (#552, docs/design/leo-reveal.md).
--
-- gen_wor_leo saved slot 3 through the Save menu on the world map by Thamasa after Leo's reveal, LEO leading.
-- From its state: the console's Reset (a person's button the pad cannot carry; tools/state_write_waivers.txt),
-- the title, Continue slot 3, until the party stands on the world map with control.  Asserted after the load:
-- the slot's record is the battery's slot 3 (read before the Reset) (actor $0C, graphics $10, the name LEO, vigor/speed/stamina/magic, max
-- HP), event switch $00E0 is set, the saved field palette for slot 12 ($1f70+12) is Leo's (palette 0), the
-- world map draws the leader in Leo's sprite and palette ($11fb/$11fc); then Thamasa's door: the leader's
-- field object (object 12) wears graphics $10 and palette 0; the main menu loads Leo's portrait
-- (PortraitGfxPtrs entry $10).  Screenshots: the world map and Thamasa after the Continue.
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 12
local REC = 0x1600 + 37 * GOGO
local SW_BYTE, SW_BIT = 0x1E9C, 0x01             -- event switch $00E0
local THAMASA_DOOR, MAP_THAMASA = { 251, 230 }, 344
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function map() return H.mapId() & 0x1FF end

local saved = {}
local portraitLeo, continued = 0, 0
H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/wor_leo.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    -- the battery's slot 3 (SRAM $306000 + $1400, the block from $1600): what the Continue will load
    local function slot3(a) return emu.read(0x306000 + 0x1400 + (a - 0x1600), emu.memType.snesMemory) end
    for i = 0, 0x24 do saved[i] = slot3(REC + i) end
    H.assertEq(slot3(SW_BYTE) & SW_BIT, SW_BIT, "the battery's slot 3 holds switch $00E0 set")
    H.assertEq(slot3(0x1F70 + GOGO), 0x00, "and slot 12's field palette Leo's")
    H.assertEq(saved[1], 0x10, "the state is gen_wor_leo's, after the reveal")
    local pp = H.sym("PortraitGfxPtrs@menu_code") + 2 * 0x10
    emu.addMemoryCallback(function() portraitLeo = portraitLeo + 1 end, emu.callbackType.read, pp, pp + 1)
    local c = H.sym("Ot6EsperContinue")
    emu.addMemoryCallback(function() continued = continued + 1 end, emu.callbackType.exec, c, c)
    H.expectTitle("save_leo: the console's Reset before the Continue")
    emu.reset()
  end),
  -- the title: Start, then A on the load menu's slot (the cursor starts on the slot last saved)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.withReset(H.driveUntil(function()
      return continued > 0 and H.worldMode() and H.worldHasControl() and bright() >= 15
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        -- (the world-map flags read the RAM the Reset left until the load replaces it)
        if continued > 0 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue slot 3 -> the world map"), function() ph = 0 end)
  end)(),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.screenshot("save_leo_world")
    H.assertEq(continued, 1, "the title's Continue ran (Ot6EsperContinue, once)")
    for i = 0, 0x24 do
      if i < 0x09 or i > 0x14 then   -- HP/MP/Exp/status ride play; the rest is the record as saved
        H.assertEq(H.readByte(REC + i), saved[i], string.format("after the Continue: record byte +$%02X as saved", i))
      end
    end
    H.assertEq(H.readWord(REC + 0x0B), saved[0x0B] | (saved[0x0C] << 8), "after the Continue: max HP as saved")
    H.assertEq(H.readByte(SW_BYTE) & SW_BIT, SW_BIT, "after the Continue: switch $00E0 set")
    H.assertEq(H.readByte(0x1F70 + GOGO), 0x00, "after the Continue: slot 12's saved field palette is Leo's (0)")
    H.log(string.format("[save_leo] after the Continue: world (%d,%d), the leader drawn as graphics $%02X palette $%02X",
      H.worldX(), H.worldY(), H.readByte(0x11FB), H.readByte(0x11FC)))
    H.assertEq(H.readByte(0x11FB), 0x10, "the world map draws the leader in Leo's sprite")
    H.assertEq(H.readByte(0x11FC), 0x00, "in Leo's palette")
  end),
  H.worldNavTo(THAMASA_DOOR[1], THAMASA_DOOR[2], { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return map() == MAP_THAMASA and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_THAMASA and H.hasControl() and bright() >= 15 end, 2400, "Thamasa", 1),
  H.waitFrames(20),
  H.call(function()
    H.screenshot("save_leo_thamasa")
    local o = 0x0878 + 41 * GOGO
    H.log(string.format("[save_leo] Thamasa: object 12 graphics $%02X, palette bits $%02X; the party object $%04X",
      H.readByte(o + 1), H.readByte(o + 8) & 0x0E, H.readWord(0x0803)))
    H.assertEq(H.readByte(o + 1), 0x10, "Thamasa: slot 12's field object wears Leo's sprite")
    H.assertEq(H.readByte(o + 8) & 0x0E, 0x00, "Thamasa: in Leo's palette")
    H.assertEq(H.readWord(0x0803), 41 * GOGO, "Thamasa: LEO leads (the party object is object 12)")
  end),
  H.driveUntil(function() return H.menuRunning() and H.readByte(0x26) == 0x05 end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "the main menu"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(portraitLeo > 0, true, "the main menu loads Leo's portrait after the Continue")
    H.log("[save_leo] PASS: the reveal came back with the save: record, switch, sprite, palette, portrait")
  end),
})
