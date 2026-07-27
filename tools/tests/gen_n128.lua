-- gen_n128.lua -- v0.6 leg 13: minecart_doorstep (map 272 {9,52} facing
-- CID) -> A -> `cutscene TRAIN` -> the minecart's six forced battles,
-- NUMBER 128 among them -> the Kefka explosion on map 240 -> control with
-- $0069=1.  Mints n128_won.
--
-- WHY THIS LEG IS NOT AN EVENT WALK.  docs/design/vector-route-recon.md §4
-- and §8 hazard 2 flagged this as the beat most likely to eat the minting
-- pass, and the reason is that **`battle 73` appears nowhere in
-- `event_main.asm`**.  The ride is opcode `$ae`, `CUTSCENE::TRAIN`
-- (include/event_cmd.inc:707), issued at event_main.asm:96580; it runs in
-- the world module's train engine off a fixed 5-byte-per-item course
-- (world/train_script.asm:615-660), and the fights are issued by ASM
-- writing the event-battle id straight to $0011E0:
--     item 3  cmd $e0 -> TrainCmd_e0 (:829) -> event battle $29 = battle 41
--     item 9  cmd $e1 -> TrainCmd_e1 (:864) -> event battle $90 = battle 144
--     item 14 cmd $e0 -> battle 41
--     item 24 cmd $e1 -> battle 144
--     item 31 cmd $e1 -> battle 144
--     item 36 cmd $e2 -> TrainCmd_e2 (:899) -> event battle $49 = battle 73
--                        = NUMBER 128 $010b + Left Blade $0140 + RightBlade $013f
-- so nothing in the event disassembly names the boss and no doorstep
-- fixture can be parked in front of it.  This leg therefore RECORDS every
-- battle the ride throws instead: the driver below logs each formation on
-- its rising edge and the assertions afterwards are about that record --
-- six fights seen, and one of them $010b with both blades.  A quiet ride
-- would fail loudly rather than pass.
--
-- It also answers recon probe 4 (ride duration), which the recon could
-- only guess at because it never traced where the train counter $36 is
-- decremented: the frame count from `cutscene TRAIN` to control on map 240
-- is logged below.
--
-- ############################################################################
-- ## THIS GENERATOR DOES NOT MINT.  IT IS THE MEASUREMENT OF WHY.           ##
-- ############################################################################
--
-- Run against minecart_doorstep it rides the cutscene correctly and fights
-- all six battles in the scripted order --
--
--   1  f1281  0006 2A2A ...           Mag Roader           (battle 41)
--   2  f2450  0006 0006 ...           Mag Roader x2        (battle 144)
--   3  f3474  0006 2A2A ...           Mag Roader           (battle 41)
--   4  f5170  0006 0006 ...           Mag Roader x2        (battle 144)
--   5  f6546  0006 0006 ...           Mag Roader x2        (battle 144)
--   6  f7514  010B 0140 292A 013F     NUMBER 128 + blades  (battle 73)
--
-- -- which confirms the recon's decode of train_script.asm's course, and
-- then LOCKE DIES IN FIGHT 6.  Measured (probe_train_tail.lua), his battle
-- HP $3BF4 at the start of each fight:
--
--   fight 1: 501   fight 4: 385   fight 5: 261   fight 6: 151   -> 0
--
-- i.e. he enters the ride at full HP and the five Mag Roader fights take
-- ~70 HP each even though every one of them is kill-bitted within three
-- frames of `battleLoadStarted()`; the boss finishes what is left.  The
-- screenshot `shots/train_after6.png` is the sighting: Number 128, Left
-- Blade and RightBlade all standing, LOCKE alone on 151.
--
-- THE CAUSE IS UPSTREAM, IN v0.5, AND IT IS NOT A BALANCE PROBLEM TO FIX
-- HERE.  The party is one character because the fixture chain walked out of
-- Zozo two-handed.  `event_main.asm:26287` is
--
--     char_party LOCKE, 1 / char_party CELES, 1
--     party_menu 1, NO_RESET, {LOCKE, CELES}
--
-- -- a FOUR-SLOT party menu with Locke and Celes forced and the other two
-- slots free.  Measured at the post-Opera anchor, $1EDE=$76 / $1EDF=$88, so
-- CYAN, EDGAR, SABIN and GAU are all available to fill them; but $1850 reads
-- LOCKE=$C1, CELES=$49 and every other character $00, so nobody was added.
-- After the tube room takes Celes (`char_party CELES, 0`, :96154) that
-- leaves ONE.  docs/design/bosses-wob.md §13-§16 ("Locke, Celes + two") is
-- describing the intended band; the fixture chain is what is wrong.
--
-- WHAT WOULD UNBLOCK THIS.  The v0.5 leg that answers that party_menu has
-- to pick two more characters, and everything from there down -- including
-- the tracked 32 KiB anchor at tools/tests/anchors/post-opera-v1/, which is
-- minted from blackjack.mss by gen_post_opera_anchor.lua -- has to be
-- re-minted.  That is a v0.5 change, not a v0.6 one, so this generator is
-- left in the tree as the evidence rather than being made to pass by
-- weakening what it checks.
--
-- PARTY: LOCKE ALONE.  Leg 11 measured $1850 after the tube room -- one
-- character with a nonzero party nibble -- so every fight on this ride,
-- Number 128 included, is a solo fight.  Asserted at the doorstep so the
-- balance work has a measurement to stand on rather than
-- docs/design/bosses-wob.md §15's "three".
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Tap `dir` whenever the party has control, hands off while a scene owns
-- it, edge-A through dialogs.  Used to walk INTO a trigger whose scene then
-- takes over -- the tap keeps the party from sliding past the tile.
local function tapInto(dir, pred, maxFrames, what)
  local phase, n, ph, calm, hb = 0, 0, 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 120 == 0 then
        H.log(string.format("tapInto f%d (%d,%d) phase=%d ctl=%s algn=%s "
          .. "dlg=%s ev=%s $01B5=%d face=%d",
          H.frame, H.fieldX(), H.fieldY(), phase, tostring(H.hasControl()),
          tostring(H.tileAligned()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), sw(0x01B5),
          H.readByte(0x087f + H.readWord(0x0803))))
      end
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        -- STOP TAPPING once we are where we were going.  The terminator
        -- wants 16 consecutive calm frames on the target, and an eager tap
        -- walks straight off it before the count gets there: the first
        -- version of this rode the chute correctly to (10,45) and then
        -- tapped itself to (10,46) and timed out.
        if pred() then return end
        if settled() then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dir] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

