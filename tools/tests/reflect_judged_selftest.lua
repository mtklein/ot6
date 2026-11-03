-- @manual standalone: lua tools/tests/reflect_judged_selftest.lua
-- reflect_judged_selftest.lua -- the Reflect half of the confirm's cast guard
-- (#388, #500, M.reflectJudged): a reflectable cast is judged on the bodies
-- the cursor ($7B7E) holds at the confirm, not on every standing body, so a
-- Fire on a body out of Reflect goes in while a Hidonite beside it reflects.
-- Synthetic slots, no emulator: the escape paths -- a body under the cursor
-- fallen before the confirm (the engine retargets the cast), an empty cursor
-- (on the party), a target gone into Reflect since the plan, a spread over a
-- mirror -- keep the whole-stage rule, and absorb and null stay judged on
-- the stage (M.castVeto's reflectSlots).  Every assertion runs against the
-- lib as it is (it must hold) and against a mutant of the function's own
-- source (it must fail).
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
local function check(what, name, from, to, f)
  n = n + 1
  local ok, r = pcall(f)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local real = H[name]
  H[name] = mutant(name, from, to)
  local mok, mr = pcall(f)
  H[name] = real
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant ('%s' -> '%s') passed it too", what, from, to))
  checks[#checks + 1] = what
end
-- the confirm's decision: castVeto on the stage, Reflect judged on the cursor
local function veto(elem, tgtmons, slots)
  local s, why = H.castVeto(elem, true, slots, H.reflectJudged(tgtmons, slots))
  return s and s.slot, why
end
local function body(slot, reflect, absorb, null)
  return { slot = slot, species = 0x100 + slot, reflect = reflect or false, absorb = absorb or 0, null = null or 0 }
end
-- Hidon's field: Hidon in slot 0, Hidonite $160 (Reflect) in slot 3, two more
local field = { body(0), body(2), body(3, true), body(4) }
local function without(s)
  local t = {}
  for _, x in ipairs(field) do if x.slot ~= s then t[#t + 1] = x end end
  return t
end
local FIRE = 0x01
check("the cursor on Hidon alone, out of Reflect: the cast goes", "reflectJudged",
  "if seen ~= tgtmons then return slots end", "do return slots end",
  function() return veto(FIRE, 0x01, field) == nil end)
check("two bodies under the cursor, neither in Reflect: the cast goes", "reflectJudged",
  "if (tgtmons & (1 << s.slot)) ~= 0 then", "if (1 << s.slot) == tgtmons then",
  function() return veto(FIRE, 0x05, field) == nil end)
check("the cursor on the Hidonite in Reflect (a steer that gave up there): refused", "reflectJudged",
  "  return t\n", "  return {}\n",
  function() local s, why = veto(FIRE, 0x08, field); return s == 3 and why == "reflect" end)
check("a spread over the field with a mirror in it: refused", "reflectJudged",
  "  return t\n", "  return {}\n",
  function() local s, why = veto(FIRE, 0x1D, field); return s == 3 and why == "reflect" end)
check("the aimed body fell before the confirm (the engine retargets): judged on the stage", "reflectJudged",
  "if seen ~= tgtmons then return slots end", "",
  function() local s, why = veto(FIRE, 0x01, without(0)); return s == 3 and why == "reflect" end)
check("an empty cursor (on the party): judged on the stage", "reflectJudged",
  "if tgtmons == 0 or M.REFLECT_PER_TARGET == false then return slots end",
  "if M.REFLECT_PER_TARGET == false then return slots end",
  function() local s, why = veto(FIRE, 0x00, field); return s == 3 and why == "reflect" end)
check("the target went into Reflect after the plan: refused", "reflectJudged",
  "  return t\n", "  return {}\n",
  function()
    local t = { body(0, true), body(3, true) }
    local s, why = veto(FIRE, 0x01, t); return s == 0 and why == "reflect"
  end)
check("the lever off (M.REFLECT_PER_TARGET = false): the old whole-stage rule", "reflectJudged",
  "if tgtmons == 0 or M.REFLECT_PER_TARGET == false then return slots end",
  "if tgtmons == 0 then return slots end",
  function()
    H.REFLECT_PER_TARGET = false
    local ok, s, why = pcall(veto, FIRE, 0x01, field)
    H.REFLECT_PER_TARGET = nil
    return ok and s == 3 and why == "reflect"
  end)
-- absorb and null stay judged on the stage: a body off the cursor that
-- drinks the element still refuses the cast
check("a body off the cursor absorbs the element: refused on the stage", "castVeto",
  "for _, s in ipairs(slots) do\n      if (s.absorb & elem) ~= 0", "for _, s in ipairs(reflectSlots or slots) do\n      if (s.absorb & elem) ~= 0",
  function()
    local t = { body(0), body(3, false, FIRE) }
    local s, why = veto(FIRE, 0x01, t); return s == 3 and why == "absorb"
  end)
check("a body off the cursor nulls the element: refused on the stage", "castVeto",
  "for _, s in ipairs(slots) do\n    if elem ~= 0 and (s.null & elem) == elem", "for _, s in ipairs(reflectSlots or slots) do\n    if elem ~= 0 and (s.null & elem) == elem",
  function()
    local t = { body(0), body(3, false, 0, FIRE) }
    local s, why = veto(FIRE, 0x01, t); return s == 3 and why == "null"
  end)
check("no cursor handed in (a plan made before the window): judged on the stage", "castVeto",
  "for _, s in ipairs(reflectSlots or slots) do\n      if s.reflect", "for _, s in ipairs(reflectSlots or {}) do\n      if s.reflect",
  function() local s, why = H.castVeto(FIRE, true, field); return s and s.slot == 3 and why == "reflect" end)
print(string.format("reflect_judged_selftest: PASS -- %d assertions, each failed by its own mutant: %s",
  n, table.concat(checks, "; ")))
