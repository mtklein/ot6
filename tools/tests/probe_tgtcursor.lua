-- probe_tgtcursor.lua -- read-only: enumerate the battle target cursor's
-- monster-side hover positions on a group-80 formation (mrf_entry), pressing
-- one direction at a time from target select and logging masks $7B7E/$7B7D.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/mrf_entry.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_TGT = 0x05, 0x38

local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot * 12 + r * 3) == cmd then return r end
  end
  return nil
end

-- latch the blinking masks across a dwell
local function dwell(n)
  local mon, chr = 0, 0
  return H.repeatN(n, {
    H.call(function()
      local m, c = H.readByte(0x7B7E), H.readByte(0x7B7D)
      if m ~= 0 then mon = m end
      if c ~= 0 then chr = c end
      H.vars.mon, H.vars.chr = mon, chr
    end),
    H.waitFrames(1),
  })
end

local function press(dir)
  return H.repeatN(1, {
    H.pressButtons({ dir }, 4),
    dwell(20),
    H.call(function()
      H.log(string.format("  press %-5s -> mon=$%02x chr=$%02x st=$%02x",
        dir, H.vars.mon, H.vars.chr, H.readByte(MSTATE)))
      H.vars.mon, H.vars.chr = 0, 0
    end),
  })
end

H.run({ maxFrames = 60000 }, {
  H.loadState(STATE),
  H.waitFrames(60),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    1800, "field control", 5),
  H.call(function()
    H.vars.x0, H.vars.y0 = H.fieldX(), H.fieldY()
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.call(function()
      if H.battleLoadStarted() or not H.hasControl() then H.setPad({}); return end
      if H.fieldY() == H.vars.y0 then H.setPad({ up = true })
      else H.setPad({ down = true }) end
    end),
  }, "a factory encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.call(function()
    local mons = {}
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
        mons[#mons + 1] = string.format("m%d=$%04x", m, H.readWord(0x57C0 + m * 2))
      end
    end
    H.log("[formation] " .. table.concat(mons, " "))
  end),
  -- wait for any command window, go to its Fight row, open target select
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 9000, {
    H.waitFrames(1),
  }, "a command window opens"),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.readByte(MSTATE) == ST_TGT end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if ph >= 4 then H.setPad({}); return end
        local act = H.readByte(ACTOR) & 3
        local st = H.readByte(MSTATE)
        if st == ST_CMD then
          local want = cmdRowOf(act, 0x00)
          local cur = H.readByte(CMDROW + act) & 3
          if cur == want then H.setPad({ a = true })
          elseif cur < want then H.setPad({ down = true })
          else H.setPad({ up = true }) end
        else
          H.setPad({})
        end
      end),
      H.waitFrames(1),
    }, "target select opens (Fight)")
  end)(),
  H.call(function() H.setPad({}) end),
  dwell(20),
  H.call(function()
    H.log(string.format("[open] initial hover mon=$%02x chr=$%02x",
      H.vars.mon, H.vars.chr))
    H.vars.mon, H.vars.chr = 0, 0
  end),
  -- single presses, each direction several times, logging the latched mask
  press("left"), press("left"), press("left"),
  press("down"), press("down"), press("down"),
  press("right"), press("right"), press("right"),
  press("up"), press("up"), press("up"),
  press("left"), press("down"), press("left"), press("up"),
  press("down"), press("down"), press("up"), press("right"),
  -- cancel out with no action queued
  H.pressButtons({ "b" }, 4), H.waitFrames(20),
  H.pressButtons({ "b" }, 4), H.waitFrames(20),
  H.logStep(function() return "tgtcursor probe complete" end),
})
