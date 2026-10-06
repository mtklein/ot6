-- @manual standalone: lua tools/tests/field_care_selftest.lua
-- field_care_selftest.lua -- an M.fieldCare step a loop reuses cares on every
-- visit (#409).
--
-- No emulator.  The kernel's latches (`served`, the refused plans) belong
-- to one visit; before #409 the step kept one kernel for its life, so a
-- loop that reset the step and came back with work to do found `served`
-- already set: "heal/revive through the field menu satisfied after 0
-- frames", and nothing was cared for (battle_hirecrew's party walked on
-- with one member standing and wiped).  Here the kernel is a stand-in
-- (M.careKernel) whose `served` latches the way the real one's does, the
-- menu reads are stubbed open and closed on cue, and the step is driven
-- through two visits with a reset between: the kernel must serve twice.
-- The negative control is the step without its reset hook (M.withReset
-- made a no-op): the second visit then serves nothing.
local mem = {}
emu = {
  eventType = { inputPolled = 1, startFrame = 2 },
  callbackType = { exec = 1, read = 2, write = 3 },
  memType = { snesWorkRam = 1, snesPrgRom = 2 },
  addEventCallback = function() return 1 end,
  removeEventCallback = function() end,
  addMemoryCallback = function() return 1 end,
  read = function(a) return mem[a] or 0 end,
  readWord = function(a) return (mem[a] or 0) | ((mem[a + 1] or 0) << 8) end,
  write = function(a, v) mem[a] = v end,
  writeWord = function(a, v) mem[a] = v & 0xFF; mem[a + 1] = v >> 8 end,
  setInput = function() end,
  getState = function() return {} end,
}
OT6_SYMS = setmetatable({}, { __index = function() return 0 end })
local rawPrint = print
print = function() end
local H = dofile("tools/tests/lib/ot6.lua")
loadfile("tools/tests/lib/ot6_field.lua")(H)
print = rawPrint

local function visits(noReset)
  local need, menuUp, serves, kernels = true, false, 0, 0
  H.careKernel = function(opts)
    kernels = kernels + 1
    local served = false
    return {
      tag = opts.tag or "care", budget = 600,
      anyNeed = function() return need end,
      serveFrame = function() served = true; serves = serves + 1; need = false end,
      served = function() return served end,
      roster = function(what) return "[care] " .. what end,
    }
  end
  H.eventTimerLive = function() return false end
  H.battleLoadStarted = function() return false end
  H.mainMenuUp = function() return menuUp end
  H.fieldControl = function() return not menuUp end
  H.tileAligned = function() return true end
  H.worldMode = function() return false end
  H.setPad = function(b) if b and b[1] == "x" then menuUp = true end; if b and b[1] == "b" then menuUp = false end end
  H.log = function() end
  local realReset = H.withReset
  if noReset then H.withReset = function(step) return step end end
  local step = H.fieldCare({ tag = "selftest" })
  H.withReset = realReset
  local function run()
    for _ = 1, 5000 do
      if step:tick() == "done" then return end
    end
    error("the care step never finished")
  end
  run()
  local first = serves
  step:reset()
  need = true            -- a fight later: someone is hurt again
  run()
  return first, serves - first, kernels
end

local first, second, kernels = visits(false)
assert(first == 1, "first visit serves once, got " .. first)
assert(second == 1, "second visit, after the loop's reset, serves again (#409), got " .. second)
assert(kernels == 2, "the reset builds a fresh kernel, got " .. kernels .. " kernels")
local cf, cs = visits(true)
assert(cf == 1 and cs == 0, string.format("control: without the reset hook the second visit serves "
  .. "nothing (the bug), got %d then %d", cf, cs))
print("field_care_selftest: PASS -- a fieldCare step reset between visits serves on both (one kernel a "
  .. "visit); the control without the reset serves only the first (#409)")
