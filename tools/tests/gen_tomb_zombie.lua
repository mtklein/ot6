-- gen_tomb_zombie.lua -- a battle in Darill's Tomb at the moment a Zombie
-- lands on a party member, with a turn to spare: the fixture
-- battle_zombiecure plays on.
--
-- From wor_tomb (CELES, SABIN, EDGAR and SETZER on the tomb's save point,
-- 300 (122,14)), up through (122,7) into the grave's room, 299 (100,28),
-- whose pool (field group 150: PowerDemon; Exoray x3; Mad Oscar + Exoray)
-- holds the tomb's Zombie-casters (the PowerDemon's Soul Out, the Exoray's
-- DoomPollen; route-wor-falcon 3.5).  The party paces the room between
-- (100,26) and (100,17), the grave's tile (100,14) kept off the plan,
-- fighting with navTo's playBattles="tactical" driver.
--
-- When a Zombie lands on a member with another standing, the whole machine
-- is captured that frame (H.requestSaveState) and held, and the battle
-- plays on with the same driver.  The capture is emitted as tomb_zombie.mss
-- only if the battle had a TURN TO SPARE for the cure: another standing
-- member's command window opened while the zombie stood, and the battle was
-- still up SPARE frames after that window opened (the cure's item has to
-- run before the last blow; in the first variation set 3 of 19 landings
-- had a Revivify planned that the battle's end beat, route-wor-falcon
-- 12.3).  A landing without one is said and skipped, and the pacing goes
-- on.  battle_zombiecure asserts the same precondition by name.
--
-- A landing that qualifies live is then PROVED the way the suite will use it
-- (the 2026-11-03 miss: the party's own pacing had a turn to spare on the
-- landing the generator saw, and the suite, loading the same frame and
-- driving it with advanceStory's cure line, saw the battle end 212 frames
-- later -- a Zombied member's engine-aimed Fight, queued before the landing,
-- resolves at a different frame and on a different target depending on which
-- commands the party gives while it waits, so the battle's length is the
-- drive's, not the frame's).  The generator saves a resume point, reloads
-- the landing and plays it out with the suite's own drive (advanceStory,
-- playBattles "tactical", zombieCure), and emits the landing only if the
-- window and the SPARE frames come out there too; otherwise it says so,
-- returns to the resume point and paces on to the next landing (ROUNDS
-- bounds the tries).
--
-- Every battle's draw is logged as a [key] line (the seed $be at
-- InitBattle's store and the battle group $11E0) and every landing with
-- its key, so a set of fixtures is counted by distinct battle key.  SKIP
-- qualifying landings are passed over before the one captured (0 here; a
-- variation set derives copies with more, build/attempts/wt/wor-tomb/
-- review/).  Measured by key (review/zfix/gen_k*.log, SKIP 0 and 1 at
-- seed shifts 0, 7, 13, 21, 29 and 37): 141 grave-room battles over 57
-- distinct battle keys, 18 landings over 10 of those keys, every one of
-- them with a turn to spare; the first came in battle 6 to 16.
-- CAP bounds the walk; a run that meets no qualifying landing
-- fails at that assertion naming every battle fought.  Reads only; every
-- step is a button press.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/wor_tomb.mss.lua"
local CAP = 40
local SKIP = 0
local SPARE = 900
local ROUNDS = 12
local ST1, MENU, ACTOR = 0x3EE4, 0x7BCA, 0x62CA

local o0 = nil
-- the battle is up while a monster of it still stands: present ($3AA8 bit
-- 0) with HP.  monstersPresent() reads the opening line-up, so it stayed
-- true through the victory text, and a battle whose last blow fell 711
-- frames after the window read as "up 900 frames after it"
-- (build/attempts/wt/v029-narshe-route/zombiecure/zc_trace3.log: both
-- monsters 0 HP at f714-715, the window at f3, the battle unloaded at
-- f1469; the Revivify planned at f430 never ran)
local function up()
  if not H.battleLoadStarted() then return false end
  for s = 0, 5 do
    if (H.readByte(0x3AA8 + s * 2) & 1) == 1 and H.readWord(0x3BFC + s * 2) > 0 then return true end
  end
  return false
