-- gen_esper_tubes.lua -- cold battery Continue from the n024-entry-save-v1
-- checkpoint (map 273 {26,53}, slot 3), two steps to the 024 entry point,
-- battle 72, through the {25,50} door to map 274 (the esper tube room),
-- parked at {10,10} facing UP, one UP-step-plus-A-hold from the Cid/Kefka
-- set piece.  Generates n024_won.mss and esper_tubes_entry.mss.
--
-- The tube-room trigger at {10,9} fires only while the party faces UP and
-- holds A; navTo cannot do that (it releases the pad between steps and
-- never holds A on the open field), so the entry point is banked one tile
-- south at {10,10}, already facing UP.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh reads this marker and refuses, before boot, any
--   OT6_SRAM_CHECKPOINT whose manifest declares a different
--   persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")
-- The retry ladder's spread and its collision check: each attempt is held
-- until the game-time frame counter the battle seed is made of reaches
-- its own phase, and L.report() fails if two attempts drew one seed,
-- which would make this ladder one fight played twice.
local L = H.newSeedLadder("battle 72")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
-- H.cond with an always-true predicate wraps a list into a single step
-- (a bare list can't be spliced into a step list)
local function seq(steps) return H.cond(function() return true end, steps) end
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

-- ------------------ battle 72, played with real input --------------------
local N024 = 0x010A
local function eoff(m) return 8 + m * 2 end
local function mshields(m) return H.readByte(0x3E38 + eoff(m)) end
local function mticks(m)   return H.readByte(0x3E88 + eoff(m)) end
local function mhp(m)      return H.readWord(0x3BFC + m * 2) end
local function mspecies(m) return H.readWord(0x57C0 + m * 2) end

local fightBlob, fightWon = nil, false

-- One attempt, flat: driveUntil bodies replay latched state, so each
-- attempt builds fresh closures.  Attempt 1 runs in place; later attempts
-- reload the entry point blob and shift the RNG phase.  The outcome is
-- decided on $0649: a win clears it, a loss never touches it.
local function n024Attempt(n)
  local loadReq
  local NSLOT = nil
  local sawBreak, deathFrame, deathTicks = nil, nil, nil
  local hb, ph, giveUp = 0, 0, 0
  local F = H.newFightDriver("b72", { tactical = true, boost = true, bank = 3,
    items = true, healPercent = 60, cadence = 12 })
  return H.cond(function() return fightWon end, {}, {
    H.logStep(function()
      return string.format("battle 72 attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(fightBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "entry point reload") end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(map(), 273, "reloaded onto map 273")
        H.assertEq(H.fieldX() == 25 and H.fieldY() == 52, true,
          "reloaded at the (25,52) entry point")
      end),
    }) or seq({}),
    L.spread(n),                        -- spread the battle RNG phase
    -- A into NUMBER 024 -> battle 72.  Confirm the formation before
    -- fighting it: without the assert, a win over the wrong battle would
    -- look identical in the log.
    H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
      H.hold({ "a", "up" }), H.waitFrames(4), H.hold({ "up" }), H.waitFrames(4),
    }, "A into NUMBER 024 -> battle 72"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 900,
      "battle 72 active", 30),
    H.call(function()
      local w = H.formationWords()
      H.log(string.format("[battle 72] formation = %04X %04X %04X %04X %04X %04X",
        w[1], w[2], w[3], w[4], w[5], w[6]))
      H.assertEq(H.formationHas({ [N024] = true }), true,
        "battle 72 is NUMBER 024 $010A -- fighting the right battle")
      for m = 5, 0, -1 do
        if mspecies(m) == N024 then NSLOT = m end   -- lowest slot wins
      end
      H.assertEq(NSLOT ~= nil, true, "a NUMBER 024 slot resolved")
      -- no-staging control: the gauge seeds full (7 shields) rather than
      -- being pre-cleared
      H.assertEq(mshields(NSLOT), 7,
        "NUMBER 024 opens with his authored 7 shields")
      H.assertEq(mticks(NSLOT), 0, "NUMBER 024 is NOT pre-broken")
      H.log(string.format("[battle 72] n024 hp=%d sh=%d", mhp(NSLOT),
        mshields(NSLOT)))
      H.screenshot("n024_battle")
    end),
    H.waitFrames(90),
    -- the library fighter drives the fight; its menu==0 branch pages
    -- battle text and the victory teardown, carrying the battle to the
    -- field (or through the Annihilated screen, on a loss).
    H.driveUntil(function() return not H.battleLoadStarted() end, 90000, {
      H.call(function()
        hb = hb + 1
        if hb % 600 == 0 then
          H.log(string.format(
            "f%d n024 hp=%d sh=%d tk=%d | party %d/%d/%d/%d",
            H.frame, mhp(NSLOT), mshields(NSLOT), mticks(NSLOT),
            H.readWord(0x3BF4), H.readWord(0x3BF6),
            H.readWord(0x3BF8), H.readWord(0x3BFA)))
        end
        if not sawBreak and mshields(NSLOT) == 0 and mticks(NSLOT) ~= 0 then
          sawBreak = H.frame
          H.log(string.format("NUMBER 024 BROKEN at f%d: shields 0, timer %d "
            .. "-- seven real chips did this", H.frame, mticks(NSLOT)))
        end
        if not deathFrame and mhp(NSLOT) == 0 then
          deathFrame, deathTicks = H.frame, mticks(NSLOT)
          H.log(string.format("NUMBER 024 hp hit 0 at f%d (broken timer %d)",
            deathFrame, deathTicks))
        end
        F.frame()
      end),
    }, "battle 72, played (tactical + boost bank + real items)"),
    H.call(function() F.idle(); H.setPad({}) end),
    H.logStep(function()
      return string.format(
        "battle 72 torn down at f%d (break %s; kill %s); deciding",
        H.frame, sawBreak and ("f" .. sawBreak) or "not observed",
        deathFrame and ("f" .. deathFrame .. " tk=" .. deathTicks) or "not seen")
    end),
    -- won or lost?  Tap A while control is away (pages _ca5ea9's scene
    -- and, on a loss, the Annihilated screen); give the tail 3000 frames
    -- to clear $0649 before calling the attempt lost.
    H.driveUntil(function()
      giveUp = giveUp + 1
      return sw(0x0649) == 0 or giveUp >= 3000
    end, 3200, {
      H.call(function()
        ph = (ph + 1) % 8
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the _cc79ed tail clears $0649 (or the loss shows itself)"),
    H.call(function()
      H.setPad({})
      if sw(0x0649) == 0 then
        fightWon = true
        H.log(string.format("battle 72 WON on attempt %d, f%d "
          .. "(tactical + boost bank + items)", n, H.frame))
      else
        H.log(string.format("attempt %d LOST (no $0649 clear after teardown), f%d",
          n, H.frame))
      end
    end),
  })
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


H.run({ maxFrames = 300000 }, {
  -- Cold battery boot: title -> Continue -> the sole valid slot (3) -> the
  -- 273 save point, standing on the tile the checkpoint was saved on.
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  -- Soft landing wait: a wrong-boundary checkpoint lands somewhere else,
  -- and the failure should be the entry contract naming the wrong map
  -- rather than a timeout here.
  H.waitUntilSoft(function()
    return map() == 273 and H.tileAligned() and bright() >= 15
  end, 3000, "landed_at_c"),
  H.waitFrames(60),
  H.call(function()
    -- The entry contract: declared once in lib/ot6_contract.lua under
    -- "n024-entry-save-v1".  A stale or wrong checkpoint fails here by
    -- naming what differed.
    H.assertEntryContract("n024-entry-save-v1")
    H.log(partyReport("n024-entry-save-v1 entry"))
  end),

  -- the two steps back onto the 024 entry point (§5's "C + 2 steps")
  H.navTo(25, 52, { maxFrames = 6000, playBattles = "flee" }),
  H.call(function()
    H.assertEq(map(), 273, "on map 273")
    H.assertEq(H.fieldX(), 25, "024 entry point x")
    H.assertEq(H.fieldY(), 52, "024 entry point y")
    H.assertEq(sw(0x0649), 1, "$0649 SET -- 024 has not been fought")
    H.log(partyReport("024 entry point (walked from checkpoint C)"))
  end),

  -- 1. the player's prep: the checkpoint can deliver LOCKE and CELES
  --    bare-handed and the party hurt, so re-equip and top HP up before
  --    the retry blob, so every attempt replays a prepared party.
  -- Best-effort, mask-checked kits (the gen_ifrit_magicite pattern): each
  -- slot equips if the bag holds the item, repeated slot entries are a
  -- weakest-first preference ladder, and LOCKE's left hand is a SECOND
  -- WEAPON under his Genji Glove -- 024's row is slash|pierce, and the
  -- pair chips both axes twice per boosted Fight.
  (function()
    local KITS = {
      { 1, "LOCKE",  { { 0, 0x0F }, { 1, 0x00 }, { 1, 0x01 }, { 1, 0x02 },
                       { 2, 0x69 }, { 3, 0x84 } } },
      { 4, "EDGAR",  { { 0, 0x0A }, { 0, 0x0B }, { 0, 0x0F },
                       { 1, 0x5A }, { 2, 0x69 }, { 3, 0x84 } } },
      { 5, "SABIN",  { { 0, 0x53 }, { 1, 0x5A }, { 2, 0x73 }, { 3, 0x86 } } },
      { 6, "CELES",  { { 0, 0x0A }, { 2, 0x6A }, { 3, 0x84 } } },
    }
    local steps = {}
    for _, kit in ipairs(KITS) do
      local char, name, pairs_ = kit[1], kit[2], kit[3]
      for _, p in ipairs(pairs_) do
        local slot, item = p[1], p[2]
        local tag = string.format("%s Number-024 kit slot %d", name, slot)
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
  H.fieldCare({ tag = "care before battle 72", threshold = 0.95 }),
  H.navTo(25, 52, { maxFrames = 6000, playBattles = "flee" }),
  H.call(function()
    H.assertEq(H.fieldX() == 25 and H.fieldY() == 52, true,
      "back at the entry point, armed and topped up")
    H.log(partyReport("024 entry point, prepared"))
  end),
  -- capture the prepared entry point as the retry ladder's reload blob
  (function()
    local req
    return seq({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "entry point retry blob")
        fightBlob = req.blob
        H.log(string.format("retry blob captured: %d bytes", #fightBlob))
      end),
    })
  end)(),

  -- 2. battle 72, played with real input, on the phase-spread retry ladder
  L.watch(),
  n024Attempt(1),
  n024Attempt(2),
  n024Attempt(3),
  -- Before the verdict, not after: three attempts are evidence only if
  -- they were three different fights.
  L.report(),
  H.call(function()
    H.assertEq(fightWon, true,
      "battle 72 won within 3 attempts (the library fighter: "
      .. "tactical + boost bank + real items)")
  end),
  -- ride the post-battle tail out to a settled field ($0649 already
  -- cleared; playBattles=true, though no battle can occur here)
  H.advanceStory(function() return sw(0x0649) == 0 and settled() end, 12000,
    { playBattles = true }),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 273, "still on map 273 after battle 72")
    H.assertEq(sw(0x0649), 0, "$0649 CLEAR -- NUMBER 024 is gone")
    H.assertEq(H.bfsPath(25, 50) ~= nil, true,
      "the esper-tube door (25,50) is open now that {25,51} is clear")
    H.log(string.format("[n024_won] f%d map=%d (%d,%d) door plan=%d steps",
      H.frame, map(), H.fieldX(), H.fieldY(), #H.bfsPath(25, 50)))
    H.log(partyReport("n024_won"))
    H.screenshot("n024_won")
  end),
  H.saveState("n024_won.mss"),
  -- Reload-verified: a calm capture does not imply a calm reload, so
  -- reload the parked moment and require the consumer's boot to find it
  -- quiet.
  (function()
    local saveReq, loadReq
    return seq({
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "n024_won verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "n024_won verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(map(), 273, "reload: still on map 273")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.assertEq(H.dialogWaiting(), false, "reload: no dialog pending")
        H.assertEq(H.hasControl() and H.tileAligned(), true,
          "reload: controllable at rest")
        H.assertEq(sw(0x0649), 0, "reload: $0649 still CLEAR -- the win held")
        H.log("n024_won verify: the reload stayed calm")
      end),
    })
  end)(),

  -- 2. {25,50} -> map 274 {10,25}
  H.navTo(25, 50, { maxFrames = 9000, playBattles = "flee", arrive = function() return map() == 274 end }),
  H.waitUntil(function() return map() == 274 and settled() end, 6000,
    "map 274 control", 5),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 274, "the esper tube room is map 274")
    H.assertEq(H.fieldX(), 10, "274 landing x")
    H.assertEq(H.fieldY(), 25, "274 landing y")
    H.assertEq(sw(0x0068), 0, "$0068 CLEAR -- the Cid scene has not run")
    census("274", {
      { 10, 9, "the BIG_SWITCH trigger _cc7a60" },
      { 20, 13, "the lift trigger _cc7f43 ($0068-gated)" },
    })
    H.screenshot("esper_tubes_landing")
  end),

  -- 3. up to {10,10}, one step below the trigger tile.
  H.navTo(10, 10, { maxFrames = 12000, playBattles = "flee" }),

  -- 3a. Why the entry point is not on {10,9}: sample control while
  --     standing on the trigger tile for 90 frames.  _cc7a60 re-enters
  --     every frame the party stands there and takes its early exit, so
  --     hasControl() flickers continuously and no settle predicate can
  --     hold.  Then step back off and generate from {10,10}.
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(40),
  (function() local n, ctl, ev = 0, 0, 0
    return H.driveUntil(function() return n >= 90 end, 300, {
      H.call(function()
        n = n + 1
        if H.hasControl() then ctl = ctl + 1 end
        if H.eventRunning() then ev = ev + 1 end
        H.setPad({})
        if n == 90 then
          H.log(string.format("[on-trigger sample] at (%d,%d): hasControl %d/90 "
            .. "frames, eventRunning %d/90 -- this is why the fixture is "
            .. "banked one tile south", H.fieldX(), H.fieldY(), ctl, ev))
        end
      end),
    }, "sample control while standing on {10,9}")
  end)(),
  -- Approach {10,10} from below so the last step is an UP step and the
  -- party is already facing UP when it lands: this engine turns and moves
  -- in the same frame when the destination is walkable, so a separate
  -- "press up to turn" would walk back onto the trigger tile.
  H.navTo(10, 11, { maxFrames = 6000, playBattles = "flee" }),   -- back off the trigger tile
  H.navTo(10, 10, { maxFrames = 6000, playBattles = "flee" }),   -- back onto the entry point, facing UP
  (function() local calm = 0
    return H.driveUntil(function()
      local ok = H.fieldX() == 10 and H.fieldY() == 10 and settled()
             and H.readByte(0x087f + H.readWord(0x0803)) == 0
      calm = ok and calm + 1 or 0
      if calm >= 20 then H.setPad({}); return true end
      return false
    end, 3000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        H.setPad({})
      end) }, "twenty settled frames below the BIG_SWITCH tile")
  end)(),

  H.call(function()
    H.assertEq(map(), 274, "on map 274")
    H.assertEq(H.fieldX(), 10, "tube-room entry point x -- one step below {10,9}")
    H.assertEq(H.fieldY(), 10, "tube-room entry point y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0,
      "facing UP toward the trigger tile (EVENT_DIR 0 -- this is the $01B0 "
      .. "the trigger demands, already set)")
    H.assertEq(settled(), true, "the entry point is QUIET")
    H.assertEq(sw(0x0068), 0, "$0068 CLEAR")
    H.assertEq(H.readByte(0x1A69) & 0x07, 0x07, "still RAMUH + IFRIT + SHIVA")
    H.log(string.format("[esper_tubes_entry] f%d map=%d (%d,%d) face=%d $1A69=%02X",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x087f + H.readWord(0x0803)), H.readByte(0x1A69)))
    H.log(partyReport("esper_tubes_entry"))
    H.screenshot("esper_tubes_entry")
  end),
  H.saveState("esper_tubes_entry.mss"),
  -- Reload-verified, and deliberately before the A-hold trigger check
  -- below, which consumes the entry point by firing the scene.  After the
  -- reload, the verify below runs from a state byte-equivalent to the
  -- generated savestate.
  (function()
    local saveReq, loadReq
    return seq({
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "entry point verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "entry point verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(map(), 274, "reload: still on map 274")
        H.assertEq(H.fieldX() == 10 and H.fieldY() == 10, true,
          "reload: still parked at (10,10)")
        H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0,
          "reload: still facing UP")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.assertEq(H.hasControl() and H.tileAligned(), true,
          "reload: controllable at rest")
        H.assertEq(sw(0x0068), 0, "reload: $0068 still CLEAR")
        H.log("esper_tubes_entry verify: the reload stayed calm")
      end),
    })
  end)(),

  -- 4. Verify that an A-hold fires _cc7a60: the entry point is a tile
  --    plus a facing rather than just a tile, and a fixture that only
  --    stands here shows nothing.
  (function() local n = 0
    return H.driveUntil(function()
      return H.fieldY() == 9 and n > 120 and (not H.hasControl() or sw(0x0068) == 1)
    end, 4000, {
      H.call(function() n = n + 1
        H.setPad({ "a", "up" })
      end) }, "UP + A held steps onto {10,9} and fires _cc7a60")
  end)(),
  H.release(),
  H.call(function()
    H.assertEq(H.fieldY(), 9, "the verify walked onto the trigger tile")
    H.assertEq(H.hasControl(), false,
      "VERIFIED: holding A while facing UP on {10,9} took control -- "
      .. "_cc7a60 fired")
    H.log(string.format("[verify] scene running at f%d, map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("esper_tubes_verify")
  end),
  H.logStep(function()
    return string.format("n024_won and esper_tubes_entry generated; "
      .. "the entry point is map 274 (10,10) facing UP, one UP-step-plus-A-hold "
      .. "from _cc7a60 (frame %d)", H.frame)
  end),
})
