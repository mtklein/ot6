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
-- The walk is navTo's playBattles="tactical" (M.newFightDriver with the
-- walk options), the driver every route segment fights with.  The test
-- captures the driver's log through H.log and watches the four status
-- bytes on a startFrame callback (reads only), and asserts:
--   * Berserk landed on a party member at least once (the exposure; a
--     walk that no longer draws it fails here, loudly, rather than pass
--     on nothing);
--   * the driver said `[status] ... is under BERSERK` once per
--     (entity, battle) it landed on, with the cure verdict from the ROM
--     ("none in the bag": Remedy's STATUS2 byte is $48);
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

-- status watch: per battle, per entity, when a denying status landed
-- and cleared (in captured-line indices, so the plan lines can be
-- located between them)
local battles, cur = {}, nil
local last = {}
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
      battles[#battles + 1] = cur; cur = nil; last = {}
    end
    return
  end
  if cur == nil then cur = { n = #battles + 1, landed = {}, open = {} } end
  for e = 0, 3 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      local s1, s2, s3 = H.readByte(S1 + e * 2), H.readByte(S2 + e * 2), H.readByte(S3 + e * 2)
      local den = H.turnDenied({ s1 = s1, s2 = s2, s3 = s3 })
      local was = last[e]
      if den ~= nil and was == nil then
        cur.open[e] = { name = den, at = #lines, frame = H.frame,
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

H.run({ maxFrames = 120000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "camp_escaped boots on the World of Balance")
    emu.addEventCallback(function() observe() end, emu.eventType.startFrame)
  end),
  H.worldNavTo(178, 82, { maxFrames = 25000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return mapIdx() == 132 end, 4000, "the forest loads", 5),
  H.call(function()
    -- close a battle still open in the watch (none expected on the field)
    if cur then battles[#battles + 1] = cur; cur = nil end
    for _, b in ipairs(battles) do
      for e, o in pairs(b.open) do o.to = #lines; b.landed[#b.landed + 1] = o end
    end
    local seen = 0
    for _, b in ipairs(battles) do
      for _, o in ipairs(b.landed) do
        seen = seen + 1
        local e, name = nil, o.name
        -- the entity is in the [test] line; recover it from the record
        for ee, _ in pairs({}) do e = ee end
        -- scan the captured window
        local statusLines, planLines, parkLines = 0, 0, 0
        for i = o.at, o.to do
          local s = lines[i]
          if s:find("%[status%] f%+%d+ entity %d+ char %d+ is under " .. name:upper()) then
            statusLines = statusLines + 1
            e = tonumber(s:match("entity (%d+) char"))
          end
        end
        H.assertEq(statusLines, 1, string.format("battle %d: one [status] line for the %s that landed",
          b.n, name))
        for i = o.at, o.to do
          local s = lines[i]
          if e ~= nil and s:find("actor=" .. e .. " char=%d+ plan=") then planLines = planLines + 1 end
          if s:find("parked %d+ pulses") or s:find("consumed %d+ pulses")
             or s:find("FIGHT DRIVER STUCK") or s:find("recovery cap") then
            parkLines = parkLines + 1
          end
        end
        H.assertEq(planLines, 0, string.format("battle %d: no plan made for entity %s while under %s",
          b.n, tostring(e), name))
        H.assertEq(parkLines, 0, string.format("battle %d: no park, pulse-budget or recovery-cap line under %s",
          b.n, name))
        if name == "Berserk" then
          local cureSaid = false
          for i = o.at, o.to do
            if lines[i]:find("cure: none in the bag %(Remedy x%d+ carries no Berserk bit%)") then cureSaid = true end
          end
          H.assertEq(cureSaid, true, string.format("battle %d: the [status] line carries the ROM's cure verdict", b.n))
        end
      end
    end
    H.assertEq(seen >= 1, true, "a turn-denying status landed on the walk (the exposure; "
      .. #battles .. " battle(s) fought)")
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
