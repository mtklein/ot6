-- probe_cover.lua -- does vanilla's CoverEffect commit on a staged fixture?
-- MODE 3: the attacker is a MUDDLED ally with a Fight-only command list
-- (battle_runic's idiom), so the swings come on a character ATB we control
-- instead of monster AI.  Reports the CoverEffect/Check/Set/commit funnel plus
-- the frame distance from a commit to the next damage numeral.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local TRUE_KNIGHT, STOP, MUDDLE, MAGITEK = 0x40, 0x10, 0x20, 0x08
local knight, victim, attacker = nil, nil, nil
local msPresent = {}

local function hp(s) return H.readWord(0x3BF4 + s * 2) end
local function alive(s) return H.readByte(0x3AA0 + s * 2) % 2 == 1 end

local function pinField()
  if not knight then return end
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      H.writeWord(0x3C1C + s * 2, 3000)
      H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) & ~MAGITEK & 0xFF)
      if s == attacker then
        H.writeWord(0x3BF4 + s * 2, 2000)
        H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) | MUDDLE)
        H.writeByte(0x202E + s * 12, 0x00)          -- Fight, alone
        H.writeByte(0x2031 + s * 12, 0xFF)
        H.writeByte(0x2034 + s * 12, 0xFF)
        H.writeByte(0x2037 + s * 12, 0xFF)
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) & ~TRUE_KNIGHT & 0xFF)
      elseif s == victim then
        H.writeWord(0x3BF4 + s * 2, 10)
        H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) | 0x02)  -- near fatal
        H.writeByte(0x3EF8 + s * 2, H.readByte(0x3EF8 + s * 2) | STOP)
        H.writeByte(0x3C58 + s * 2,
          H.readByte(0x3C58 + s * 2) & ~TRUE_KNIGHT & 0xFF)
      elseif s == knight then
        H.writeWord(0x3BF4 + s * 2, 2000)
        H.writeByte(0x3C58 + s * 2, H.readByte(0x3C58 + s * 2) | TRUE_KNIGHT)
        H.writeByte(0x3EF8 + s * 2, H.readByte(0x3EF8 + s * 2) & ~STOP & 0xFF)
        H.writeByte(0x3219 + s * 2, 0x60)
      end
    end
  end
  for _, m in ipairs(msPresent) do
    if H.readWord(0x3BFC + m * 2) ~= 3000 then H.writeWord(0x3BFC + m * 2, 3000) end
    H.writeWord(0x3C24 + m * 2, 3000)
  end
end

local n = { cover = 0, check = 0, set = 0, commit = 0 }
local seen, commitF, numeralF = {}, {}, {}
local cycle = 0
local lastCtr = nil

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    local live = {}
    for s = 0, 3 do if alive(s) and hp(s) > 0 then live[#live + 1] = s end end
    attacker, victim, knight = live[1], live[2], live[3]
    H.assertEq(knight ~= nil, true, "three live characters")
    H.log(string.format("attacker=%d victim=%d knight=%d monsters=%d",
      attacker, victim, knight, #msPresent))
    pinField()
    local ce, cc, sc = H.sym("CoverEffect"), H.sym("CheckCoverTarget"),
                       H.sym("SetCoverTarget")
    emu.addMemoryCallback(function()
      n.cover = n.cover + 1
      if n.cover <= 10 then
        seen[#seen + 1] = string.format("COV f%d b2=$%02x b8=$%04x",
          H.frame, H.readByte(0x00B2), H.readWord(0x00B8))
      end
    end, emu.callbackType.exec, ce, ce)
    emu.addMemoryCallback(function()
      n.check = n.check + 1
      if n.check <= 10 then
        local x = emu.getState()["cpu.x"] & 0xff
        seen[#seen + 1] = string.format(
          "  CHK f%d x=$%02x st12=$%04x st34=$%04x hp=%d f2=%d",
          H.frame, x, H.readWord(0x3EE4 + x), H.readWord(0x3EF8 + x),
          H.readWord(0x3BF4 + x), H.readWord(0x00F2))
      end
    end, emu.callbackType.exec, cc, cc)
    emu.addMemoryCallback(function()
      n.set = n.set + 1
      local f4, f8 = H.readByte(0x00F4), H.readByte(0x00F8)
      local y = emu.getState()["cpu.y"] & 0xff
      if f4 ~= 0xff and y == f8 then
        n.commit = n.commit + 1
        commitF[#commitF + 1] = { f = H.frame, blocker = f4 }
      end
      if n.set <= 10 then
        seen[#seen + 1] = string.format("  SET f%d f4=$%02x f8=$%02x y=$%02x",
          H.frame, f4, f8, y)
      end
    end, emu.callbackType.exec, sc, sc)
    emu.addEventCallback(function()
      pinField()
      local c = H.readByte(0x632E)
      if lastCtr ~= nil and c ~= lastCtr then numeralF[#numeralF + 1] = H.frame end
      lastCtr = c
    end, emu.eventType.startFrame)
  end),
  -- SERVICE FOREIGN MENUS.  A ready character's open menu parks the whole
  -- action queue (battle_runic's measurement, and probe_cover MODE 3's first
  -- run: menu=$01 for 20000 frames, cov=0).  Never the knight's own menu.
  H.repeatN(400, {
    H.call(function()
      cycle = cycle + 1
      if cycle % 25 == 0 then
        local atb, st3 = {}, {}
        for e = 0, 0x12, 2 do
          atb[#atb + 1] = string.format("%02x", H.readByte(0x3219 + e))
          st3[#st3 + 1] = string.format("%02x", H.readByte(0x3EF8 + e))
        end
        H.log(string.format("f%d menu=$%02x actor=%d cov=%d set=%d COMMIT=%d "
          .. "atb=%s st3=%s hp=%d/%d/%d turn=%d stop=$%02x wait=$%02x pres=%d%d",
          H.frame, H.readByte(0x7BCA), H.readByte(0x62CA),
          n.cover, n.set, n.commit,
          table.concat(atb, " "), table.concat(st3, " "),
          hp(0), hp(1), hp(2), H.readByte(0x3A3E),
          H.readByte(0x2F41), H.readByte(0x3A8F),
          H.readByte(0x3AA8 + msPresent[1] * 2) % 2,
          H.readByte(0x3AA8 + msPresent[2] * 2) % 2))
      end
      if H.readByte(0x7BCA) ~= 0 and H.readByte(0x62CA) ~= knight then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(13),
  }),
  H.call(function()
    for i = 1, math.min(#seen, 40) do H.log(seen[i]) end
    H.log(string.format("TOTAL cover=%d check=%d set=%d commit=%d", n.cover,
      n.check, n.set, n.commit))
    for i = 1, math.min(#commitF, 8) do
      local c = commitF[i]
      local nxt = nil
      for _, f in ipairs(numeralF) do
        if f >= c.f then nxt = f break end
      end
      H.log(string.format("commit f%d blocker=$%02x -> next numeral %s (+%s)",
        c.f, c.blocker, tostring(nxt), nxt and tostring(nxt - c.f) or "?"))
    end
  end),
})
