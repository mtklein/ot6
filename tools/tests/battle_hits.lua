-- battle_hits: a boosted Fight swings again — +2 swings per pending BP
-- (one real hit per BP for a one-weapon character; a genji pair swings
-- both hands again). The magitek party has no Fight command, so the test
-- forces the vanilla auto-Fight path: rewrite every command list to
-- Fight-only and berserk the party (RandCharAction reads the LIVE $202e
-- list -> Cmd_00 -> FightAttack, no menus pausing wait-mode atb).
-- The character whose menu is open when berserk lands keeps replaying its
-- stale menu-staged action (C1 staging), so the test subject is a
-- DIFFERENT slot — one that never had a menu up.
--   asserts: $3a70 gets the boosted swing count 1 + 2*pending exactly
--   once (only the subject has pending), never more, and the boost is
--   consumed with no regen after the swing.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local function bp(slot) return H.readByte(0x3e9c + slot*2) end
local subject, bp0
local swings, swingRef = {}, nil

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.call(function()
    local menuHolder = H.readByte(0x62ca)
    subject = (menuHolder + 1) % 3
    bp0 = bp(subject)
    H.log(string.format("menu holder slot %d, test subject slot %d, bp0 %d",
      menuHolder, subject, bp0))
    H.writeWord(0x3C00, 500); H.writeWord(0x3C02, 500)  -- guards survive
    for slot = 0, 3 do                    -- entries are [cmd,d,d] x4 = 12/char
      H.writeByte(0x202e + slot*12, 0x00)
      H.writeByte(0x2031 + slot*12, 0xff)
      H.writeByte(0x2034 + slot*12, 0xff)
      H.writeByte(0x2037 + slot*12, 0xff)
      local a = 0x3ee5 + slot*2
      H.writeByte(a, H.readByte(a) | 0x10)
    end
  end),
  -- the subject may have an action pre-queued by the battle-entry mash;
  -- let their first action (queued beam or clean fight) flush unboosted
  H.waitUntil(function() return bp(subject) ~= bp0 end, 8000, "first action flushed", 10),
  H.call(function()
    -- magitek status routes every berserk/confused action to a random
    -- beam (RandMagitekAction) no matter the command list — clear it so
    -- berserk picks Fight from the live list
    local st1 = 0x3ee4 + subject*2
    H.writeByte(st1, H.readByte(st1) & 0xf7)
    H.writeByte(0x3e9c + subject*2, 3)    -- bp to spend
    H.writeByte(0x3e9d + subject*2, 2)    -- boost their next auto-Fight
    swingRef = emu.addMemoryCallback(function(addr, value)
      swings[#swings + 1] = value
    end, emu.callbackType.write, 0x7e3a70, 0x7e3a70)
  end),
  H.waitUntil(function() return pend(subject) == 0 end, 8000, "boosted fight lands", 10),
  H.waitFrames(120),
  H.call(function()
    emu.removeMemoryCallback(swingRef, emu.callbackType.write, 0x7e3a70, 0x7e3a70)
    local n5, maxv, vals = 0, -1, {}
    for _, v in ipairs(swings) do
      if v == 5 then n5 = n5 + 1 end
      if v > maxv and v ~= 0xff then maxv = v end   -- ff = the dec-past-zero wrap
      vals[#vals + 1] = string.format("%02x", v)
    end
    H.log("swing-count write values: " .. table.concat(vals, " "))
    H.assertEq(n5, 1, "exactly one boosted fight queued 1+2*2 swings")
    H.assertEq(maxv, 5, "and nothing queued more")
    H.assertEq(bp(subject), 1, "boost consumed (3-2), regen skipped")
    H.assertEq(pend(subject), 0, "pending cleared")
    H.screenshot("hits_landed")
  end),
})
