-- probe_fieldcells.lua -- FIND the cursor cells of the field Item windows by
-- differencing memory across a single pad edge, instead of guessing which
-- direct-page byte "is" the cursor.  Reads only; writes nothing (issue #75).
--
-- probe_fieldheal established the state chain off vargas_doorstep.mss:
--   $05 main menu (Item on row 0) -A-> $08 item list -A-> $19 -A-> $70,
-- and that an A in $70 consumed a TONIC (slot 0) and healed EDGAR +50 --
-- i.e. neither the item row nor the target row followed DP $4B, which stayed
-- 00 through all of it.  gen_sabin_train's shop notes say MoveCursor's own
-- row cell is DP $4E; that is a lead, not a fact, for these windows.
--
-- So: snapshot direct page $00-$FF (plus the menu's $1D00-$1DFF scratch)
-- before and after ONE down press in each window, and print every byte that
-- moved.  The cell that counts 0,1,2 with the highlight is the cursor.
--
-- Run it directly:
--   OT6_KEEP_RUNS=1 OT6_NO_PUBLISH=1 tools/tests/run.sh tools/tests/probe_fieldcells.lua
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_doorstep.mss.lua"

local ZMENUSTATE = 0x26

local RANGES = { { 0x0000, 0x00ff }, { 0x1d00, 0x1dff } }

local function snapshot()
  local s = {}
  for _, r in ipairs(RANGES) do
    for a = r[1], r[2] do s[a] = H.readByte(a) end
  end
  return s
end

local function diff(tag, a, b)
  local hits = {}
  for _, r in ipairs(RANGES) do
    for addr = r[1], r[2] do
      if a[addr] ~= b[addr] then
        hits[#hits + 1] = string.format("$%04X %02X->%02X",
          addr, a[addr], b[addr])
      end
    end
  end
  H.log(string.format("[%s] state=%02X changed: %s", tag,
    H.readByte(ZMENUSTATE),
    #hits == 0 and "(nothing)" or table.concat(hits, "  ")))
end

local before = nil
local function mark()
  return H.call(function() before = snapshot() end)
end
local function report(tag)
  return H.call(function() diff(tag, before, snapshot()) end)
end

local function settle(n)
  local i = 0
  return H.driveUntil(function() i = i + 1; return i > n end, n + 120, {
    H.call(function() H.setPad({}) end),
  }, "settle")
end

local function edge(btn, n)
  return H.cond(function() return true end, {
    H.pressButtons({ btn }, 4), H.release(), settle(n or 60),
  })
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

H.run({ maxFrames = 60000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 600, "field control", 5),
  H.call(function() H.log("roster: " .. roster()) end),

  edge("x", 150),
  H.call(function()
    H.log(string.format("main menu state=%02X", H.readByte(ZMENUSTATE)))
  end),

  -- the main menu's own cursor first: a known-good control for the method
  mark(), edge("down", 60), report("main menu, one DOWN"),
  edge("up", 60),

  -- into the item list
  edge("a", 150),
  H.call(function()
    H.log(string.format("item list state=%02X", H.readByte(ZMENUSTATE)))
  end),
  mark(), edge("down", 60), report("item list, one DOWN"),
  mark(), edge("down", 60), report("item list, second DOWN"),
  mark(), edge("up", 60),   report("item list, one UP"),

  -- window after the first A
  edge("a", 150),
  H.call(function()
    H.log(string.format("after A#1 state=%02X", H.readByte(ZMENUSTATE)))
  end),
  mark(), edge("down", 60), report("A#1 window, one DOWN"),
  mark(), edge("right", 60), report("A#1 window, one RIGHT"),

  -- window after the second A
  edge("a", 150),
  H.call(function()
    H.log(string.format("after A#2 state=%02X", H.readByte(ZMENUSTATE)))
  end),
  mark(), edge("down", 60), report("A#2 window, one DOWN"),
  mark(), edge("down", 60), report("A#2 window, second DOWN"),
  mark(), edge("right", 60), report("A#2 window, one RIGHT"),

  -- confirm and see who moved
  H.call(function() H.log("before confirm: " .. roster()) end),
  edge("a", 250),
  H.call(function()
    H.log("after confirm: " .. roster())
    H.log(string.format("state=%02X", H.readByte(ZMENUSTATE)))
    H.screenshot("cells_after_confirm")
  end),
})