end
local key = "?"
local cand = nil          -- the held landing: { e, f, key, req, window }
local skipped, qualified, emitted, landings = 0, 0, false, {}
local pending = nil     -- a landing that qualified live, awaiting the proof by the suite's drive
local proving = false
local function standing(e)
  local s1 = H.readByte(ST1 + e * 2)
  return H.readWord(0x3C1C + e * 2) > 0 and H.readWord(0x3BF4 + e * 2) > 0 and (s1 & 0xC2) == 0
end
local function zombied(e)
  local s1 = H.readByte(ST1 + e * 2)
  return (s1 & 0x02) ~= 0 and (s1 & 0x80) == 0 and H.readWord(0x3C1C + e * 2) > 0
end

local function judge(why, ok)
  landings[#landings + 1] = string.format("%s %s", cand.key, ok and "QUALIFIES" or ("no: " .. why))
  H.log(string.format("[tomb_zombie] f%d landing on entity %d in battle %s %s: %s", H.frame, cand.e, cand.key,
    ok and "QUALIFIES" or "does not qualify", why))
  if ok then
    qualified = qualified + 1
    if qualified > SKIP and not emitted and not pending then
      H.assertEq(cand.req.done and cand.req.ok, true, "the capture at the landing")
      pending = cand
      pending.resume = H.requestSaveState()
      H.log(string.format("[tomb_zombie] battle %s, entity %d (char %d), landed f%d, qualified live: held for the "
        .. "proof by the suite's drive", cand.key, cand.e, cand.char, cand.f))
    elseif not emitted then
      skipped = skipped + 1
    end
  end
  cand = nil
end

emu.addEventCallback(function()
  if o0 == nil or emitted or pending or proving then return end
  if not up() then
    if cand then
      judge(cand.window and string.format("the battle ended %d frames after the first standing window (SPARE %d)",
        H.frame - cand.window, SPARE) or "the battle ended before another standing member's window opened", false)
    end
    return
  end
  if cand == nil then
    local n = 0
    for e = 0, 3 do if standing(e) then n = n + 1 end end
    for e = 0, 3 do
      if zombied(e) and n >= 1 and not (landings.seen and landings.seen[key .. ":" .. e]) then
        landings.seen = landings.seen or {}
        landings.seen[key .. ":" .. e] = true
        cand = { e = e, f = H.frame, key = key, char = H.readByte(0x3ED8 + e * 2), req = H.requestSaveState() }
        H.log(string.format("[tomb_zombie] f%d battle %s: Zombie lands on entity %d (char %d), %d member(s) "
          .. "standing; held", H.frame, key, e, cand.char, n))
        return
      end
    end
    return
  end
  if not zombied(cand.e) then
    if not cand.window then judge("the Zombie cleared before another standing member's window opened", false) end
    -- cleared after the window: the turn was there; wait out SPARE below
    if cand and cand.window and H.frame - cand.window >= SPARE then
      judge(string.format("cleared after the window, the battle still up %d frames after it", SPARE), true)
    end
    return
  end
  if not cand.window and H.readByte(MENU) ~= 0 then
    local a = H.readByte(ACTOR) & 3
    if a ~= cand.e and standing(a) then
      cand.window = H.frame
      H.log(string.format("[tomb_zombie] f%d entity %d's command window opens with entity %d Zombied", H.frame, a, cand.e))
    end
  end
  if cand.window and H.frame - cand.window >= SPARE then
    judge(string.format("the battle still up %d frames after the window", SPARE), true)
  end
end, emu.eventType.startFrame)

-- the proof: the suite's own drive on the held landing, its precondition read the way the suite reads it
local P = nil
local function proofWatch()
  if P == nil or P.done or not up() then return end
  P.lastUp = H.frame
  if not P.window and H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) ~= P.e then P.window = H.frame end
end
emu.addEventCallback(proofWatch, emu.eventType.startFrame)

