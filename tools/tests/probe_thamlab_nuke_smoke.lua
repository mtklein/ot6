-- probe_thamlab_nuke_smoke.lua -- thamasa fire lab: smoke for the fight
-- driver's new attack-magic repertoire (opts.nuke / opts.nukeLore).
--
--   tools/tests/run.sh tools/tests/probe_thamlab_nuke_smoke.lua
--
-- Hand-run instrument (probe_): boots build/states/battle_entry.mss (the
-- generic first-battle fixture) twice and plays the same fight with
-- H.newFightDriver, once per arm:
--
--   A  default opts -- the repertoire must be INERT: not one nuke or lore
--      plan in the log, and the fight completes the way it always has.
--      (A byte-compare against the old driver is impractical headless;
--      "no new plan kinds ever offered" is the observable contract, since
--      every new branch announces itself through M.log before returning
--      a plan.)
--   B  opts.nuke={Ice,Ice2} + opts.nukeLore={Aqua Rake} + boost -- this
--      fixture's party is the intro trio in Magitek armor, so whether
--      anything is castable is measured, not assumed: the probe logs each
--      actor's command table and spellCell/Lore gate verdicts.  If nobody
--      can cast, the assertion is the clean no-castable-nuke fallthrough:
--      plan=fight turns happen, no wedge, no lore window ever opened.
--
-- The REAL measurement (FlameEater/ambush win rates under the repertoire)
-- runs later against the thamlab fixtures; this file only proves the new
-- opts are inert by default and fail safe with nothing castable.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

-- Fire leads the smoke list: this fixture's only mage is intro Terra, who
-- knows Fire (arm A's cure plans prove her live Magic list works) but not
-- Ice, so Fire is what makes arm B exercise the real cast path end-to-end
-- while Ice/Ice2 exercise the not-known skip.
local FIRE, ICE, ICE2, AQUA_RAKE_LORE = 0x00, 0x01, 0x06, 3
local CMDTBL, BCHID, CURMP = 0x202E, 0x3ED8, 0x3C08
local CMD_MAGIC, CMD_LORE = 0x02, 0x0C

-- Count the driver's own announcements as they stream through H.log: every
-- new repertoire branch logs before it returns a plan, so these counters
-- are exactly "how many times a nuke/lore/fight plan was offered".
local nukeN, loreN, planN, stallN = 0, 0, 0, 0
local baseLog = H.log
H.log = function(s, ...)
  if type(s) == "string" then
    if s:find("nuke $", 1, true) or s:find("nuke lore $", 1, true) then
      nukeN = nukeN + 1
    end
    if s:find("plan=lore", 1, true) then loreN = loreN + 1 end
    if s:find(" plan=", 1, true) then planN = planN + 1 end
    if s:find("LORE STALLED", 1, true) then stallN = stallN + 1 end
  end
  return baseLog(s, ...)
end

local function cmdAt(e, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + e * 12 + r * 3) == cmd then return "row" .. r end
  end
  return "none"
end

local function partyReport(tag)
  for e = 0, 3 do
    local mx = H.readWord(0x3C1C + e * 2)
    if mx > 0 then
      local rows = {}
      for r = 0, 3 do
        rows[#rows + 1] = string.format("%02X",
          H.readByte(CMDTBL + e * 12 + r * 3))
      end
      H.log(string.format(
        "[%s] entity %d char=$%02X cmds=%s hp=%d/%d mp=%d magic=%s lore=%s",
        tag, e, H.readByte(BCHID + e * 2), table.concat(rows, ","),
        H.readWord(0x3BF4 + e * 2), mx, H.readWord(CURMP + e * 2),
        cmdAt(e, CMD_MAGIC), cmdAt(e, CMD_LORE)))
    end
  end
end

-- one arm: reload the fixture, walk into the battle, play it out with the
-- given driver opts, then hand the counters to `check`
local function arm(tag, opts, check)
  local F = nil
  return {
    H.loadState(STATE),
    H.waitFrames(10),
    H.call(function()
      nukeN, loreN, planN, stallN = 0, 0, 0, 0
      F = H.newFightDriver(tag, opts)
      H.log("---- " .. tag .. " ----")
    end),
    H.enterEncounter(),
    H.waitFrames(60),
    H.call(function() partyReport(tag) end),
    H.driveUntil(function()
      return not H.battleLoadStarted()
    end, 30000, {
      H.call(function() F.frame() end),
    }, tag .. ": play the battle out"),
    H.call(function()
      F.idle()
      H.log(string.format(
        "[%s] battle done f%d: nuke offers=%d lore plans=%d plans=%d "
        .. "stalls=%d", tag, H.frame, nukeN, loreN, planN, stallN))
      check()
    end),
  }
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

add({ H.waitFrames(20) })

-- ---------------------------------------------------------------- arm A --
add(arm("smokeA-default", {}, function()
  H.assertEq(planN > 0, true, "arm A: the driver planned turns at all")
  H.assertEq(nukeN, 0, "arm A: default opts never offered a nuke")
  H.assertEq(loreN, 0, "arm A: default opts never offered a lore plan")
  H.assertEq(stallN, 0, "arm A: the lore stall guard never fired")
end))

-- ---------------------------------------------------------------- arm B --
add(arm("smokeB-nuke",
  { nuke = { FIRE, ICE, ICE2 }, nukeLore = { AQUA_RAKE_LORE }, boost = true },
  function()
    H.assertEq(stallN, 0, "arm B: the lore stall guard never fired")
    H.assertEq(loreN, 0,
      "arm B: no Lore command in this party, so no lore plan")
    if nukeN > 0 then
      H.log(string.format(
        "[result] lab=smoke strategy=nuke-smoke castable=1 offers=%d", nukeN))
    else
      -- nothing castable after all: the point is then the CLEAN
      -- fallthrough -- the fight was still planned turn by turn (this
      -- fixture's Magitek party has no Fight row, so the fallthrough plan
      -- is `switch`, not `fight`) and finished inside the budget
      H.assertEq(planN > 0, true,
        "arm B: with no castable nuke, the driver still planned turns")
      H.log("[result] lab=smoke strategy=nuke-smoke castable=0 " ..
        "fallthrough=clean")
    end
  end))

H.run({ maxFrames = 120000 }, steps)
