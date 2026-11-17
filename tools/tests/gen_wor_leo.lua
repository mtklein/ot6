-- gen_wor_leo.lua -- a branch leg beside the Gogo arc (#552, docs/design/leo-reveal.md): Continue the
-- `wor-gogo-v1` battery (STRAGO, RELM, GOGO and TERRA on foot on the Falcon's tile by Thamasa), then
--   1. the cabin without GOGO (STRAGO, RELM, TERRA, LOCKE: the save has LOCKE waiting
--      aboard in a Ribbon, which a regroup refuses (#506), so he is the one seated), Thamasa, Leo's grave (344 (54,18), facing up, A):
--      vanilla's line ($0845, "General Leo...") and nothing else;
--   2. the cabin with GOGO again, leading (GOGO, STRAGO, RELM, TERRA), the state `wor_leo_pre` in Thamasa's street, the
--      grave: the reveal scene played through, every dialogue page pressed on, in its order (GOGO's line,
--      LEO's, the first reactor's -- TERRA's in this party --, LEO's two); slot 12's record (actor $0C kept,
--      graphics $10, the name LEO, the four stats the higher of the two rows, max HP +14) and switch $00E0;
--   3. the grave again: vanilla's line;
--   4. out to the world map, a save there through the Save menu (slot 3), and the state `wor_leo`.
-- No leg boots what it leaves; the suites menu_leo, battle_leo and save_leo boot its states.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, STRAGO, RELM, GOGO = 0, 1, 7, 8, 12
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [STRAGO] = "STRAGO", [RELM] = "RELM", [GOGO] = "GOGO" }
local MAP_THAMASA = 344
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, settled, say, regroup, liftOff, watches, enterFrom, outToWorld =
  K.map, K.settled, K.say, K.regroup, K.liftOff, K.watches, K.enterFrom, K.outToWorld

local THAMASA_DOOR, FALCON = { 251, 230 }, { 250, 229 }
local GRAVE = { 54, 18 }                     -- the trigger (event_trigger.asm _344): the tile before the stone
local REC = 0x1600 + 37 * GOGO
local SW_LEO = 0x00E0                        -- code_ext.inc OT6_LEO_SWITCH
local DLG_VANILLA, DLG_LEO = 0x0845, 0x0C0C  -- "General Leo..."; event_main.asm OT6_LEO_DLG
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

-- the record as the log reads it
local function recLine(tag)
  local nm = {}
  for i = 2, 7 do nm[#nm + 1] = string.format("%02X", H.readByte(REC + i)) end
  return string.format("[leo] %s: actor $%02X graphics $%02X name %s vigor %d speed %d stamina %d magic %d "
    .. "HP %d/%d MP %d/%d switch $00E0=%d", tag, H.readByte(REC), H.readByte(REC + 1), table.concat(nm, " "),
    H.readByte(REC + 0x1A), H.readByte(REC + 0x1B), H.readByte(REC + 0x1C), H.readByte(REC + 0x1D),
    H.readWord(REC + 9), H.readWord(REC + 0x0B) & 0x3FFF, H.readWord(REC + 0x0D), H.readWord(REC + 0x0F) & 0x3FFF,
    sw(SW_LEO))
end
local function snap()
  local t = {}
  for i = 0, 0x24 do t[i] = H.readByte(REC + i) end
  return t
end

-- the grave, examined: on its tile facing up, A; every dialogue page that opens is logged ($d0, the
-- dialogue index EventCmd_4b sets), shot and pressed on, until the party is the player's again
local shown = {}
local function examine(tag)
  local n, pages, last = 0, 0, nil
  return H.withReset(H.seqStep({
    H.navTo(GRAVE[1], GRAVE[2] + 1, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
    H.navTo(GRAVE[1], GRAVE[2], { maxFrames = 3000 }),
    H.waitUntil(function() return settled() end, 600, tag .. ": on the grave's tile", 1),
    H.call(function() shown = {}; n = 0 end),
    H.faceAndHoldA("up", function() return H.dialogWaiting() end, 1200, tag .. ": face the grave, A"),
    H.release(),
    H.driveUntil(function()
      n = n + 1
      return n > 30 and settled() and not H.eventRunning()
    end, 9000, {
      H.call(function()
        if H.dialogWaiting() then
          local id = H.readWord(0x00D0) & 0x1FFF
          if id ~= last then
            last = id
            pages = pages + 1
            shown[#shown + 1] = id
            H.log(string.format("[leo] %s: dialogue $%04X open (page %d) f%d", tag, id, pages, H.frame))
            H.screenshot(string.format("%s_%02d_%04x", tag, pages, id))
          end
          H.setPad(n % 8 < 4 and { "a" } or {})
        else
          last = nil
          H.setPad({})
        end
      end),
    }, tag .. ": the grave's event, through"),
    H.release(),
    H.call(function() H.screenshot(tag .. "_after") end),
  }), function() n, pages, last = 0, 0, nil end)
end
local function assertShown(tag, want)
  local got = {}
  for _, id in ipairs(shown) do got[#got + 1] = string.format("$%04X", id) end
  local exp = {}
  for _, id in ipairs(want) do exp[#exp + 1] = string.format("$%04X", id) end
  H.log(string.format("[leo] %s: dialogue shown %s", tag, table.concat(got, " ")))
  H.assertEq(table.concat(got, " "), table.concat(exp, " "), tag .. ": the dialogue the grave showed, in order")
end

local before = nil
H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("wor-gogo-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log(recLine("boot"))
    -- hard inputs (gen_wor_gogo's play): GOGO recruited and seated, his record his own, the reveal not played
    H.assertEq(H.readByte(0x1850 + GOGO) & 7, 1, "GOGO in party 1 at the boot (gen_wor_gogo seated him)")
    H.assertEq(H.readByte(REC), 0x0C, "slot 12 holds actor $0C, GOGO (gen_wor_gogo recruited him)")
    H.assertEq(H.readByte(REC + 1), 0x0C, "slot 12 wears GOGO's sprite at the boot")
    H.assertEq(sw(SW_LEO), 0, "switch $00E0 clear at the boot: the reveal has not played")
  end),
  -- @@setup-end

  -- ---- 1. without GOGO: vanilla's grave -------------------------------------------------------------------
  -- @@stage nogogo
  regroup({ STRAGO, RELM, TERRA, LOCKE }),
  liftOff(),
  H.flyTo(FALCON[1], FALCON[2], { what = "the Falcon down by Thamasa again", fight = FIGHT }),
  H.call(function() before = snap() end),
  enterFrom(THAMASA_DOOR, MAP_THAMASA, "Thamasa without GOGO"),
  examine("nogogo"),
  H.call(function()
    assertShown("without GOGO", { DLG_VANILLA })
    H.assertEq(sw(SW_LEO), 0, "without GOGO: switch $00E0 still clear")
    local now = snap()
    for i = 0, 0x24 do
      H.assertEq(now[i], before[i], string.format("without GOGO: slot 12's record byte +$%02X unchanged", i))
    end
    H.log(recLine("without GOGO"))
  end),
  H.navTo(22, 47, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
  outToWorld("down", "off Thamasa's edge"),
  H.worldNavTo(FALCON[1], FALCON[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { THAMASA_DOOR } }),

  -- ---- 2. with GOGO: the reveal ----------------------------------------------------------------------------
  -- @@stage reveal
  regroup({ GOGO, STRAGO, RELM, TERRA }),
  liftOff(),
  H.flyTo(FALCON[1], FALCON[2], { what = "the Falcon down by Thamasa with GOGO", fight = FIGHT }),
  enterFrom(THAMASA_DOOR, MAP_THAMASA, "Thamasa with GOGO"),
  H.call(function()
    before = snap()
    H.log(recLine("before the grave"))
    H.assertEq(H.readByte(0x0879 + 41 * GOGO), 0x0C, "GOGO's field object wears his own sprite before the grave")
  end),
  H.saveState("wor_leo_pre.mss"),
  examine("reveal"),
  H.call(function()
    -- the first reactor in the scene's case order (CELES, TERRA, ...): TERRA's line in this party
    assertShown("the reveal", { DLG_LEO, DLG_LEO + 1, DLG_LEO + 5, DLG_LEO + 2, DLG_LEO + 3 })
    H.log(recLine("after the reveal"))
    H.assertEq(sw(SW_LEO), 1, "the reveal set switch $00E0")
    H.assertEq(H.readByte(REC), 0x0C, "the slot keeps actor $0C (Mimic, the picker and the final order key on it)")
    H.assertEq(H.readByte(REC + 1), 0x10, "slot 12 wears Leo's sprite (graphics $10)")
    local name = {}
    for i = 2, 7 do name[#name + 1] = string.format("%02X", H.readByte(REC + i)) end
    H.assertEq(table.concat(name, " "), "8B 84 8E FF FF FF", "slot 12's name is LEO")
    local leo = { 52, 38, 41, 36 }              -- char_prop.asm, Leo's row: vigor, speed, stamina, magic
    for i = 0, 3 do
      H.assertEq(H.readByte(REC + 0x1A + i), math.max(before[0x1A + i], leo[i + 1]),
        string.format("stat +$%02X is the higher of GOGO's (%d) and Leo's (%d)", 0x1A + i, before[0x1A + i], leo[i + 1]))
    end
    local maxHp0 = (before[0x0B] | (before[0x0C] << 8)) & 0x3FFF
    H.assertEq(H.readWord(REC + 0x0B) & 0x3FFF, math.min(9999, maxHp0 + 14), "max HP up by Leo's base over GOGO's (50 - 36)")
    H.assertEq(H.readWord(REC + 0x0B) & 0xC000, ((before[0x0C] << 8) & 0xC000), "max HP's boost bits kept")
    H.assertEq(H.readWord(REC + 0x0F), before[0x0F] | (before[0x10] << 8), "max MP kept (GOGO's base, 12, is the higher)")
    for i = 0x16, 0x19 do
      H.assertEq(H.readByte(REC + i), before[i], string.format("command +$%02X kept", i))
    end
    for i = 0x1E, 0x24 do
      H.assertEq(H.readByte(REC + i), before[i], string.format("esper/equipment +$%02X kept", i))
    end
  end),

  -- ---- 3. the grave again: vanilla's line ------------------------------------------------------------------
  -- @@stage again
  examine("again"),
  H.call(function()
    assertShown("after the reveal", { DLG_VANILLA })
    H.log(recLine("after the second look"))
  end),

  -- ---- 4. out, and a save on the world map ----------------------------------------------------------------
  -- @@stage save
  H.navTo(22, 47, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
  outToWorld("down", "off Thamasa's edge"),
  H.worldNavTo(FALCON[1], FALCON[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { THAMASA_DOOR } }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled by the Falcon", 5),
  H.call(function()
    H.screenshot("leo_worldmap")
    -- the leader on the world map: graphics and palette from the field object and $1f70 (world_start.asm)
    H.log(string.format("[leo] the world map's leader: graphics $%02X, palette $%02X", H.readByte(0x11FB),
      H.readByte(0x11FC)))
    H.assertEq(H.readByte(0x11FB), 0x10, "the world map draws the leader, LEO, in Leo's sprite")
    H.assertEq(H.readByte(0x11FC), 0x00, "in Leo's palette (map sprite palette 0)")
  end),
  H.saveGame({ slot = 3, baseline = false, tag = "the save after the reveal" }),
  H.call(function()
    H.assertSavedSlotWorld(FALCON[1], FALCON[2], "the save after the reveal", 3, 1)
    say("wor", "saved")
    H.log(recLine("saved"))
  end),
  H.saveState("wor_leo.mss"),
  H.logStep(function()
    return string.format("wor_leo generated: the reveal played at Leo's grave, saved in slot 3 by the Falcon at "
      .. "Thamasa, world (%d,%d)", H.worldX(), H.worldY())
  end),
})
