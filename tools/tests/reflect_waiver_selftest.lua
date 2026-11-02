-- @manual standalone: lua tools/tests/reflect_waiver_selftest.lua
-- reflect_waiver_selftest.lua -- the one exemption from the cast guard's
-- Reflect half (#388, M.reflectWaived): STRAGO's study, a single-target
-- Scan, may be confirmed while another body stands in Reflect only when the
-- cursor ($7B7E) holds exactly one standing monster out of Reflect at the
-- confirm.  Synthetic slots, no emulator: the escape paths the review named
-- -- the aimed body fallen before the confirm, a steer that gave up on
-- another body, the target gone into Reflect since the plan -- each keep
-- the guard.  Every assertion runs against the lib as it is (it must hold)
-- and against a mutant of the function's own source (it must fail).
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile("tools/tests/lib/ot6.lua")
local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local lib = slurp("tools/tests/lib/ot6.lua")
local function plain(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local function mutant(name, from, to)
  local a = lib:find("\nfunction M%." .. name .. "%(")
  assert(a, "M." .. name .. " in the lib")
  local b = lib:find("\nend\n", a, true)
  local src = lib:sub(a + 1, b + 4)
  local _, count = src:gsub(plain(from), "")
  assert(count == 1, string.format("mutant of M.%s: '%s' occurs %d times", name, from, count))
  src = src:gsub(plain(from), (to:gsub("%%", "%%%%")))
  local chunk = assert(load("local M = setmetatable({}, { __index = ... })\n" .. src
    .. "\nreturn M." .. name, "mutant " .. name, "t", _G))
  return chunk(H)
end
local checks, n = {}, 0
local function check(what, from, to, f)
  n = n + 1
  local ok, r = pcall(f)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local real = H.reflectWaived
  H.reflectWaived = mutant("reflectWaived", from, to)
  local mok, mr = pcall(f)
  H.reflectWaived = real
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant ('%s' -> '%s') passed it too", what, from, to))
  checks[#checks + 1] = what
end
-- Hidon's field: Hidon in slot 0, Hidonite $160 (Reflect) in slot 3, two more
local field = { { slot = 0, reflect = false }, { slot = 2, reflect = false },
                { slot = 3, reflect = true }, { slot = 4, reflect = false } }
local function without(s)
  local t = {}
  for _, x in ipairs(field) do if x.slot ~= s then t[#t + 1] = x end end
  return t
end
check("the cursor on Hidon alone, out of Reflect: waived",
  "then return not s.reflect end", "then return false end",
  function() return H.reflectWaived(0x01, field) == true end)
check("the cursor on the Hidonite in Reflect (a steer that gave up there): kept",
  "then return not s.reflect end", "then return true end",
  function() return H.reflectWaived(0x08, field) == false end)
check("two bodies under the cursor: kept",
  "if (1 << s.slot) == tgtmons then", "if (tgtmons & (1 << s.slot)) ~= 0 then",
  function() return H.reflectWaived(0x09, field) == false end)
check("the aimed body fell before the confirm (not among the standing): kept",
  "  return false\nend", "  return true\nend",
  function() return H.reflectWaived(0x01, without(0)) == false end)
check("the target went into Reflect after the plan: kept",
  "then return not s.reflect end", "then return true end",
  function()
    local t = { { slot = 0, reflect = true }, { slot = 3, reflect = true } }
    return H.reflectWaived(0x01, t) == false
  end)
check("an empty cursor (on the party): kept",
  "  return false\nend", "  return true\nend",
  function() return H.reflectWaived(0x00, field) == false end)
print(string.format("reflect_waiver_selftest: PASS -- %d assertions, each failed by its own mutant: %s",
  n, table.concat(checks, "; ")))
