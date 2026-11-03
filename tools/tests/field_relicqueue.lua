-- @suite savestate=wor_tomb
-- field_relicqueue.lua -- H.dressRelics's queue pick (H.relicDressPick) counts each relic a member's changes take
-- against the bag (#350).  The line at 867a26d6 stopped in gen_wor_cyan: the relic rule gave CYAN both Hyper Wrists,
-- one in the bag and one still on TERRA, and the pick (by presence) dressed CYAN first: "relics with CYAN: CYAN's
-- relic slot 5 holds Hyper Wrist $D2: got 255".  On a stub queue and bag: TERRA, taking the bag's Earrings over her
-- Hyper Wrist, goes first; with both Hyper Wrists in the bag CYAN goes first, in queue order; with neither member's
-- relics there nobody goes; and a pick by presence (a mutant, run here) takes CYAN, so the case reaches the count.
-- Reads nothing from the fixture and writes nothing; it boots one only because a suite runs in the emulator.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_tomb.mss.lua"
local HW, EAR = 0xD2, 0xC3

H.run({ maxFrames = 600 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    local queue = { { name = "CYAN", changes = { { 4, HW }, { 5, HW } } }, { name = "TERRA", changes = { { 5, EAR } } } }
    local bag = { [HW] = 1, [EAR] = 1 }
    local function have(id) return bag[id] or 0 end
    H.assertEq(H.relicDressPick(queue, have), 2, "TERRA (Earrings, in the bag) goes before CYAN (two Hyper Wrists, "
      .. "one in the bag)")
    bag[HW] = 2
    H.assertEq(H.relicDressPick(queue, have), 1, "with both Hyper Wrists in the bag CYAN goes first, in queue order")
    bag[HW], bag[EAR] = 1, 0
    H.assertEq(H.relicDressPick(queue, have), nil, "nobody can go: CYAN lacks a Hyper Wrist, TERRA the Earrings")
    -- the mutant: the pick by presence takes CYAN with one of his two in the bag
    local function byPresence(q, hv)
      for i, p in ipairs(q) do
        local ok = true
        for _, c in ipairs(p.changes) do if c[2] ~= 0xFF and hv(c[2]) < 1 then ok = false end end
        if ok then return i end
      end
    end
    bag[HW], bag[EAR] = 1, 1
    H.assertEq(byPresence(queue, have), 1, "the case reaches the count: a pick by presence takes CYAN first")
    H.log("[relicqueue] PASSED: TERRA before CYAN with one of his two Hyper Wrists in the bag")
  end),
})
