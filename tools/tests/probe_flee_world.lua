-- @manual
-- probe_flee_world.lua -- #150: on a FLEEABLE random, does the mustflee
-- helper hold L+R and does the party actually leave?  Boots camp_escaped
-- (Sabin's scenario, the world map outside the Imperial camp) and walks the
-- route gen_sabin_forest walks, toward the Phantom Forest entrance (178,82),
-- under playBattles="mustflee".  A startFrame observer logs the engine's
-- own run machinery through every battle:
--   $b1     bit 1 = the escape command's own can't-run gate (Cmd_2a,
--           battle_main.asm), bit 2 = the smoke-bomb can't-run bit
--   $2f45   characters-are-running (L+R seen and not blocked)
--   $3a3b   run difficulty; $3d70,2,4,6 the per-character run counters
--   $3a38   character-just-ran-away latch; $b0 bit 2 the run action latch
-- Reads and pad presses only; the [ot6pad] lines are the helper's L+R.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/camp_escaped.mss.lua"
local WANT_BATTLES = 2

local battles, inBattle, bN = 0, false, 0
local ranLatch = false
local hpLine = function()
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    out[#out + 1] = string.format("c%d %d/%d L%d", c, H.charHp(c), H.charMaxHp(c),
      H.readByte(0x1600 + 37 * c + 8))
  end
  return table.concat(out, " ")
end

emu.addEventCallback(function()
  local live = H.battleLoadStarted()
  if live and not inBattle then
    inBattle, bN, ranLatch = true, 0, false
    battles = battles + 1
    H.log(string.format("[flee probe] battle %d up at f%d formation %04X %04X %04X %04X %04X %04X",
      battles, H.frame, H.readWord(0x57C0), H.readWord(0x57C2), H.readWord(0x57C4),
      H.readWord(0x57C6), H.readWord(0x57C8), H.readWord(0x57CA)))
  end
  if inBattle then
    bN = bN + 1
    if H.readByte(0x3a38) ~= 0 and not ranLatch then
      ranLatch = true
      H.log(string.format("[flee probe] battle %d: $3a38=%02X -- a character JUST RAN AWAY at battle frame %d (f%d)",
        battles, H.readByte(0x3a38), bN, H.frame))
    end
    if bN <= 4 or bN % 60 == 0 then
      H.log(string.format("[flee probe] b%d +%d $b1=%02X $2f45=%d $3a3b=%d counters=%d,%d,%d,%d $3a38=%02X $b0=%02X $2f4b=%02X $3ebc=%02X",
        battles, bN, H.readByte(0x00b1), H.readByte(0x2f45), H.readByte(0x3a3b),
        H.readByte(0x3d70), H.readByte(0x3d72), H.readByte(0x3d74), H.readByte(0x3d76),
        H.readByte(0x3a38), H.readByte(0x00b0), H.readByte(0x2f4b), H.readByte(0x3ebc)))
    end
  end
  if not live and inBattle then
    inBattle = false
    H.log(string.format("[flee probe] battle %d down at f%d after %d frames: ran=%s monstersPresent=%d $3ebc=%02X | %s",
      battles, H.frame, bN, tostring(ranLatch), H.monstersPresent(), H.readByte(0x3ebc), hpLine()))
  end
end, emu.eventType.startFrame)

H.run({ maxFrames = 200000 }, {
  H.loadState(FIX),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.worldMode(), true, "camp_escaped is on the world map")
    H.log(string.format("[flee probe] start at world (%d,%d) | %s", H.worldX(), H.worldY(), hpLine()))
  end),
  H.worldNavTo(178, 82, {
    maxFrames = 60000, playBattles = "mustflee", care = false,
    arrive = function()
      return (battles >= WANT_BATTLES and not H.battleLoadStarted()) or not H.worldMode()
    end,
  }),
  H.call(function()
    H.log(string.format("[flee probe] done at f%d after %d battle(s) at world (%d,%d) | %s",
      H.frame, battles, H.worldX(), H.worldY(), hpLine()))
  end),
})
