-- gen_n128.lua -- the minecart platform (map 272, CID at {9,51}) -> A ->
-- `cutscene TRAIN` -> the minecart's six forced battles, NUMBER 128 among
-- them -> the Kefka explosion on map 240 -> control with $0069=1 ->
-- parked ON the escape map's save point {58,7} (boundary E).  Generates
-- n128_won.mss.

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1

-- The ride issues its six battles from the world module's train engine,
-- writing the event-battle id straight to $0011E0; nothing in the event
-- disassembly names them, so no entry-point fixture can be parked in
-- front of the boss.  This step instead records every battle the ride
-- produces and asserts against that record: six fights seen, one of them
-- $010B (NUMBER 128) with both blades.

local H = dofile("tools/tests/lib/ot6.lua")
local L = H.newSeedLadder("minecart ride")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
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

-- a bare step list cannot be spliced into a step list; H.cond with an
-- always-true predicate is the library's public way to wrap one into a step
local function seq(steps) return H.cond(function() return true end, steps) end

-- What the party is carrying and what it has left to spend, read at the
-- start of every fight on the ride.  There is no field access between the
-- six fights, so the bag and the MP pools are a fixed supply and this is
-- the record of how fast the ride burns them.
local BATTINV = 0x2686                 -- battle inventory, 5 bytes/entry
local function bagCount(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id then
      return H.readByte(BATTINV + i * 5 + 3)
    end
  end
  return 0
end
local function supplyReport(tag)
  local who = {}
  for e = 0, 3 do
    local maxhp = H.readWord(0x3C1C + e * 2)
    if maxhp > 0 then
      who[#who + 1] = string.format("e%d char%d %d/%d hp %d/%d mp bp%d",
        e, H.readByte(0x3ED8 + e * 2), H.readWord(0x3BF4 + e * 2), maxhp,
        H.readWord(0x3C08 + e * 2), H.readWord(0x3C30 + e * 2),
        H.readByte(0x3E9C + e * 2))
    end
  end
  H.log(string.format("[supply %s] tonic=%d potion=%d fenix=%d | %s",
    tag, bagCount(0xE8), bagCount(0xE9), bagCount(0xF0),
    table.concat(who, " | ")))
end

-- What each attempt's boss fight looked like, so a lost ladder reports a
-- measurement instead of "got false, want true".  One row per attempt: what
-- the party brought into fight 6 and how far down the body got.
local fight6 = {}
local function fight6Row()
  local r = fight6[#fight6]
  if r == nil then return "fight 6 never reached" end
  return string.format("in %d/%d/%d hp, %d tonic %d potion %d fenix; "
    .. "body $010B %d/3276 sh%d at its lowest",
    r.hp[1], r.hp[2], r.hp[3], r.tonic, r.potion, r.fenix, r.low, r.lowSh)
end

local fights, rideStart = {}, nil
local function rideDriver(pred, lostRef, maxFrames, what)
  local ph, hb, battN, wipeN = 0, 0, 0, 0

  -- healer is SABIN on both drivers: his Pummel is bludgeoning against a
  -- pierce-weak body and slash-weak blades, so his turn is the one to
  -- spend on healing.  EDGAR's boosted AutoCrossbow (500-750 damage, up
  -- to three shields per action) is the one never to spend.  The Roader
  -- threshold is 95% (the five Roader fights are the only chance to
  -- heal, with no field access between the six); the boss threshold 85%.
  local SABIN, LOCKE, BOLT = 0x05, 0x01, 0x02
  local Ftrash = H.newFightDriver("n128 trash", { tactical = true,
    boost = true, bank = 1, items = true, healer = SABIN,
    healPercent = 95, cadence = 12 })
  -- Fight 6 steers every single-target confirm onto the body through the
  -- library's own focus machine.

  -- LOCKE's Bolt is on this driver and not on the trash one: Ramuh's
  -- grant is spent on the fight whose element row it was chosen for.
  -- boost=false because the point is the chip rather than the damage: a
  -- boosted cast is charged the higher tier's MP, and one landed hit
  -- chips one axis whatever tier it was, so the cheap tier buys more
  -- chips out of the same pool against a body carrying seven shields.
  local Fboss = H.newFightDriver("n128 boss", { tactical = true,
    boost = true, bank = 1, items = true, healer = SABIN,
    healPercent = 85, cadence = 12,
    magic = { [LOCKE] = { spell = BOLT, boost = false } },
    focus = { { slot = 0, mask = 0x01 } } })
  return H.driveUntil(function() return lostRef.lost or pred() end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 600 == 0 then
        local mhp = {}
        if H.battleLoadStarted() then
          for m = 0, 5 do
            local id = H.readWord(0x57C0 + m * 2)
            if id ~= 0xFFFF and id ~= 0 then
              mhp[#mhp + 1] = string.format("%04X:%d/sh%d", id,
                H.readWord(0x3BFC + m * 2), H.readByte(0x3E40 + m * 2))
            end
          end
        end
        H.log(string.format("ride f%d map=%d (%d,%d) ctl=%s batt=%s "
          .. "fights=%d party %d/%d/%d | %s", H.frame, map(),
          H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          tostring(H.battleLoadStarted()), #fights,
          H.readWord(0x3BF4), H.readWord(0x3BF6), H.readWord(0x3BF8),
          table.concat(mhp, " ")))
      end
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN == 3 then
        local w = H.formationWords()
        fights[#fights + 1] = w
        H.log(string.format("[ride battle %d] f%d formation = "
          .. "%04X %04X %04X %04X %04X %04X", #fights, H.frame,
          w[1], w[2], w[3], w[4], w[5], w[6]))
        supplyReport("fight " .. #fights .. " start")
        if #fights == 6 then
          H.assertEq(w[1], 0x010b,
            "fight 6 puts NUMBER 128 in monster slot 0, which is the slot "
            .. "Fboss's focus list steers to (mask $01)")
          fight6[#fight6 + 1] = {
            hp = { H.readWord(0x3BF4), H.readWord(0x3BF6), H.readWord(0x3BF8) },
            tonic = bagCount(0xE8), potion = bagCount(0xE9),
            fenix = bagCount(0xF0),
            low = H.readWord(0x3BFC), lowSh = H.readByte(0x3E40),
          }
        end
      end
      if battN >= 3 then
        -- a wipe never sets $0069; catch it here so the ladder can act.
        -- Debounced 120 frames: the HP table can read zero for a moment
        -- while a battle deals the party in.
        local alive = false
        for e = 0, 3 do
          if H.readWord(0x3BF4 + e * 2) > 0 then alive = true end
        end
        wipeN = (not alive) and wipeN + 1 or 0
        if wipeN >= 120 and not lostRef.lost then
          lostRef.lost = true
          H.log(string.format("[ride] PARTY WIPED in fight %d at f%d",
            #fights, H.frame))
        end
        local F = (#fights >= 6) and Fboss or Ftrash
        if #fights >= 6 and fight6[#fight6] then
          local r, hp = fight6[#fight6], H.readWord(0x3BFC)
          if hp < r.low then r.low, r.lowSh = hp, H.readByte(0x3E40) end
        end
        F.frame()
        return
      end
      if #fights > 0 and map() == 272
         and H.fieldX() == 3 and H.fieldY() == 55 and not lostRef.lost then
        lostRef.lost = true
        H.log(string.format("[ride] LOSS: the Game Over Continue landed on "
          .. "the boot save tile after fight %d, f%d", #fights, H.frame))
      end
      if battN > 0 then Ftrash.idle(); Fboss.idle(); H.setPad({}); return end
      Ftrash.idle(); Fboss.idle()
      H.setPad(ph < 4 and { "a" } or {})
    end),
  }, what)
end

local rideBlob, rideWon = nil, false

-- One attempt, flat (driveUntil bodies replay latched state, so every
-- attempt builds fresh closures).  Attempt 1 runs in place; later attempts
-- reload the prepared CID entry point and shift the RNG phase.  The outcome
-- is the ride's own terminator: control on map 240 with $0069 set.
local function rideAttempt(n)
  local loadReq
  local lostRef = { lost = false }
  return H.cond(function() return rideWon end, {}, {
    H.logStep(function()
      return string.format("minecart ride attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function()
        fights = {}                    -- a lost attempt's record is void
        loadReq = H.requestLoadState(rideBlob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "ride entry point reload") end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(map(), 272, "reloaded onto map 272")
        H.assertEq(H.fieldX() == 9 and H.fieldY() == 52, true,
          "reloaded beside CID")
      end),
    }) or seq({}),
    L.spread(n),                        -- spread the battle RNG phase
    -- A into CID -> _cc8022 -> ... -> `cutscene TRAIN`
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
    -- ride it out; terminates early on a detected wipe so the ladder can
    -- reload instead of timing out
    rideDriver(function()
      return map() == 240 and sw(0x0069) == 1 and settled()
    end, lostRef, 120000, "the minecart ride -> map 240 with $0069"),
    H.call(function()
      H.setPad({})
      if not lostRef.lost and map() == 240 and sw(0x0069) == 1 then
        rideWon = true
        H.log(string.format("minecart ride SURVIVED on attempt %d, f%d "
          .. "(%d fights fought)", n, H.frame, #fights))
      else
        H.log(string.format("attempt %d LOST (wipe in fight %d), f%d -- %s",
          n, #fights, H.frame, fight6Row()))
      end
    end),
  })
end

H.run({ maxFrames = 400000 }, {
  -- checkpoint boot: cold Continue into the 272 save tile {3,55}, entry
  -- contract, then walk back beside CID and face him.
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  -- Soft landing wait: a wrong-boundary checkpoint should fail via the entry
  -- contract naming the wrong map rather than via a timeout here.
  H.waitUntilSoft(function()
    return map() == 272 and H.tileAligned() and bright() >= 15
  end, 3000, "landed_at_d"),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("minecart-platform-v1")
    H.log(partyReport("minecart-platform-v1 entry"))
  end),
  H.navTo(9, 52, { maxFrames = 9000, playBattles = "flee" }),
  -- face CID: his object occupies (9,51), so an UP press only turns
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(20),
  H.call(function()
    H.assertEq(map(), 272, "booted on map 272")
    H.assertEq(H.fieldX(), 9, "boot x")
    H.assertEq(H.fieldY(), 52, "boot y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0, "booted facing CID")
    H.assertEq(sw(0x02BC), 0, "$02BC CLEAR at boot")
    H.assertEq(sw(0x0069), 0, "$0069 CLEAR at boot")
    local cur, n, who = H.readByte(0x1A6D), 0, {}
    for c = 0, 13 do
      local b = H.readByte(0x1850 + c)
      if b ~= 0 and (b & 0x07) == cur then n = n + 1; who[c] = true end
    end
    H.assertEq(n, 3, "the minecart is ridden by THREE characters")
    H.assertEq(who[0x01] == true, true, "and they are LOCKE...")
    H.assertEq(who[0x05] == true, true, "...SABIN (the bludgeon slot)...")
    H.assertEq(who[0x04] == true, true, "...and EDGAR (pierce + Tools)")
    H.log(partyReport("minecart_entry"))
  end),

  -- Best-effort, mask-checked kits (the gen_ifrit_magicite pattern);
  -- LOCKE's left hand is a second weapon under the Genji Glove -- the
  -- body's row is pierce, so a dagger offhand chips it twice per
  -- boosted Fight.
  (function()
    local KITS = {
      { 1, "LOCKE",  { { 0, 0x0F }, { 1, 0x00 }, { 1, 0x01 }, { 1, 0x02 },
                       { 2, 0x69 }, { 3, 0x84 } } },
      { 4, "EDGAR",  { { 0, 0x0A }, { 0, 0x0B }, { 0, 0x0F },
                       { 1, 0x5A }, { 2, 0x69 }, { 3, 0x84 } } },
      { 5, "SABIN",  { { 0, 0x53 }, { 1, 0x5A }, { 2, 0x73 }, { 3, 0x86 } } },
    }
    local steps = {}
    for _, kit in ipairs(KITS) do
      local char, name, pairs_ = kit[1], kit[2], kit[3]
      for _, p in ipairs(pairs_) do
        local slot, item = p[1], p[2]
        local tag = string.format("%s minecart kit slot %d", name, slot)
        steps[#steps + 1] = H.cond(
          function() return H.invSlotOf(item) ~= nil end,
          { H.equipLoadout(char, { { slot, item } }, { tag = tag }) },
          { H.logStep(string.format(
              "%s: $%02X not in this lineage's bag; keeping current gear",
              tag, item)) })
      end
    end
    return H.cond(function() return true end, steps)
  end)(),

  --   EDGAR AutoCrossbow   500-750, and 3 shields off the body in one action
  --   LOCKE ThunderBlade   ~200 and a shield (the blade is LIGHTNING, which
  --                        is the body's own element row, so his ordinary
  --                        Fight already chips)
  --   SABIN Pummel         ~190 and no shield at all: Pummel is bludgeoning,
  --                        the body is pierce-weak and the blades are
  --                        slash-weak, so his kit chips nothing here

  -- So:

  H.equipEsper(1, 0x11, { tag = "KIRIN -> SABIN (Cure)" }),
  H.equipEsper(2, 0x00, { tag = "RAMUH -> LOCKE (Bolt)" }),
  H.equipEsper(0, 0x03, { tag = "SIREN -> EDGAR (+4 speed)" }),
  H.call(function()
    local want = { [0x05] = 0x11, [0x01] = 0x00, [0x04] = 0x03 }
    local names = { [0x05] = "SABIN/KIRIN", [0x01] = "LOCKE/RAMUH",
                    [0x04] = "EDGAR/SIREN" }
    for c, esper in pairs(want) do
      local worn = H.readByte(0x1600 + 37 * c + 0x1E)
      H.log(string.format("[prep] char %d wears esper %02X", c, worn))
      H.assertEq(worn, esper, names[c] .. " is worn")
    end
  end),
  H.setRows({ [0x01] = true, [0x04] = true, [0x05] = true },
            { tag = "back row for the ride" }),
  H.fieldCare({ tag = "care before the ride", threshold = 0.95 }),
  H.navTo(9, 52, { maxFrames = 9000, playBattles = "flee" }),
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(20),
  H.call(function()
    H.assertEq(H.fieldX() == 9 and H.fieldY() == 52, true,
      "back beside CID, prepared")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0, "facing CID again")
    H.log(partyReport("ride entry point, prepared"))
  end),
  -- capture the prepared entry point as the retry ladder's reload blob
  (function()
    local req
    return seq({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "ride retry blob")
        rideBlob = req.blob
        H.log(string.format("retry blob captured: %d bytes", #rideBlob))
      end),
    })
  end)(),

  -- 2. the ride, on the phase-spread retry ladder
  L.watch(),
  rideAttempt(1),
  rideAttempt(2),
  rideAttempt(3),
  L.report(),
  H.call(function()
    for i, r in ipairs(fight6) do
      H.log(string.format("[fight 6] attempt %d: party %d/%d/%d hp, "
        .. "%d tonic %d potion %d fenix, body $010B down to %d/3276 sh%d",
        i, r.hp[1], r.hp[2], r.hp[3], r.tonic, r.potion, r.fenix,
        r.low, r.lowSh))
    end
    H.assertEq(rideWon, true,
      "the minecart ride survived within 3 attempts (six real "
      .. "fights, the library fighter) -- last attempt reached " .. fight6Row())
  end),
  H.waitFrames(90),

  H.call(function()
    H.log(string.format("[ride] control on map 240 at frame %d "
      .. "(%d frames from `cutscene TRAIN`), %d battles fought",
      H.frame, H.frame - rideStart, #fights))
    for i, w in ipairs(fights) do
      H.log(string.format("  fight %d: %04X %04X %04X %04X %04X %04X", i,
        w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    -- Positive controls.  A ride that fought nothing would reach
    -- map 240 the same way, so the record is what is asserted.
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
    H.log(string.format("[after the ride] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.log(partyReport("after the ride"))
    H.screenshot("n128_after_ride")
  end),

  -- 3. park on boundary E: the escape map's save point {58,7}, revealed
  --    by $06AE.  The last step is a held RIGHT from (57,7).  A save
  --    tile flickers hasControl() (the SavePoint re-entry), so arrival
  --    is judged on position, $01BF and alignment.
  H.navTo(57, 7, { maxFrames = 15000, playBattles = "flee" }),
  (function() local calm = 0
    return H.driveUntil(function()
      calm = (H.fieldX() == 58 and H.fieldY() == 7 and sw(0x01BF) == 1
              and H.tileAligned() and not H.dialogWaiting()
              and not H.battleLoadStarted()) and calm + 1 or 0
      return calm >= 8
    end, 9000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        if H.dialogWaiting() then H.setPad({ "a" }); return end
        if H.fieldX() == 58 and H.fieldY() == 7 then H.setPad({}); return end
        H.setPad({ right = true })
      end),
    }, "onto the save tile 240 (58,7)")
  end)(),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the $06AE-revealed save point works")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch took")
    H.assertExitContractPreSave("vector-escape-v1")
    H.log(string.format("[n128_won] f%d map=%d (%d,%d) -- ON boundary E",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.log(partyReport("n128_won"))
    H.screenshot("n128_won")
  end),
  H.saveState("n128_won.mss"),
  -- Reload-verified.  The party is parked on a save tile, where
  -- hasControl() flickers (the SavePoint re-entry), so the reload is
  -- judged the way the park itself was: position, latch and alignment,
  -- not the control flag.
  (function()
    local saveReq, loadReq
    return seq({
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "generated-state verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "generated-state verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(map(), 240, "reload: still on map 240")
        H.assertEq(H.fieldX() == 58 and H.fieldY() == 7, true,
          "reload: still on the save tile")
        H.assertEq(H.tileAligned(), true, "reload: at rest on the tile")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.assertEq(sw(0x0069), 1, "reload: $0069 still SET -- the win held")
        H.log("generated-state verify: the reload stayed calm -- n128_won verified")
      end),
    })
  end)(),
  H.call(function()
    census("n128_won", {
      { 58, 7, "the save point revealed by $06AE" },
      { 52, 40, "the Setzer reunion trigger _cc817f" },
    })
  end),
  H.logStep(function()
    return string.format("n128_won generated at frame %d -- map 240 (%d,%d), "
      .. "$0069=1 after %d fights on the minecart", H.frame,
      H.fieldX(), H.fieldY(), #fights)
  end),
})
