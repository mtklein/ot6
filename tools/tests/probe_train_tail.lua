-- probe_train_tail.lua -- what happens AFTER the minecart's sixth fight.
--
-- gen_n128's first run rode `cutscene TRAIN` correctly: six battles in
-- order, the last one formation `010B 0140 292A 013F` -- NUMBER 128 with
-- both blades -- and then the run wedged.  From ~frame 8800 to the 80000
-- budget the state never changed: map id 0, worldMode true, hasControl
-- false, no battle.  Map 240 never loaded and $0069 never set.
--
-- Two candidate causes, and they need different fixes, so this measures
-- rather than guesses:
--   (a) the party was WIPED and the game is sitting on GAME OVER / the
--       title screen.  The Makefile's tier-3 notes already record that
--       shape -- "battles 15/16/17 are each WON BY TAP-A (battle-clear
--       write -> GameOver softlock)" -- and this fight is LOCKE ALONE, so
--       it is the obvious suspect;
--   (b) the train script never reached its `$ff` item, so TrainCmd_ff's
--       `stz $f0 / stz $22 / inc $19` (world/train_script.asm:951-957)
--       never ran and the cutscene is still nominally live.
--
-- Distinguishing evidence dumped below: party battle HP ($3BF4), the
-- field character HP table ($1609 + 37*c), the raw map word $1F64, the
-- fade/exit byte $19, the event PC {$e5,$e6,$e7}, screen brightness, and
-- screenshots -- a GAME OVER or title screen is unmistakable in a shot.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

local function dump(tag)
  local hp = {}
  for c = 0, 13 do
    hp[#hp + 1] = string.format("%d", H.readWord(0x1609 + 37 * c))
  end
  H.log(string.format("[%s] f%d $1F64=%04X map=%d world=%s $19=%02X "
    .. "evPC=%02X%02X%02X bright=%d battHP=%d/%d/%d/%d fieldHP=%s $0069=%d",
    tag, H.frame, H.readWord(0x1f64), map(), tostring(H.worldMode()),
    H.readByte(0x0019), H.readByte(0x00e7), H.readByte(0x00e6),
    H.readByte(0x00e5), emu.getState()["ppu.screenBrightness"] or 0,
    H.readWord(0x3bf4), H.readWord(0x3bf6), H.readWord(0x3bf8),
    H.readWord(0x3bfa), table.concat(hp, ","), sw(0x0069)))
end

local fights, battN = 0, 0

H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/minecart_entry.mss.lua"),
  H.waitFrames(150),
  H.call(function() dump("boot") end),

  -- into the cutscene
  (function() local ph = 0
    return H.driveUntil(function() return sw(0x02BC) == 1 end, 20000, {
      H.call(function() ph = (ph + 1) % 8
        H.setPad(ph < 4 and { "a", "up" } or { "up" })
      end) }, "A into CID -> cutscene TRAIN")
  end)(),
  H.call(function() dump("cutscene-start") end),

  -- ride until the sixth fight is over, write-clearing as gen_n128 did
  (function() local ph = 0
    return H.driveUntil(function() return fights >= 6 and battN == 0 end, 20000, {
      H.call(function()
        ph = (ph + 1) % 8
        battN = H.battleLoadStarted() and battN + 1 or 0
        if battN == 3 then
          fights = fights + 1
          local w = H.formationWords()
          H.log(string.format("[fight %d] f%d %04X %04X %04X %04X %04X %04X",
            fights, H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
          dump("fight" .. fights .. "-start")
        end
        if battN >= 3 then
          killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
        end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "six fights")
  end)(),
  H.call(function() dump("after-fight-6"); H.screenshot("train_after6") end),

  -- then sample the stall for 6000 frames, screenshotting periodically
  (function() local n = 0
    return H.driveUntil(function() return n >= 6000 or sw(0x0069) == 1 end, 7000, {
      H.call(function()
        n = n + 1
        if n % 600 == 0 then
          dump("stall+" .. n)
          H.screenshot("train_stall_" .. n)
        end
        H.setPad({})            -- hands OFF: no A mashing during the sample
      end),
    }, "sample the stall")
  end)(),
  H.call(function() dump("end"); H.screenshot("train_stall_end") end),
})
