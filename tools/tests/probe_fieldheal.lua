-- probe_fieldheal.lua -- learns the field Item/Use/target UI by driving it
-- and watching, so the input-driven routes can heal the party between
-- steps with real presses.  Reads only; writes nothing.
--
-- Boots vargas_entry.mss, which the input-driven Mt. Kolts route delivers
-- with TERRA dead (0/94) and EDGAR on 1/145 and seven Potions and five
-- Tonics unspent.
--
-- ZMENUSTATE is DP $26, the shared cursor row is DP $4B.  Main menu is
-- $05 with Item on row 0; one A lands on $08, the item list.  The state
-- chain is $08 -> A -> $19 -> A -> $70, with $70's A confirming the
-- target.  This pass parks on a known row (Potion), presses A once,
-- screenshots, presses A once more, screenshots, and prints the
-- inventory counts and the roster around every press.
--
-- Not a suite test: no `-- @suite` marker.  Run it directly, keeping the
-- artifacts so the windows can be inspected:
--   OT6_KEEP_RUNS=1 OT6_NO_PUBLISH=1 tools/tests/run.sh tools/tests/probe_fieldheal.lua
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_entry.mss.lua"

local ZMENUSTATE, CURSOR = 0x26, 0x4B
local POTION, TONIC = 0xE9, 0xE8

local function invSlot(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id and H.readByte(0x1969 + i) > 0 then
      return i
    end
  end
  return nil
end
local function invCount(id)
  local s = invSlot(id)
  return s and H.readByte(0x1969 + s) or 0
end

local function roster()
  local out = {}
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
      local b = 0x1600 + 37 * c
      out[#out + 1] = string.format("c%d %d/%d", c,
        H.readWord(b + 9), H.readWord(b + 11))
    end
  end
  return table.concat(out, " ")
end

local function snap(tag)
  return H.call(function()
    H.log(string.format("[%s] ZMENUSTATE=%02X cursor=%02X | %s | tonic=%d " ..
      "potion=%d", tag, H.readByte(ZMENUSTATE), H.readByte(CURSOR), roster(),
      invCount(TONIC), invCount(POTION)))
    H.screenshot("probe_" .. tag)
  end)
end

local last = { st = -1, cur = -1 }
local function traceFrame(tag)
  local st, cur = H.readByte(ZMENUSTATE), H.readByte(CURSOR)
  if st ~= last.st or cur ~= last.cur then
    last.st, last.cur = st, cur
    H.log(string.format("  [%s] f%d state=%02X cursor=%02X",
      tag, H.frame, st, cur))
  end
end

local function traceFor(n, tag)
  local i = 0
  return H.driveUntil(function() i = i + 1; return i > n end, n + 120, {
    H.call(function() H.setPad({}); traceFrame(tag) end),
  }, "trace " .. tag)
end

local function press(btn, n, tag)
  return H.cond(function() return true end, {
    H.pressButtons({ btn }, 4),
    H.release(),
    traceFor(n or 120, tag),
  })
end

local function toRow(want, tag)
  return H.driveUntil(function() return H.readByte(CURSOR) == want end, 2400, {
    H.call(function()
      traceFrame(tag)
      local cur = H.readByte(CURSOR)
      H.setPad((H.frame % 10 < 4)
        and { [cur < want and "down" or "up"] = true } or {})
    end),
  }, tag)
end

H.run({ maxFrames = 60000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 600, "field control", 5),
  H.call(function()
    H.log("roster at boot: " .. roster())
    H.log(string.format("tonic slot=%s potion slot=%s",
      tostring(invSlot(TONIC)), tostring(invSlot(POTION))))
  end),

  press("x", 150, "menu open"),
  snap("main"),
  toRow(0, "main cursor -> Item"),
  H.release(), H.waitFrames(20),
  press("a", 150, "enter Item"),
  snap("list"),

  -- park on the Potion row: a heal of +250 (Potion) against +50 (Tonic)
  -- shows in the roster which row was consumed
  toRow(invSlot(POTION) or 0, "list cursor -> Potion"),
  H.release(), H.waitFrames(20),
  snap("list_on_potion"),

  press("a", 200, "A#1 on Potion"),
  snap("after_a1"),

  press("a", 200, "A#2"),
  snap("after_a2"),

  -- whichever of those windows is the target cursor, walk it and watch
  H.repeatN(3, {
    H.pressButtons({ "down" }, 4),
    H.release(),
    traceFor(45, "down"),
  }),
  snap("after_downs"),

  press("a", 250, "A#3 (confirm)"),
  snap("after_a3"),

  -- back out to the field so the probe ends in a known state
  H.repeatN(4, {
    H.pressButtons({ "b" }, 4),
    H.release(),
    traceFor(60, "back"),
  }),
  snap("backed_out"),
})
