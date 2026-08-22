-- probe_iaf_fight.lua -- INSTRUMENTATION (#132): is the IAF gauntlet survivable
-- at the routed levels (L15-17)? Drives from the deck fixture through the
-- party-select, then FIGHTS the whole auto-chain (6x battle 126 -> Ultros4 ->
-- AirForce) with the tactical driver until the FC loads (map 394 = survived) or
-- a Game Over fires (loss). Reports each battle's formation and party HP.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function idx() return H.readByte(0x4b) + H.readByte(0x4a) + H.readByte(0x5a) end
local function charAt(i) return rd(0x7e9d89 + i) end
local function grpCount() local n=0; for i=0,3 do if rd(0x7e9d99+i)~=0xFF then n=n+1 end end; return n end
local function firstEmptyGroupSlot() for _,i in ipairs({0x10,0x11,0x12,0x13}) do if charAt(i)==0xFF then return i end end end
local phase = 0
local function tap(btn) phase=(phase+1)%9; H.setPad(phase<3 and {btn} or {}) end
local function hpLine()
  local p = H.partyHp and H.partyHp() or {}
  local t = {}
  for _, v in ipairs(p) do t[#t+1] = tostring(v) end
  return table.concat(t, "/")
end
local F = H.newFightDriver("IAF", { tactical = true, boost = true, bank = 3, items = true, healPercent = 50 })
local seenBattles, lastActive, wipeHold = 0, false, 0
H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/iaf_deck.mss.lua"),
  H.waitFrames(4),
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "a" }, 4), H.waitFrames(20),
  H.driveUntil(function() local s=H.readByte(0x26); return s>=0x2c and s<=0x2f end, 1200, {
    H.call(function() H.setPad(H.dialogWaiting() and (H.frame%16<4 and {"a"} or {}) or {}) end)
  }, "party-select"),
  -- build a 3-char group
  H.driveUntil(function() return grpCount()>=3 end, 3000, {
    H.call(function()
      local s=H.readByte(0x26)
      if s==0x2d then
        if H.readByte(0x4a)~=0 then tap("up")
        elseif charAt(idx())==0xFF then tap("right") else tap("a") end
      elseif s==0x2e then
        if H.readByte(0x4a)~=0x10 then tap("down")
        else local tgt=firstEmptyGroupSlot()
          if not tgt then tap("a") else
            local cc,cr=(idx()>>1)&1, idx()&1; local tc,tr=(tgt>>1)&1, tgt&1
            if cc<tc then tap("right") elseif cc>tc then tap("left")
            elseif cr<tr then tap("down") elseif cr>tr then tap("up") else tap("a") end
          end
        end
      else tap("b") end
    end)
  }, "3-char group"),
  H.call(function()
    local g={} for i=0,3 do local c=rd(0x7e9d99+i); if c~=0xFF then g[#g+1]=string.format("$%02x",c) end end
    H.log("party formed: " .. table.concat(g, " "))
  end),
  -- confirm -> IAF, then fight the whole chain
  H.driveUntil(function()
    -- terminal: FC reached (survived), Game Over (loss), or a functional wipe
    -- (fewer than 2 alive for a sustained stretch -- the IAF picks off a
    -- limping party across timer waves without ever all-dying at once).
    if H.gameOverFired and H.gameOverFired > 0 then return true end
    if (H.readWord(0x1f64) & 0x3ff) == 394 then return true end
    local alive = 0
    for _, v in ipairs(H.partyHp and H.partyHp() or {}) do if v > 0 then alive = alive + 1 end end
    if alive < 2 and not H.battleActive() then
      wipeHold = (wipeHold or 0) + 1
    else wipeHold = 0 end
    return (wipeHold or 0) >= 300
  end, 36000, {
    H.call(function()
      local active = H.battleActive()
      if active and not lastActive then
        seenBattles = seenBattles + 1
        local f = H.formationWords and H.formationWords() or {}
        H.log(string.format("  [battle %d] f%d species=%s hp=%s", seenBattles, H.frame,
          table.concat({f[1] or "?", f[2] or "?", f[3] or "?"}, ","), hpLine()))
      end
      lastActive = active
      local s = H.readByte(0x26)
      if active or H.battleLoadStarted() then F.frame()
      elseif s == 0x2d then tap("start")               -- confirm the party
      elseif s == 0x2e or s == 0x2f then tap("b")
      elseif H.dialogWaiting() then H.setPad(H.frame % 8 < 4 and { "a" } or {})  -- ride cutscenes
      else H.setPad({}) end                            -- wait out the IAF timers
    end)
  }, "IAF chain -> FC or GameOver"),
  H.call(function()
    local won = (H.readWord(0x1f64) & 0x3ff) == 394
    local how = won and "SURVIVED to the FC"
      or ((H.gameOverFired or 0) > 0 and "LOST (Game Over)" or "LOST (party wiped by attrition)")
    H.log(string.format("RESULT: %s after %d battles; map=%d hp=%s gameOver=%d",
      how, seenBattles, H.readWord(0x1f64) & 0x3ff, hpLine(), H.gameOverFired or 0))
    H.screenshot("iaf_fight_result")
  end),
  H.logStep(function() return "done" end),
})
