-- @suite savestate=wor_grave
-- battle_typicalgate.lua -- the typical-action gate read against the
-- engine's own account (review of ad048b29, made independent on the review
-- of 4ff9b236): Dullahan's fight, the grave pressed with A as the route
-- does, played by the fight driver one call a frame.
--
-- The ground truth does not read what the driver reads.  The driver keys
-- its ledger off party HP deltas, the $B1 counter flag and the $B8 target
-- bits at each ExecCmd entry, and its turns off the monster's ATB gauge.
-- This file keys off:
--   the turns: the ATB queueing one (gaugefull's `jsr _c24e77`, "add
--              action to queue", checked against the ROM bytes: one per
--              gauge fill, a Broken monster's refused turn included), and
--              every ExecCmd entry of that monster after it that ExecRetal
--              did not run -- the driver reads the gauge's high byte
--              instead;
--   the counters: ExecRetal (@4b7b) and the entry it runs;
--   the damage: ApplyDmg (@12f5) as the engine applies it, $33D0,y on a
--              party target y, capped at that target's HP;
--   the final targets: the targets ApplyDmg was called on.
-- A unit counts when it is a counter that landed HP, or a turn that did
-- not land only on monsters.  The script's $2E/$2F entries are nobody's
-- action.  A unit's value is the most HP it took off one member.  The
-- truth is H.typicalTruth (lib/ot6.lua), the one source the lab's
-- build/lab/care/truth_hook.lua loads too; nothing in the driver reads it.
--
-- Asserted at the fight's end, the driver's ledger flushed
-- (Driver:flushLedger), for every slot:
--   - the count (L.actN) and the typical sum (L.actSum) equal the
--     engine's;
--   - precondition: at least one counter landed (Dullahan's retal Battle,
--     "if_hit: attack NOTHING, NOTHING, BATTLE", ai_script.asm:5470).
-- The bcf5240f-ad048b29 reading (H.MONACT_OLD) closed 89 actions over arm
-- B's 32 fights at ad048b29 (build/attempts/wt/care-policy-review/
-- recount_r3.txt, dull_r10_B), where lab_grave logged 227 monster ExecCmd
-- entries ($2E/$2F excluded: build/attempts/wt/care-policy/dull/
-- dull_r10_B); f8f9ad66's arm on the same snapshots logged 223
-- (dull_policy_basesnap).  It is this file's negative control.
-- No chain fixture stands at a two-action monster's fight.  The
-- two-action case (the last of three $011 in gen_tunnelarmr's first
-- battle, ai_script.asm _17: "if_num_monsters 1 / attack SPECIAL / attack
-- BATTLE, BATTLE, NOTHING") is the lab's: build/lab/care/truth_hook.lua
-- on that generator (build/attempts/wt/care-policy/twoact/).  Nothing here
-- writes emulated state.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_grave.mss.lua"
TRUTH = H.typicalTruth()

local F
local function up() return H.battleLoadStarted() and H.monstersPresent() > 0 end
local function tick()
  if not up() then F.idle(); return end
  F.frame()
end

H.run({ maxFrames = 30000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    TRUTH.reset()
    F = H.newFightDriver("typicalgate", { tactical = true, boost = true, items = true, runic = true })
  end),
  H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000, "the grave: face up, A"),
  H.release(),
  H.waitUntil(function() return up() end, 3000, "the fight is up", 1),
  H.driveUntil(function() return not up() end, 25000, { H.call(tick) }, "the driver's play"),
  H.release(),
  H.call(function()
    F.driver:flushLedger()
    local want, lines = TRUTH.expected()
    for _, l in ipairs(lines) do H.log("[typicalgate] " .. l) end
    local landed = 0
    for _, u in ipairs(TRUTH.units) do
      local v = 0
      for _, d in pairs(u.per) do if d > v then v = d end end
      if u.counter and v > 0 then landed = landed + 1 end
    end
    H.assertEq(landed >= 1, true, "precondition: a counterattack landed HP in the fight (Dullahan's retal Battle)")
    for s = 0, 5 do
      local w, L = want[s], F.driver.hitLedger[s]
      if w ~= nil or (L and (L.actN or 0) > 0) then
        local wn, ws = w and w.n or 0, w and w.sum or 0
        local gn, gs = L and L.actN or 0, L and L.actSum or 0
        H.log(string.format("[typicalgate] slot %d: the engine's units %d (sum %d), the driver's ledger %d (sum %d)",
          s, wn, ws, gn, gs))
        H.assertEq(gn, wn, string.format("slot %d: the driver's typical-action count is the engine's", s))
        H.assertEq(gs, ws, string.format("slot %d: the driver's typical-action sum is the engine's", s))
      end
    end
    H.log("[typicalgate] PASSED")
  end),
})
