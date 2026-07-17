-- probe_57ba_strip.lua -- write-watcher for the $7E57BA-$7E57BF strip
-- (OT6_CWITNESS word, OT6_RANDPEND, OT6_RANDBTL, two spare bytes).
-- Verifies the strip has ONLY bank-$F0 (OT6) and hook-shim writers
-- across the write-heavy battle paths:
--   phase 1: mines_chase field pacing -> a RANDOM encounter (exercises
--            Ot6MarkRandom's $57BC write from the field trigger, the
--            InitBP consume into $57BD, and the spike witness word) ->
--            fight mashed to victory (exercises Ot6RewardScale reads).
--   phase 2: whelk_doorstep -> the dialog-opening boss fight, mashed
--            for ~6000 frames: battle DIALOGS ($0B6E/$0B6F + the
--            shell's "Gruuu......") and fire-beam attack-name BANNERS
--            both run, the exact family that clobbered $57D5+.
-- $7E57D5 rides along as the positive control: banner machinery MUST
-- hit it. FAIL if any strip write comes from outside bank $F0.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local MINES = "/Users/mtklein/ot6/build/states/mines_chase.mss.lua"
local WHELK = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"

local hits = {}       -- addr -> { count, pcs = {pcstr -> n} }
local foreign = {}    -- strip writes from outside bank $F0
local function watch(lo, hi, strip)
  emu.addMemoryCallback(function(addr, value)
    local h = hits[addr]
    if not h then h = { count = 0, pcs = {} }; hits[addr] = h end
    h.count = h.count + 1
    pcall(function()
      local s = emu.getState()
      local pc = string.format("%02X:%04X v=%02X", s["cpu.k"], s["cpu.pc"], value)
      h.pcs[pc] = (h.pcs[pc] or 0) + 1
      if strip and s["cpu.k"] ~= 0xF0 then
        foreign[#foreign + 1] = string.format("$%06X <- %s", addr, pc)
      end
    end)
  end, emu.callbackType.write, lo, hi)
end

watch(0x7E57BA, 0x7E57BF, true)
watch(0x7E57D5, 0x7E57D5, false)

local function report(tag)
  H.log("--- " .. tag .. " ---")
  local addrs = {}
  for a in pairs(hits) do addrs[#addrs + 1] = a end
  table.sort(addrs)
  for _, a in ipairs(addrs) do
    local h = hits[a]
    local pcs = {}
    for pc, n in pairs(h.pcs) do pcs[#pcs + 1] = pc .. " x" .. n end
    table.sort(pcs)
    H.log(string.format("W $%06X: %d writes | %s", a, h.count,
      table.concat(pcs, " | ")))
  end
end

local aPhase = 0
local function mashThrough(maxFrames, what)
  return H.driveUntil(function() return not H.battleLoadStarted() end,
    maxFrames, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        H.setPad(aPhase < 4 and { "a" } or {})
      end),
    }, what)
end

H.run({ maxFrames = 60000 }, {
  -- phase 1: a real random encounter from field pacing
  H.loadState(MINES),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 1200, "mines control", 10),
  H.driveUntil(function() return H.battleLoadStarted() end, 5000, {
    H.call(function()
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      H.setPad({ [(H.fieldX() >= 78) and "left" or "right"] = true })
    end),
    H.waitFrames(1),
  }, "random encounter fires"),
  H.waitUntilSoft(function() return H.battleActive() end, 900, "p1_active", 30),
  H.call(function()
    H.assertEq(H.readByte(0x57bd), 1, "random-encounter flag latched by InitBP")
    H.assertEq(H.readByte(0x57bc), 0, "pending marker consumed by InitBP")
    H.assertEq(H.readWord(0x57ba), 11, "C witness word intact at $57BA")
  end),
  mashThrough(12000, "random fight resolved"),
  H.call(function() report("after phase 1 (random encounter)") end),

  -- phase 2: the whelk fight (battle dialogs + beam banners)
  H.loadState(WHELK),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 1200, "whelk control", 10),
  H.driveUntil(function() return H.battleLoadStarted() end, 3300, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.waitUntilSoft(function() return H.battleActive() end, 900, "p2_active", 30),
  H.call(function()
    H.assertEq(H.readByte(0x57bd), 0, "event battle carries NO random flag")
    H.assertEq(H.readWord(0x57ba), 11, "C witness word intact at $57BA")
  end),
  -- mash beams into the fight long enough for banners, shell dialogs,
  -- and MegaVolt counters; the fight itself need not resolve
  H.call(function() soak = 0 end),
  H.driveUntil(function()
    soak = soak + 1
    return soak >= 6000 or not H.battleLoadStarted()
  end, 6600, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      H.setPad(aPhase < 4 and { "a" } or {})
    end),
  }, "banner+dialog soak"),
  H.call(function()
    report("after phase 2 (whelk banners + dialogs)")
    H.assertEq(hits[0x7E57D5] ~= nil, true,
      "positive control: banner machinery wrote $57D5")
    for _, f in ipairs(foreign) do H.log("FOREIGN " .. f) end
    H.assertEq(#foreign, 0, "strip $57BA-$57BF has only bank-F0 writers")
  end),
})