local function pace()
  local wp = 1
  local WPS = { { 100, 26 }, { 100, 17 } }
  return H.withReset(H.driveUntil(function()
    if emitted or (pending and pending.resume.done) then return true end
    return cand == nil and not pending and not up() and #H.outcomes - o0 >= CAP
  end, 590000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 20000, playBattles = "tactical", avoid = { { 100, 14 }, { 100, 29 } } }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "pacing the grave's room"), function() wp = 1 end)
end

local function prove()
  local req, po0
  return {
    H.call(function()
      proving = true
      H.assertEq(pending.resume.done and pending.resume.ok, true, "the resume point at the landing's proof")
      H.setPad({})
      req = H.requestLoadState(pending.req.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "the held landing's reload")
      H.rearmInputInjection()
      po0 = #H.outcomes
      P = { e = pending.e, f = H.frame }
      H.log(string.format("[tomb_zombie] proof: battle %s reloaded at f%d, driven by advanceStory as battle_zombiecure "
        .. "drives it", pending.key, H.frame))
    end),
    H.advanceStory(function() return #H.outcomes > po0 and H.hasControl() end, 50000,
      { playBattles = "tactical", fight = { zombieCure = true } }),
    H.call(function()
      P.done = true
      local ok = P.window ~= nil and (P.lastUp or 0) - P.window >= SPARE
      H.log(string.format("[tomb_zombie] proof: window %s, battle up until f%s, SPARE %d: %s", tostring(P.window),
        tostring(P.lastUp), SPARE, ok and "holds" or "does NOT hold"))
      landings[#landings + 1] = string.format("%s %s", pending.key, ok and "PROVED" or "not proved by the suite's drive")
      if ok then
        H.emitBlob("tomb_zombie.mss", pending.req.blob)
        emitted = pending
        H.log(string.format("[tomb_zombie] emitted tomb_zombie.mss (%d bytes): battle %s, entity %d (char %d), "
          .. "landed f%d", #pending.req.blob, pending.key, pending.e, pending.char, pending.f))
      else
        skipped = skipped + 1
        local resume = pending.resume.blob
        pending, P = nil, nil
        req = H.requestLoadState(resume)
      end
    end),
    H.cond(function() return not emitted end, {
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "the resume point's reload")
        H.rearmInputInjection()
        proving = false
        cand = nil
      end),
    }),
  }
end

local steps = {
  H.loadState(STATE),
  H.call(function()
    o0 = #H.outcomes
    H.assertEq(H.mapId() & 0x1ff, 300, "wor_tomb stands in Darill's Tomb B3 (map 300)")
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      key = string.format("be%02X-g%04X", emu.getState()["cpu.a"] & 0xff, H.readWord(0x11e0))
      H.log(string.format("[key] battle key %s f%d map %d", key, H.frame, H.mapId() & 0x1ff))
    end, emu.callbackType.exec, addr, addr)
  end),
  H.crossDoor(122, 7, 299, 100, 28, "the east room (122,7) -> the grave's room (100,28)"),
}
for _ = 1, ROUNDS do
  steps[#steps + 1] = H.cond(function() return not emitted end, {
    pace(),
    H.cond(function() return pending ~= nil and not emitted end, prove()),
  })
end
steps[#steps + 1] = H.call(function()
  local forms = {}
  for i = o0 + 1, #H.outcomes do
    forms[#forms + 1] = string.format("$%03X %s", H.outcomes[i].form & 0x1FF, H.outcomes[i].kind)
  end
  H.log(string.format("[tomb_zombie] %d battle(s) fought: %s; landings: %s", #H.outcomes - o0,
    table.concat(forms, ", "), #landings > 0 and table.concat(landings, "; ") or "none"))
  H.assertEq(emitted ~= false, true, string.format("a Zombie landed with a turn to spare (another standing "
    .. "member's window, the battle up %d frames after it, live and under the suite's drive) within %d battles, past "
    .. "%d skipped, in %d round(s) (fought: %s)", SPARE, CAP, SKIP, ROUNDS, table.concat(forms, ", ")))
end)
steps[#steps + 1] = H.logStep(function()
  return string.format("tomb_zombie generated: battle %s, entity %d (char %d) Zombied at f%d",
    emitted.key, emitted.e, emitted.char, emitted.f)
end)
H.run({ maxFrames = 1200000 }, steps)
