-- probe_iaf_fight3.lua -- the IAF gauntlet with the tuned bolt kit (#133).
--
-- probe_iaf_fight asked the question at the routed L15-17 from iaf_deck;
-- this asks it from wob_grind_done.mss (the leveled party on foot beside
-- the Blackjack parked at the Chimera pocket): walk back onto the ship,
-- ride the deck flow to the party-select, and fight the chain with the
-- grinders holding the route: Terra $00 + Locke $01 (the two ThunderBlades,
-- the bolt plan) and Strago $07
-- at L21/L22/L21 (Celes stayed L15 on the bench, so the original
-- Terra/Celes/Relm three would test a party nobody routed).
-- Everything from the deck onward is probe_iaf_fight's proven drive.
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
local F = H.newFightDriver("IAF3", { tactical = true, boost = true, bank = 3, items = true, healPercent = 50,
  magic = { [0x07] = { spell = 2 } } })  -- Strago casts Bolt (Ramuh grant)
local seenBattles, lastActive, wipeHold = 0, false, 0
local TARGETS = { 0x00, 0x01, 0x07 }
local sweep = 0
local dirMap = {}                 -- "inc"/"dec" -> learned dpad button
local lastIdx, lastBtn, probeI, probeN = nil, nil, 0, 0
local function inGroup(c)
  for i = 0, 3 do if rd(0x7e9d99 + i) == c then return true end end
  return false
end
local function nextTarget()
  for _, c in ipairs(TARGETS) do if not inGroup(c) then return c end end
  return nil
end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
H.run({ maxFrames = 100000 }, flatten({
  H.loadState("build/states/wob_grind_run.mss.lua"),
  H.waitFrames(8),
  -- the bolt kit: Ramuh + Earrings x2 on Strago, RunningShoes on Terra,
  -- Sniper Sight on Locke (all field-menu drives, no state writes)
  H.equipEsper(function() return (H.readByte(0x1850 + 7) >> 3) & 3 end, 0,
    { tag = "Ramuh onto STRAGO" }),
  H.equipLoadout(7, { {4, 0xc3}, {5, 0xc3} }, { tag = "Earrings x2 STRAGO" }),
  H.cond(function() return H.invCountOf(0xba) > 0 end, {
    H.equipLoadout(0, { {4, 0xba} }, { tag = "RunningShoes TERRA" }),
  }, {}),
  H.equipLoadout(1, { {4, 0xe3} }, { tag = "Sniper Sight LOCKE" }),
  -- walk onto the parked ship: $1f62 = airship xy (set by LandAirship)
  H.call(function()
    H.log(string.format("party (%d,%d), airship (%d,%d)",
      H.worldX(), H.worldY(),
      H.readByte(0x1f62), H.readByte(0x1f63)))
  end),
  H.worldNavTo(function() return H.readByte(0x1f62) end,
               function() return H.readByte(0x1f63) end,
    { maxFrames = 8000, playBattles = "tactical",
      arrive = function() return not H.worldMode() end }),
  -- boarding = an A edge while standing on the ship tile (move.asm@204e:
  -- $08 bit7 edge).  With $01BA clear (it is, everywhere in this chain)
  -- boarding goes STRAIGHT to flight -- no deck.  The deck is the X
  -- button in flight: ctrl.asm@6ead, an X edge with $19==0 runs
  -- VehicleEvent_00 (ca/0068, "blackjack deck").
  H.driveUntil(function() return rd(0x20) == 1 end, 1200,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "aboard (vehicle mode)"),
  H.waitFrames(150),                    -- flight settle, as after Lift-off
  H.driveUntil(function() return not H.worldMode() end, 1500,
    { H.call(function() H.setPad(H.frame % 30 < 4 and { "x" } or {}) end) },
    "the deck map loads (X in flight)"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("aboard: map=%d field=(%d,%d)",
      H.mapId() & 0x3ff, H.fieldX(), H.fieldY()))
  end),
  -- probe_iaf_fight's proven deck -> party-select -> IAF drive, except the
  -- walk targets the helm STEP-TRIGGER tile itself, (14,6) (event_trigger
  -- map 6: {14,6} -> _caf532): iaf_deck happened to park the party there,
  -- this boarding lands at (16,6), and (15,8) fires nothing.
  H.navTo(14, 6, { maxFrames = 2000, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "a" }, 4), H.waitFrames(20),
  H.driveUntil(function() local s=H.readByte(0x26); return s>=0x2c and s<=0x2f end, 1200, {
    H.call(function() H.setPad(H.dialogWaiting() and (H.frame%16<4 and {"a"} or {}) or {}) end)
  }, "party-select"),
  H.driveUntil(function() return grpCount()>=3 end, 4000, {
    H.call(function()
      if H.frame % 40 == 0 then H.log(string.format(
        "  build f%d 26=%02X 4a=%02X 4e=%02X idx=%02X char=%02X val=%02X want=%s grp=%d",
        H.frame, H.readByte(0x26), H.readByte(0x4a), H.readByte(0x4e), idx(),
        charAt(idx()), rd(0x7eac8d + idx()), tostring(nextTarget()), grpCount())) end
      local s=H.readByte(0x26)
      if s==0x2d then
        if H.readByte(0x4a)~=0 then tap("up")   -- group exit (proven in probe_iaf)
        else
          -- Closed-loop steering with LEARNED buttons: the reserve list is
          -- readable ($7e9d89+i, compacting as chars are placed), but which
          -- dpad button moves the cursor which way is not worth guessing
          -- (four assumed layouts measured wrong).  Try buttons in rotation,
          -- watch idx, and remember what worked.
          local t = nil
          for i = 0, 15 do
            local c = charAt(i)
            if (c==0x00 or c==0x01 or c==0x07) and not inGroup(c)
               and rd(0x7eac8d + i) < 0x80 then t = i; break end
          end
          local cur = idx()
          if not t then tap("b")
          elseif cur == t then tap("a")
          else
            local want = (cur < t) and "inc" or "dec"
            if lastIdx ~= nil and cur ~= lastIdx and lastBtn then
              dirMap[(cur > lastIdx) and "inc" or "dec"] = lastBtn
            end
            local btn = dirMap[want]
            if not btn then
              probeI = (probeI or 0)
              btn = ({"down","up","right","left"})[(probeI % 4) + 1]
              probeN = (probeN or 0) + 1
              if probeN % 14 == 0 then probeI = probeI + 1 end
            end
            lastIdx, lastBtn = cur, btn
            tap(btn)
          end
        end
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
  -- per-wave loop with BETWEEN-WAVE CARE: field timers pause while a
  -- menu is open (the vanilla IAF design intends menu heals between
  -- waves), so after each fight ends, heal via fieldCare before the
  -- next wave lands.  12 rounds covers 6x126 + Ultros/Chupon + AirForce
  -- with slack.
  (function()
    local function ended()
      if H.gameOverFired and H.gameOverFired > 0 then return true end
      if (H.readWord(0x1f64) & 0x3ff) == 394 then return true end
      local alive = 0
      for _, c in ipairs(H.partyMembers()) do
        if H.charHp(c) > 0 then alive = alive + 1 end
      end
      if alive < 2 and not H.battleActive() then
        wipeHold = (wipeHold or 0) + 1
      else wipeHold = 0 end
      return (wipeHold or 0) >= 300
    end
    local out = {}
    for w = 1, 12 do
      out[#out+1] = H.cond(function() return not ended() end, {
        -- one wave: wait for it, fight it
        H.driveUntil(function()
          return ended() or (seenBattles >= w and not H.battleActive()
            and not H.battleLoadStarted())
        end, 20000, {
          H.call(function()
            local active = H.battleActive()
            if active and not lastActive then
              seenBattles = seenBattles + 1
              local f = H.formationWords and H.formationWords() or {}
              H.log(string.format("  [battle %d] f%d species=%s hp=%s", seenBattles, H.frame,
                table.concat({f[1] or "?", f[2] or "?", f[3] or "?"}, ","), hpLine()))
            end
            if not active and lastActive then lastActive = false; return end
            lastActive = active
            local s = H.readByte(0x26)
            if active or H.battleLoadStarted() then F.frame()
            elseif s == 0x2d then tap("start")
            elseif s == 0x2e or s == 0x2f then tap("b")
            elseif H.dialogWaiting() then H.setPad(H.frame % 8 < 4 and { "a" } or {})
            else H.setPad({}) end
          end)
        }, "wave " .. w),
        H.waitFrames(20),
        -- the care window: menu-heal while the wave timer is paused
        -- soft pre-open: the inter-wave windows are short (256-512
        -- frame timers) and the wave-6 teaser blocks menus, so try the
        -- menu for <=400 frames and yield to any landing battle; only
        -- hand fieldCare a menu that is already open ($26==0x05).
        (function()
          local t2 = 0
          return H.cond(function()
            t2 = 0
            return not ended() and seenBattles < 8
              and not H.battleActive() and not H.battleLoadStarted()
          end, {
            H.driveUntil(function()
              t2 = t2 + 1
              return t2 >= 400 or H.readByte(0x26) == 0x05
                or H.battleActive() or H.battleLoadStarted()
            end, 800, {
              H.call(function()
                if H.battleLoadStarted() then H.setPad({}); return end
                H.setPad(t2 % 12 < 4 and { "x" } or {})
              end),
            }, "menu pre-open " .. w),
            H.release(),
            H.cond(function() return H.readByte(0x26) == 0x05 end,
              { H.fieldCare({ tag = "iaf-care " .. w, threshold = 0.85 }) }, {}),
            -- fieldCare no-ops when healthy and leaves our pre-opened
            -- menu up -- which freezes the FIELD_ONLY wave timers.
            -- Always close it.
            (function()
              local t3 = 0
              return H.driveUntil(function()
                t3 = t3 + 1
                return t3 >= 600 or H.readByte(0x26) ~= 0x05
              end, 900, {
                H.call(function() H.setPad(t3 % 12 < 4 and { "b" } or {}) end),
              }, "menu close " .. w)
            end)(),
            H.release(),
            H.waitFrames(20),
          }, {})
        end)(),
        -- after the six waves (ambush + 5 = battle 7), Ultros is armed
        -- by WALKING to the deck's right edge (map 10 triggers (22,5-7)
        -- -> _ca5a16, gated on the teaser's $01F0); step off and back on
        -- each round until it fires
        H.cond(function()
          return not ended() and seenBattles == 7 and not H.battleActive()
            and not H.battleLoadStarted() and (H.mapId() & 0x3ff) == 10
        end, {
          H.navTo(20, 6, { maxFrames = 2000, arrive = function()
            return H.battleLoadStarted() or H.battleActive() end }),
          H.navTo(22, 6, { maxFrames = 2000, arrive = function()
            return H.battleLoadStarted() or H.battleActive() end }),
          H.waitFrames(60),
        }, {}),
      }, {})
    end
    return out
  end)(),
  H.call(function()
    local won = (H.readWord(0x1f64) & 0x3ff) == 394
    local how = won and "SURVIVED to the FC"
      or ((H.gameOverFired or 0) > 0 and "LOST (Game Over)" or "LOST (party wiped by attrition)")
    H.log(string.format("RESULT: %s after %d battles; map=%d hp=%s gameOver=%d",
      how, seenBattles, H.readWord(0x1f64) & 0x3ff, hpLine(), H.gameOverFired or 0))
    H.screenshot("iaf2_result")
  end),
  H.cond(function() return (H.readWord(0x1f64) & 0x3ff) == 394 end, {
    H.waitFrames(60),
    H.saveState("fc_land.mss"),
  }, {}),
  H.logStep(function() return "done" end),
}))
