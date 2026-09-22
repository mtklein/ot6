-- @suite savestate=camp_escaped slow
-- battle_statuses.lua -- the fight driver plans around a turn-denying
-- status (#187), measured in play rather than staged.
--
-- The exposure is the route's own: camp_escaped's world walk to the
-- Phantom Forest entrance (178,82) rolls CrassHoppr ($02F, special $4C =
-- Berserk, its script's SPECIAL on the first line) -- on this boot's
-- seed the first random lands Berserk on SHADOW as his window opens
-- (probe_statuses.lua, 2026-09-16: `[landed f610] Berserk on entity 1
-- INTO ITS OWN OPEN WINDOW: atb=0097 $3AA0=8F menu=01 st=01 actor=1`),
-- and the second on CYAN.  Before the fix the driver logged `actor=1
-- char=3 plan=fight` for the berserked SHADOW and lost the plan as
-- actor_changed when the engine took the window; a Stop or Sleep in a
-- list would have parked until the watchdog.
--
-- The two battles the direct walk happens to draw are not the exposure,
-- though.  SPECIAL is the monster's own roll inside a battle (a seed
-- sweep of the direct walk, build/sweeps/statuses-fix2, came away with
-- nothing on 2 of 8 seeds), and WHICH battles the walk draws is not
-- the seed's at all: the formation is picked by the save's encounter
-- counter (lib/ot6_field.lua, random-encounter pools), which every
-- regeneration of the chain moves.  The legs' pool is Stray Cat x3 (no
-- CrassHoppr) at 80/256 beside two CrassHoppr formations at 176/256, so
-- one fixture meets CrassHopprs every battle and the next can meet eight
-- Stray Cat packs in a row.  So the walk PACES the route's own leg
-- between (176,71) and (178,81) until a turn-denying status has actually
-- landed, and only then turns into the forest; and it bounds the pacing
-- by what can deny a turn, read from the ROM: an EXPOSURE battle is one
-- whose formation holds a species whose special (MonsterProp+31, decoded
-- as battle_main.asm @3318 does) inflicts a status H.turnDenied names
-- AND whose AI script can issue SPECIAL ($EF).  The walk stops after
-- EXPOSURES of those (the measured count, at EXPOSURES below), and caps
-- all battles at the most any encounter-counter state needs to deal
-- that many exposures from the legs' own pool (H.worstCaseEncounters),
-- so a walk that really cannot draw one still fails loudly at the same
-- assertion, and a fixture whose counter deals Stray Cats first still
-- gets its full count of exposures.
--
-- The walk is navTo's playBattles="tactical" (M.newFightDriver with the
-- walk options), the driver every route segment fights with.  The test
-- captures the driver's log through H.log and watches the four status
-- bytes on a startFrame callback (reads only), and asserts:
--   * Berserk landed on a party member at least once (the exposure; a
--     walk that no longer draws it fails here, loudly, rather than pass
--     on nothing);
--   * the driver said `[status] ... is under BERSERK` once per
--     (entity, battle) it landed on, with the cure verdict from the ROM
--     ("none in the bag": Remedy's STATUS2 byte is $48) -- counted over
--     the whole battle, which is the span the driver's own statusSaid
--     table is keyed by, and not over this watcher's window: the driver
--     and this watcher log on different callbacks within one frame, so
--     which side of the window boundary that one line falls on is not a
--     property of the driver at all (see the comment at the count);
--   * it never planned for that entity while the status stood (no
--     `actor=<e> char=.. plan=` line inside the window), never counted a
--     park or a pulse budget against it, and the recovery cap never fired;
--   * the walk arrived (map 132), so the fights ended in wins.
-- If a `[layout] ... preemptive` line occurs (#186, a 1/8 roll), the
-- free-round line must follow it in that battle before any top-up heal.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/camp_escaped.mss.lua"
local MENU, ACTOR = 0x7BCA, 0x62CA
local S1, S2, S3 = 0x3EE4, 0x3EE5, 0x3EF8

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end

-- the driver's log, captured line by line (H.log is the lib's M.log;
-- every driver line goes through it)
local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end

-- ---- what can deny a turn, read from the ROM --------------------------
-- A species' special attack is MonsterProp+31; battle_main.asm @3318
-- decodes its low six bits, and under $20 they are a status index
-- (GetBitPtr: status byte index>>3, bit index&7).  It denies a turn when
-- H.turnDenied names that status -- the same predicate the watch below
-- and the driver use -- and it is only ever used when the species' AI
-- script can issue SPECIAL ($EF): as a lone attack byte, or as one of
-- $F0's three picks, in either section.
local MONSTER_PROP = H.sym("MonsterProp") & 0x3FFFFF
local AI_PTRS = H.sym("AIScriptPtrs") & 0x3FFFFF
local AI_SCRIPT = H.sym("AIScript") & 0x3FFFFF
local SPECIAL = 0xEF
local function specialDenial(sp)
  local b = H.readRomByte(MONSTER_PROP + sp * 32 + 31) & 0x3F
  if b >= 0x20 then return nil end
  local st = { 0, 0, 0, 0 }
  st[(b >> 3) + 1] = 1 << (b & 7)
  return H.turnDenied({ s1 = st[1], s2 = st[2], s3 = st[3], s4 = st[4] })
end
local function usesSpecial(sp)
  local off = H.readRomWord(AI_PTRS + sp * 2)
  local i, section = 0, 0
  while section < 2 and i < H.AI_SCRIPT_MAX do
    local op = H.readRomByte(AI_SCRIPT + off + i)
    if op == SPECIAL then return true end
    if op == 0xF0 then
      for k = 1, 3 do
        if H.readRomByte(AI_SCRIPT + off + i + k) == SPECIAL then return true end
      end
    end
    if op == 0xFF then section = section + 1 end
    i = i + (H.AI_OP_LEN[op] or 1)
  end
  return false
end
-- the status species `sp` can deny a turn with, or nil
local denierMemo = {}
local function denier(sp)
  if denierMemo[sp] == nil then
    local d = sp < 0x180 and specialDenial(sp) or nil
    denierMemo[sp] = (d ~= nil and usesSpecial(sp)) and d or false
  end
  return denierMemo[sp] or nil
end

-- status watch: per battle, per entity, when a denying status landed
-- and cleared (in captured-line indices, so the plan lines can be
-- located between them)
local battles, cur = {}, nil
local last = {}
-- set the frame a turn-denying status first lands anywhere in the party:
-- the pacing legs below end on it
local landedAny = false
-- exposure battles fought so far (the formation held a denier as it
-- opened), and the world tile and group each battle fired on
local exposures = 0
local lastTile, lastGroup = nil, nil
local function observe()
  if not H.battleLoadStarted() then
    if cur then
      -- a status that ended with the battle closes its window here, at
      -- this battle's last line, not at the end of the run
      for e, o in pairs(cur.open) do
        o.to = #lines
        cur.landed[#cur.landed + 1] = o
        H.log(string.format("[test] battle %d: %s on entity %d ended with the battle (line %d)",
          cur.n, o.name, e, #lines))
      end
      cur.open = {}
      cur.to = #lines
      battles[#battles + 1] = cur; cur = nil; last = {}
    end
    -- the tile a coming encounter fires on (CheckBattleWorld reads the
    -- party's tile after the step) and the group it rolls from, read
    -- while the world tilemap is still in WRAM
    if H.worldMode() and H.worldAligned() then
      local x, y = H.worldX(), H.worldY()
      local k = y * 256 + x
      if k ~= lastTile then lastTile, lastGroup = k, H.worldEncounterGroup(x, y) end
    end
    return
  end
  if cur == nil then
    cur = { n = #battles + 1, landed = {}, open = {}, from = #lines, age = 0,
            tile = lastTile, group = lastGroup }
  end
  cur.age = cur.age + 1
  -- the formation as it opened (M.formationSpecies: $3F45's mask over the
  -- $57C0 words), classified once the battle has loaded it
  if cur.exposure == nil and cur.age >= 60 and #H.formationSpecies() > 0 then
    local names, deny = {}, nil
    for _, s in ipairs(H.formationSpecies()) do
      names[#names + 1] = string.format("%03X", s.species)
      deny = deny or denier(s.species)
    end
    cur.exposure = deny ~= nil
    if cur.exposure then exposures = exposures + 1 end
    H.log(string.format("[test] battle %d opened on (%d,%d) group %s, formation %d [%s]: %s",
      cur.n, (cur.tile or 0) & 0xFF, (cur.tile or 0) >> 8, tostring(cur.group),
      H.readWord(0x11E0) & 0x1FF, table.concat(names, " "),
      cur.exposure and string.format("an exposure (%s special; %d so far)", deny, exposures)
        or "no species here denies a turn"))
  end
  for e = 0, 3 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      local s1, s2, s3 = H.readByte(S1 + e * 2), H.readByte(S2 + e * 2), H.readByte(S3 + e * 2)
      local den = H.turnDenied({ s1 = s1, s2 = s2, s3 = s3 })
      local was = last[e]
      if den ~= nil and was == nil then
        landedAny = true
        cur.open[e] = { name = den, entity = e, at = #lines, frame = H.frame,
                        ownWindow = H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == e }
        H.log(string.format("[test] battle %d: %s landed on entity %d at f%d (line %d)%s",
          cur.n, den, e, H.frame, #lines, cur.open[e].ownWindow and " in its own window" or ""))
      elseif den == nil and was ~= nil then
        local o = cur.open[e]
        o.to = #lines
        cur.landed[#cur.landed + 1] = o
        cur.open[e] = nil
        H.log(string.format("[test] battle %d: %s off entity %d at f%d (line %d)",
          cur.n, was, e, H.frame, #lines))
      end
      last[e] = den
    end
  end
end

-- the route's own leg, paced: (176,71) and (178,81) are both on the line
-- camp_escaped's walker already plans through to the forest mouth (the
-- wnav trace logs both), so a lap between them is the same walk, walked
-- again, and draws from the same pool.
local PACE_A, PACE_B = { 176, 71 }, { 178, 81 }
-- How many exposure battles the walk gives a turn-denying special to
-- land in: measured per exposure battle -- see the note at the verdict.
local EXPOSURES = 16
-- the most battles any encounter-counter state needs to deal EXPOSURES
-- exposures from the legs' pool; set once the world is loaded
local battleBudget = nil
local function leftTheWorld() return not H.worldMode() end
local function fought() return #battles + (cur and 1 or 0) end
local function keepPacing()
  return not landedAny and exposures < EXPOSURES and fought() < battleBudget
end

-- The legs' pool and the budget it implies.  The groups are the ones a
-- lap's own paths roll from (H.worldPathGroups over A -> B -> A, the
-- walkers' BFS legs); a formation slot counts as an exposure only when
-- every formation it can deal holds a denier, in every one of those
-- groups.
local function budget()
  return H.call(function()
    local order = H.worldPathGroups({ PACE_A, PACE_B, PACE_A })
    H.assertEq(#order > 0, true, "the pacing legs roll random battles somewhere on their paths")
    local exposureSlot = { true, true, true, true }
    for _, g in ipairs(order) do
      local pool = H.encounterPool(g)
      for slot = 1, 4 do
        local e = pool[slot]
        local parts = {}
        for _, f in ipairs(e.formations) do
          local deny, names = nil, {}
          for _, sp in ipairs(f.species) do
            names[#names + 1] = string.format("%03X", sp)
            deny = deny or denier(sp)
          end
          if deny == nil then exposureSlot[slot] = false end
          parts[#parts + 1] = string.format("%d [%s]%s", f.id, table.concat(names, " "),
            deny and (" " .. deny) or "")
        end
        H.log(string.format("[test] leg pool: group %d slot %d (%d/256) %s", g, slot, e.odds,
          table.concat(parts, ", ")))
      end
    end
    local any = false
    for slot = 1, 4 do any = any or exposureSlot[slot] end
    H.assertEq(any, true, "the legs' pool deals a formation with a turn-denying species")
    local hist
    battleBudget, hist = H.worstCaseEncounters(function()
      local n = 0
      return function(slot)
        if exposureSlot[slot] then n = n + 1 end
        return n >= EXPOSURES
      end
    end)
    H.log(string.format("[test] budget: %d exposure battle(s), within at most %d battle(s) -- "
      .. "the most any encounter-counter state needs to deal that many from group(s) %s "
      .. "(%.1f%% of states need no more than %d)", EXPOSURES, battleBudget,
      table.concat(order, ","), 100 * H.encounterShare(hist, EXPOSURES), EXPOSURES))
  end)
end

-- The pacing legs.  A leg is taken or skipped WHOLE: the decision is made
-- at the leg's own start, never mid-battle.  Cutting a leg short inside a
-- battle would hand that battle to the next leg's freshly built fight
-- driver, whose statusSaid table starts empty -- it would say the
-- [status] line a second time for a status it had already reported, and
-- the count below would read 2 for one landing.  Each leg gets a fresh
-- worldNavTo, as it did when the legs were unrolled.
local function pacing()
  local leg, nav = 0, nil
  return {
    tick = function()
      while true do
        if nav == nil then
          if not keepPacing() then return "done" end
          leg = leg + 1
          local wp = (leg % 2 == 1) and PACE_B or PACE_A
          H.log(string.format("[test] leg %d: no turn-denying status yet after %d battle(s), "
            .. "%d of them exposures -- pacing to (%d,%d) to draw more",
            leg, fought(), exposures, wp[1], wp[2]))
          nav = H.worldNavTo(wp[1], wp[2], { maxFrames = 25000,
            playBattles = "tactical", arrive = leftTheWorld })
        end
        if nav:tick() == "frame" then return "frame" end
        nav = nil
      end
    end,
    reset = function() leg, nav = 0, nil end,
  }
end

H.run({ maxFrames = 200000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "camp_escaped boots on the World of Balance")
    emu.addEventCallback(function() observe() end, emu.eventType.startFrame)
  end),
  H.worldNavTo(PACE_A[1], PACE_A[2], { maxFrames = 25000,
    playBattles = "tactical", arrive = leftTheWorld }),
  -- the budget plans the legs' paths over the world tilemap in WRAM; a
  -- battle on A itself ends the walk the frame control returns, before
  -- the reload has rebuilt the map
  H.waitUntil(function() return H.worldSettled() end, 1500, "the world map settled", 5),
  budget(),
  pacing(),
  H.worldNavTo(178, 82, { maxFrames = 25000,
    playBattles = "tactical", arrive = leftTheWorld }),
  H.waitUntil(function() return mapIdx() == 132 end, 4000, "the forest loads", 5),
  H.call(function()
    -- close a battle still open in the watch (none expected on the field)
    if cur then cur.to = #lines; battles[#battles + 1] = cur; cur = nil end
    for _, b in ipairs(battles) do
      b.to = b.to or #lines
      for _, o in pairs(b.open) do o.to = b.to; b.landed[#b.landed + 1] = o end
    end
    local seen = 0
    for _, b in ipairs(battles) do
      -- The [status] line is counted over the WHOLE BATTLE, not over the
      -- watcher's own window.  The driver says it "the frame it lands"
      -- (lib/ot6.lua, statusSaid: once per battle per entity per status);
      -- this watcher runs on startFrame and so first SEES the bit on the
      -- next frame, by which time the driver has already logged the
      -- [status] line and whatever else that frame produced.  Whether
      -- the line falls inside [o.at, o.to] was therefore decided by how
      -- many other lines the driver happened to emit in between: on
      -- main's camp_escaped walk battle 1's [status] line was the last
      -- line before o.at (counted, verdict 1) and battle 2's was followed
      -- by one `battle f+300 ...` heartbeat (not counted, verdict 0) --
      -- the same run, the same driver, the same status, opposite
      -- verdicts.  The battle span is the boundary the property is
      -- actually stated against, and it does not move.
      local said = {}
      for i = b.from, b.to do
        local s = lines[i]
        local e, name = s:match("%[status%] f%+%d+ entity (%d+) char %d+ is under (%u+)")
        if e then
          local key = tonumber(e) .. ":" .. name
          said[key] = (said[key] or 0) + 1
        end
      end
      -- one verdict per (entity, status) the watch saw land, in landing
      -- order, so a status that landed twice in one battle is still one
      -- verdict -- statusSaid says the line once per battle, not once per
      -- landing
      local asked = {}
      for _, o in ipairs(b.landed) do
        local key = o.entity .. ":" .. o.name:upper()
        if not asked[key] then
          asked[key] = true
          H.assertEq(said[key] or 0, 1, string.format(
            "battle %d: one [status] line for the %s that landed on entity %d",
            b.n, o.name, o.entity))
        end
      end
      for _, o in ipairs(b.landed) do
        seen = seen + 1
        local e, name = o.entity, o.name
        local planLines, parkLines = 0, 0
        for i = o.at, o.to do
          local s = lines[i]
          if s:find("actor=" .. e .. " char=%d+ plan=") then planLines = planLines + 1 end
          if s:find("parked %d+ pulses") or s:find("consumed %d+ pulses")
             or s:find("FIGHT DRIVER STUCK") or s:find("recovery cap") then
            parkLines = parkLines + 1
          end
        end
        H.assertEq(planLines, 0, string.format("battle %d: no plan made for entity %d while under %s",
          b.n, e, name))
        H.assertEq(parkLines, 0, string.format("battle %d: no park, pulse-budget or recovery-cap line under %s",
          b.n, name))
        if name == "Berserk" then
          local cureSaid = false
          for i = b.from, b.to do
            if lines[i]:find("cure: none in the bag %(Remedy x%d+ carries no Berserk bit%)") then cureSaid = true end
          end
          H.assertEq(cureSaid, true, string.format("battle %d: the [status] line carries the ROM's cure verdict", b.n))
        end
      end
    end
    -- EXPOSURES is measured per exposure battle.  A lab copy of this walk
    -- that paced 20 battles whatever landed (build/lab/draw-budgets/
    -- statuses/measure_p/shift{0,7,13,21}.log) fought 48 exposure battles
    -- -- formation 57 (Beakor, Stray Cat, CrassHoppr x2) 32 times, 51
    -- (CrassHoppr x3) 16 -- and a Berserk landed in 22 of them (0.46; 15 of
    -- 32 and 7 of 16), shift 0 missing its first four in a row.  At that
    -- rate sixteen exposures all miss about once in 18,000 walks (0.54^16);
    -- at the rate's 95% lower bound (0.33), once in 600.  The battle budget
    -- above then makes sure every counter state gets its sixteen.
    H.assertEq(seen >= 1, true, string.format("a turn-denying status landed on the walk "
      .. "(the exposure; %d battle(s) fought, %d of them exposures, of a budget of %d "
      .. "exposures within %d battles)", #battles, exposures, EXPOSURES, battleBudget or -1))
    -- #186: a preemptive layout line is followed by the free-round line
    -- before any top-up in that battle
    local pre, free, topUp = nil, nil, nil
    for i, s in ipairs(lines) do
      if s:find("%[layout%] battle type .* preemptive") and pre == nil then pre = i end
      if pre and free == nil and s:find("the preemptive strike's free round") then free = i end
      if pre and topUp == nil and s:find(" heal entity %d+ %(") then topUp = i end
    end
    if pre ~= nil then
      H.assertEq(free ~= nil and (topUp == nil or free < topUp), true,
        "the free-round line follows the preemptive layout before any top-up")
      H.log("[test] preemptive strike measured at line " .. pre)
    else
      H.log("[test] no preemptive strike rolled on this walk (a 1/8 roll per battle)")
    end
    H.log(string.format("[test] statuses landed: %d over %d battle(s); driver planned around every one",
      seen, #battles))
  end),
})