local function census(tag, targets)
  local sx, sy = H.fieldX(), H.fieldY()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local seen, q, qi = { [(sy & ym) * 256 + (sx & xm)] = true }, { { sx, sy } }, 1
  while qi <= #q and qi <= 3000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = (x + v[1]) & xm, (y + v[2]) & ym
        local k = ny * 256 + nx
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format("[census %s] from (%d,%d) on map %d: %d tiles reachable",
    tag, sx, sy, map(), #q))
  for _, t in ipairs(targets or {}) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[census %s] -> (%d,%d) %-34s : %s", tag, t[1], t[2],
      t[3] or "", p and (#p .. " steps: " .. table.concat(p, " ")) or "NO PATH"))
  end
end


-- Ride the cutscene: kill-bit every battle, edge-A through every text, and
-- RECORD each fight's formation words on its rising edge so the assertions
-- afterwards are about what was actually fought.
local fights, battN, rideStart = {}, 0, nil
local function rideDriver(pred, maxFrames, what)
  local ph, hb = 0, 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 600 == 0 then
        H.log(string.format("ride f%d map=%d (%d,%d) world=%s ctl=%s batt=%s "
          .. "fights=%d", H.frame, map(), H.fieldX(), H.fieldY(),
          tostring(H.worldMode()), tostring(H.hasControl()),
          tostring(H.battleLoadStarted()), #fights))
      end
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN == 3 then
        local w = H.formationWords()
        fights[#fights + 1] = w
        H.log(string.format("[ride battle %d] f%d formation = "
          .. "%04X %04X %04X %04X %04X %04X", #fights, H.frame,
          w[1], w[2], w[3], w[4], w[5], w[6]))
      end
      if battN >= 3 then
        killBitAll()
        H.setPad(ph < 4 and { "a" } or {})
        return
      end
      if battN > 0 then H.setPad({}); return end
      -- outside battle: advance any text, otherwise hands off.  The ride
      -- is on rails; a held direction would only fight the engine.
      H.setPad(ph < 4 and { "a" } or {})
    end),
  }, what)
end

H.run({ maxFrames = 100000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/minecart_doorstep.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 272, "booted on map 272")
    H.assertEq(H.fieldX(), 9, "boot x")
    H.assertEq(H.fieldY(), 52, "boot y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0, "booted facing CID")
    H.assertEq(sw(0x02BC), 0, "$02BC CLEAR at boot")
    H.assertEq(sw(0x0069), 0, "$0069 CLEAR at boot")
    local cur, n = H.readByte(0x1A6D), 0
    for c = 0, 13 do
      local b = H.readByte(0x1850 + c)
      if b ~= 0 and (b & 0x07) == cur then n = n + 1 end
    end
    H.assertEq(n, 1, "the minecart is ridden by ONE character")
    H.assertEq(H.readByte(0x1850 + 1) & 0x07, cur, "and it is LOCKE")
    H.log(partyReport("minecart_doorstep"))
  end),

  -- 1. A into CID -> _cc8022 -> ... -> `cutscene TRAIN`
  (function() local ph = 0
    return H.driveUntil(function() return sw(0x02BC) == 1 end, 20000, {
      H.call(function() ph = (ph + 1) % 8
        if H.dialogWaiting() or not settled() then
          H.setPad(ph < 4 and { "a" } or {})
        else
          H.setPad(ph < 4 and { "a", "up" } or { "up" })
        end
      end) }, "A into CID -> $02BC -> cutscene TRAIN")
  end)(),
  H.call(function()
    rideStart = H.frame
    H.assertEq(sw(0x02BC), 1, "$02BC SET -- the minecart cutscene has begun")
    H.log(string.format("[ride] cutscene TRAIN entered at frame %d", H.frame))
    H.screenshot("minecart_ride")
  end),

  -- 2. ride it out
  rideDriver(function() return map() == 240 and sw(0x0069) == 1 and settled() end,
    80000, "the minecart ride -> map 240 with $0069"),
  H.waitFrames(90),

  H.call(function()
    H.log(string.format("[ride] control on map 240 at frame %d "
      .. "(%d frames from `cutscene TRAIN`), %d battles fought",
      H.frame, H.frame - rideStart, #fights))
    for i, w in ipairs(fights) do
      H.log(string.format("  fight %d: %04X %04X %04X %04X %04X %04X", i,
        w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    -- POSITIVE CONTROLS.  A ride that quietly fought nothing would reach
    -- map 240 just the same, so the record is what is asserted.
    H.assertEq(#fights >= 6, true,
      "the ride fought at least six battles (train_script.asm's six cmd bytes)")
    local sawN128 = false
    for _, w in ipairs(fights) do
      for _, v in ipairs(w) do if v == 0x010b then sawN128 = true end end
    end
    H.assertEq(sawN128, true,
      "NUMBER 128 $010b was fought -- the boss TrainCmd_e2 issues by writing "
      .. "$0011E0, which no grep of event_main.asm can find")
    H.assertEq(map(), 240, "the escape map is 240")
    H.assertEq(mapTitleHere(), "",
      "map 240 has no map title (map_prop byte 0 = 0) -- it is a second "
      .. "copy of VECTOR used for the escape")
    H.assertEq(sw(0x0069), 1, "$0069 SET -- 262 (28,9) now exits to 240, not 242")
    H.assertEq(sw(0x0666), 1, "$0666 SET")
    H.assertEq(sw(0x06AE), 1, "$06AE SET -- the save point on 240 (58,7) is revealed")
    H.assertEq(sw(0x006B), 0, "$006B CLEAR -- the Setzer reunion is still ahead")
    H.log(string.format("[n128_won] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.log(partyReport("n128_won"))
    H.screenshot("n128_won")
  end),
  H.saveState("n128_won.mss"),
  H.call(function()
    census("n128_won", {
      { 58, 7, "the save point revealed by $06AE" },
      { 52, 40, "the Setzer reunion trigger _cc817f" },
    })
  end),
  H.logStep(function()
    return string.format("n128_won minted at frame %d -- map 240 (%d,%d), "
      .. "$0069=1 after %d fights on the minecart", H.frame,
      H.fieldX(), H.fieldY(), #fights)
  end),
})
