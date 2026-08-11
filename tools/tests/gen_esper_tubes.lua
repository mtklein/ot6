-- gen_esper_tubes.lua -- v0.6 leg 10, the leg OUT of boundary C (#25):
-- cold battery Continue from the tracked n024-doorstep-save-v1 anchor (the
-- NEW #10 save point, map 273 {26,53}, slot 3), the boundary's ENTRY
-- CONTRACT asserted as the first real act, two steps to the 024 doorstep
-- -> battle 72 -> the {25,50} door -> map 274, the esper tube room ->
-- parked at {10,10} FACING UP, one UP-step-plus-A-hold from the Cid/Kefka
-- set piece.  Mints n024_won and esper_tubes_doorstep.
--
-- ANCHORED MINT (frontier_graph.py: anchor="n024-doorstep-save-v1" on
-- BOTH of this script's states -- one script, one boot, two mints, so the
-- second state cannot ride a predecessor edge the boot never uses).  The
-- leg used to boot n024_doorstep.mss; that state stays minted as B->C's
-- terminal, and the cold Continue replays its last two steps from the
-- anchor instead (the "C + 2 steps" hybrid; boundary C is lettered in
-- tools/tests/frontier_graph.py).
--
-- BATTLE 72 (_cc79ed, event_main.asm:95385) is `battle 72 / call _ca5ea9 /
-- hide_obj NPC_1 / sort_obj / switch $0649=0` -- no `if_b_switch` gate at
-- all, and $0649 going to 0 is the receipt (recon probe 5).  Measured
-- formation at the doorstep: `010A FFFF FFFF FFFF FFFF FFFF` -- Number 024
-- alone, as decoded.
--
-- THE FIGHT IS PLAYED, NOT KILL-BITTED (issue #75).  NUMBER 024 is the
-- specimen guard (bosses-wob.md section 14): 7 shields, a ROTATING
-- elemental wall (WallChange), and the fixed chip classes are slashing +
-- piercing -- the doc's own "handhold while the wall spins", which is
-- exactly what the library fighter swings: boosted Fights (slashing) and
-- EDGAR's AutoCrossbow (piercing).  The drive is H.newFightDriver
-- (tactical + boost bank + real Item heals/revival, the configuration
-- that has now beaten VARGAS, battle 70 and the brokendeath guard), after
-- the player's own prep -- H.equipOptimum and H.fieldCare -- because the
-- July-cut anchor delivers the party hurt and LOCKE/CELES bare-handed
-- (the Vector remove_equip; measured on the sibling anchored leg, and
-- the equip audit names both).  gen_tunnelarmr's phase-spread retry
-- ladder wraps the engagement: battle 72 is an event battle, a loss is
-- GAME OVER, and the RNG seed is the frame phase at battle init.
--
-- THE TUBE-ROOM TRIGGER IS FACING+BUTTON GATED, and this is the second
-- place in v0.6 where that is load bearing (the first was the Vector sneak
-- ledge; see gen_vector_sneak.lua for the $01B0-$01B7 decode).
--
--   ff6/src/event/event_trigger.asm:1216   make_event_trigger {10,9}, _cc7a60
--   ff6/src/event/event_main.asm:95456-95461
--       _cc7a60: if_any
--                        switch $01B0=0        ; NOT facing UP
--                        switch $01B4=0        ; A NOT held
--                        switch $0068=1        ; already done
--                        goto EventReturn
--
-- $01B0 and $01B4 are $1EB6 bits 0 and 4 -- "party is facing up" and "the
-- A button is down this frame" -- rewritten every event tick by
-- UpdateCtrlFlags (field/event.asm:5415-5433).  So the scene fires only
-- while the party STANDS on {10,9}, faces UP at the BIG_SWITCH NPC on
-- {10,8} (npc_prop.asm:12631) and HOLDS A.  A navTo can never do that: it
-- releases the pad between steps and never presses A on the open field
-- (ot6_field.lua:340-351).
--
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
-- ^ the persistent-SRAM layout this leg understands (issue #25).  run.sh
--   reads the marker line above and refuses -- BEFORE the emulator boots,
--   naming both strings -- any OT6_SRAM_ANCHOR whose manifest.json declares
--   a different persistent_layout.
--
-- The doorstep is banked ONE TILE SOUTH of the trigger, at {10,10} already
-- facing UP, and not on {10,9} itself.  Measured reason, sampled in this
-- run and logged: standing on {10,9} with A released, hasControl() held
-- for only 68 of 90 frames and eventRunning() for 22 -- _cc7a60 is
-- re-entered every frame the party stands there, takes its early
-- `goto EventReturn` because $01B4 is clear, and the event PC bouncing
-- into bank $CA makes hasControl() flicker forever.  No settle predicate
-- can hold on that tile.  gen_zozo3_clock hit the same trap on the clock
-- tile and solved it the same way.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
-- a bare step list cannot be spliced into a step list; H.cond with an
-- always-true predicate is the library's public way to wrap one into a step
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
-- (a tapInto helper used to sit here, DEFINED and never called -- the same
-- dead battle toolkit gen_tunnelarmr's and gen_n024_doorstep's conversions
-- deleted from their own files; its only battle handling was the kill-bit)

-- ------------------------- battle 72, played honestly (issue #75) --------
local N024 = 0x010A
local function eoff(m) return 8 + m * 2 end
local function mshields(m) return H.readByte(0x3E38 + eoff(m)) end
local function mticks(m)   return H.readByte(0x3E88 + eoff(m)) end
local function mhp(m)      return H.readWord(0x3BFC + m * 2) end
local function mspecies(m) return H.readWord(0x57C0 + m * 2) end

local fightBlob, fightWon = nil, false

-- One attempt, flat (driveUntil bodies replay latched state, so every
-- attempt builds fresh closures).  Attempt 1 runs in place -- the live
-- timeline IS the blob's timeline; later attempts reload the doorstep blob
-- and shift the RNG phase.  The outcome is decided on $0649: _cc79ed's
-- tail clears it after a win, while a loss rides the Annihilated screen
-- into GAME OVER and never touches it.
local function n024Attempt(n)
  local loadReq
  local NSLOT = nil
  local sawBreak, deathFrame, deathTicks = nil, nil, nil
  local hb, ph, giveUp = 0, 0, 0
  local F = H.newFightDriver("b72", { tactical = true, boost = true, bank = 3,
    items = true, healPercent = 60, cadence = 12 })
  return H.cond(function() return fightWon end, {}, {
    H.logStep(function()
      return string.format("battle 72 attempt %d (phase offset %d) at f%d",
        n, (n - 1) * 37, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(fightBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "doorstep reload") end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(map(), 273, "reloaded onto map 273")
        H.assertEq(H.fieldX() == 25 and H.fieldY() == 52, true,
          "reloaded at the (25,52) doorstep")
      end),
    }) or seq({}),
    H.waitFrames((n - 1) * 37),         -- vary the battle RNG seed
    -- A into NUMBER 024 -> battle 72.  Confirm the formation before
    -- fighting it: a win over the WRONG battle would look identical in
    -- the log without the assert.
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
      -- NO-STAGING CONTROL: the gauge seeds FULL from the authored table
      -- (bosses-wob.md 14: 7 shields), not pre-cleared by a rig
      H.assertEq(mshields(NSLOT), 7,
        "NUMBER 024 opens with his authored 7 shields")
      H.assertEq(mticks(NSLOT), 0, "NUMBER 024 is NOT pre-broken")
      H.log(string.format("[battle 72] n024 hp=%d sh=%d", mhp(NSLOT),
        mshields(NSLOT)))
      H.screenshot("n024_battle")
    end),
    H.waitFrames(90),
    -- the honest fight: the library fighter, gauges logged around it.  Its
    -- menu==0 branch pages battle text and the victory teardown, so this
    -- one drive carries the battle to the field (or through the
    -- Annihilated screen, on a loss).
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
        H.log(string.format("battle 72 WON HONESTLY on attempt %d, f%d "
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
  -- COLD BATTERY BOOT (issue #25): title -> Continue -> the sole valid
  -- slot (3) -> the NEW 273 save point, standing on the tile the anchor
  -- was saved on.
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  -- SOFT landing wait: a wrong-boundary anchor lands somewhere else, and
  -- the failure must be the entry contract NAMING the wrong map -- never a
  -- timeout here (leg-fixtures.md, "fails loudly, naming what differed").
  H.waitUntilSoft(function()
    return map() == 273 and H.tileAligned() and bright() >= 15
  end, 3000, "landed_at_c"),
  H.waitFrames(60),
  H.call(function()
    -- THE ENTRY CONTRACT (issue #25): declared once in lib/ot6_contract.lua
    -- under "n024-doorstep-save-v1" -- the same table the leg INTO C
    -- (gen_n024_doorstep) and the anchor mint (gen_n024_save_anchor)
    -- assert as their EXIT contract.  A stale or wrong anchor fails HERE
    -- by naming what differed.
    H.assertEntryContract("n024-doorstep-save-v1")
    H.log(partyReport("n024-doorstep-save-v1 entry"))
  end),

  -- the two steps back onto the 024 doorstep (§5's "C + 2 steps")
  H.navTo(25, 52, { maxFrames = 6000, honest = "flee" }),
  H.call(function()
    H.assertEq(map(), 273, "on map 273")
    H.assertEq(H.fieldX(), 25, "024 doorstep x")
    H.assertEq(H.fieldY(), 52, "024 doorstep y")
    H.assertEq(sw(0x0649), 1, "$0649 SET -- 024 has not been fought")
    H.log(partyReport("024 doorstep (walked from anchor C)"))
  end),

  -- 1. the player's prep, all through real menus: the July-cut anchor
  --    delivers LOCKE and CELES bare-handed and the party can arrive hurt
  --    (both measured on the sibling anchored legs) -- re-equip
  --    (Equip -> Optimum, a no-op for anyone armed) and top HP up from
  --    the bag BEFORE the retry blob, so every attempt replays a
  --    prepared party
  H.equipOptimum({ tag = "n024 kit" }),
  H.fieldCare({ tag = "care before battle 72", threshold = 0.95 }),
  H.navTo(25, 52, { maxFrames = 6000, honest = "flee" }),
  H.call(function()
    H.assertEq(H.fieldX() == 25 and H.fieldY() == 52, true,
      "back at the doorstep, armed and topped up")
    H.log(partyReport("024 doorstep, prepared"))
  end),
  -- capture the prepared doorstep as the retry ladder's reload blob
  (function()
    local req
    return seq({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "doorstep retry blob")
        fightBlob = req.blob
        H.log(string.format("retry blob captured: %d bytes", #fightBlob))
      end),
    })
  end)(),

  -- 2. battle 72, played honestly, on the phase-spread retry ladder
  n024Attempt(1),
  n024Attempt(2),
  n024Attempt(3),
  H.call(function()
    H.assertEq(fightWon, true,
      "battle 72 won honestly within 3 attempts (the library fighter: "
      .. "tactical + boost bank + real items)")
  end),
  -- ride the post-battle tail out to a settled field ($0649 already
  -- cleared; honest -- no battle can occur here)
  H.advanceStory(function() return sw(0x0649) == 0 and settled() end, 12000,
    { honest = true }),
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
  -- RELOAD-VERIFIED (gen_sabin_gau's pattern, a trap this program has paid
  -- for): capture-calm does NOT imply reload-calm, so reload the parked
  -- moment and require the consumer's boot to find it quiet.
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
  H.navTo(25, 50, { maxFrames = 9000, honest = "flee", arrive = function() return map() == 274 end }),
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
  H.navTo(10, 10, { maxFrames = 12000, honest = "flee" }),

  -- 3a. WHY THE DOORSTEP IS NOT ON {10,9}.  A first version of this leg
  --     tried to park ON the trigger tile and timed out: the terminator
  --     wants consecutive settled frames and settled() never held there.
  --     Measured below rather than assumed -- step up onto {10,9} with NO
  --     A held and sample control for 90 frames.  Expected (and this is
  --     the same trap gen_zozo3_clock hit on the clock tile): _cc7a60 is
  --     re-entered every frame the party stands on it, takes its early
  --     `goto EventReturn` because $01B4 is clear, and the event PC
  --     bouncing into bank $CA is enough to make eventRunning() -- and so
  --     hasControl() -- flicker forever.  Then step back off and mint from
  --     {10,10}, one UP-step-plus-A-hold from the scene.
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
  -- Step back off, then approach {10,10} FROM BELOW so the last step is an
  -- UP step and the party is already facing UP when it lands.  A separate
  -- "press up to turn" would not do: this engine turns and moves in the
  -- same frame when the destination is walkable (measured,
  -- probe_vector_step -- facing and pixel position both changed on frame 6
  -- of a held press), and {10,9} is walkable, so a facing press here walks
  -- straight back onto the trigger tile.  Every earlier face-an-NPC press
  -- in this chain was safe only because an NPC object occupied the
  -- destination and the step was refused.
  H.navTo(10, 11, { maxFrames = 6000, honest = "flee" }),   -- back off the trigger tile
  H.navTo(10, 10, { maxFrames = 6000, honest = "flee" }),   -- back onto the doorstep, facing UP
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
    H.assertEq(H.fieldX(), 10, "tube-room doorstep x -- one step below {10,9}")
    H.assertEq(H.fieldY(), 10, "tube-room doorstep y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0,
      "facing UP toward the trigger tile (EVENT_DIR 0 -- this is the $01B0 "
      .. "the trigger demands, already set)")
    H.assertEq(settled(), true, "the doorstep is QUIET")
    H.assertEq(sw(0x0068), 0, "$0068 CLEAR")
    H.assertEq(H.readByte(0x1A69) & 0x07, 0x07, "still RAMUH + IFRIT + SHIVA")
    H.log(string.format("[esper_tubes_doorstep] f%d map=%d (%d,%d) face=%d $1A69=%02X",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x087f + H.readWord(0x0803)), H.readByte(0x1A69)))
    H.log(partyReport("esper_tubes_doorstep"))
    H.screenshot("esper_tubes_doorstep")
  end),
  H.saveState("esper_tubes_doorstep.mss"),
  -- RELOAD-VERIFIED, and deliberately BEFORE the A-hold trigger check
  -- below, which consumes the doorstep by firing the scene -- after the
  -- reload the verify below runs from a state byte-equivalent to the mint.
  (function()
    local saveReq, loadReq
    return seq({
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "doorstep verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "doorstep verify: reload") end),
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
        H.log("esper_tubes_doorstep verify: the reload stayed calm")
      end),
    })
  end)(),

  -- 4. VERIFY, after the mint, that an A-HOLD really fires _cc7a60.  This
  --    is the assertion that a plain navTo could never satisfy, and it is
  --    the whole reason the doorstep is a tile-with-a-facing rather than a
  --    tile: a fixture that merely stands here proves nothing.
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
    return string.format("n024_won and esper_tubes_doorstep minted; "
      .. "doorstep is map 274 (10,10) facing UP, one UP-step-plus-A-hold "
      .. "from _cc7a60 (frame %d)", H.frame)
  end),
})
