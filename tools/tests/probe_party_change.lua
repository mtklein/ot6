-- probe_party_change.lua -- from the airship lounge (wob_lounge.mss),
-- talk to a roster character, answer "Change party members?" Yes, and
-- swap RELM out for MOG in the $26 swap UI (#133 Water Rondo prep).
-- Heavily instrumented: the previous sweep sat 20k frames with no
-- dialog, so log control/menu/dialog state while sweeping.
-- Saves wob_mog_party.mss.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
-- $26 is only meaningful while the menu program runs -- on the field it
-- idles at a stale value (measured 0x2F in the lounge).  The menu owns
-- input, so require control to be gone, no dialog, and the state range,
-- debounced a few frames so scene transitions don't misfire it.
local menuStreak = 0
local function menuState()
  local s = H.readByte(0x26)
  local live = (not H.hasControl()) and (not H.dialogWaiting())
    and s >= 0x2c and s <= 0x2f
  menuStreak = live and menuStreak + 1 or 0
  return menuStreak >= 10
end
local function idx() return H.readByte(0x4b) + H.readByte(0x4a) + H.readByte(0x5a) end
local function charAt(i) return rd(0x7e9d89 + i) end
local function mogSeated() return (H.readByte(0x1850 + 10) & 0x07) ~= 0 end
local function firstEmptyGroupSlot()
  for _, i in ipairs({ 0x10, 0x11, 0x12, 0x13 }) do
    if charAt(i) == 0xFF then return i end
  end
  return nil
end
local function relmGroupSlot()
  for _, i in ipairs({ 0x10, 0x11, 0x12, 0x13 }) do
    if charAt(i) == 8 then return i end
  end
  return nil
end

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/wob_lounge.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("boot: map %d (%d,%d) ctrl=%s dlg=%s $26=%02X",
      H.mapId() & 0x1ff, H.fieldX(), H.fieldY(),
      tostring(H.hasControl()), tostring(H.dialogWaiting()),
      H.readByte(0x26)))
  end),
  (function()
    local phase = 0
    local function tap(btn) phase = (phase + 1) % 9
      H.setPad(phase < 3 and { [btn] = true } or {}) end
    local function tapB(btn) phase = (phase + 1) % 9
      H.setPad(phase < 3 and { btn } or {}) end
    local t, scanDir, scanT, held, ex = 0, "right", 0, nil, nil
    local w = { st = 0, di = 1, mv = 1, shuffle = 0 }
    local dirs = { "down", "left", "right", "up" }
    return H.driveUntil(function()
      return mogSeated() and H.hasControl() and not H.dialogWaiting()
    end, 30000, {
      H.call(function()
        t = t + 1
        if t % 900 == 0 then
          H.log(string.format("  sweep t=%d (%d,%d) ctrl=%s dlg=%s $26=%02X grp=%02X,%02X,%02X,%02X mog=%02X",
            t, H.fieldX(), H.fieldY(), tostring(H.hasControl()),
            tostring(H.dialogWaiting()), H.readByte(0x26),
            charAt(0x10), charAt(0x11), charAt(0x12), charAt(0x13),
            H.readByte(0x1850 + 10)))
        end
        if t == 3000 or t == 12000 then H.screenshot("sweep" .. t) end
        if menuState() then
          -- the "Change party?" menu opens with the group RESET (all
          -- $FF), so all four seats get filled: TERRA, LOCKE, STRAGO,
          -- MOG.  Cursor layout is not assumed: an explorer taps a
          -- direction and rotates whenever the cursor signature
          -- (idx+$4a) stops changing.
          local WANT = { 0x0A, 0x00, 0x01, 0x07 }   -- Mog first
          local function grpCount()
            local n = 0
            for _, i in ipairs({ 0x10, 0x11, 0x12, 0x13 }) do
              if charAt(i) ~= 0xFF then n = n + 1 end
            end
            return n
          end
          local function inGroup(c)
            for _, i in ipairs({ 0x10, 0x11, 0x12, 0x13 }) do
              if charAt(i) == c then return true end
            end
            return false
          end
          local function nextGoal()
            for _, c in ipairs(WANT) do
              if not inGroup(c) then return c end
            end
            return nil
          end
          local sig = idx() * 256 + H.readByte(0x4a) * 4 + H.readByte(0x5a)
          if ex == nil then ex = { di = 1, lastSig = sig, still = 0 } end
          if sig ~= ex.lastSig then ex.lastSig = sig; ex.still = 0
          else ex.still = ex.still + 1 end
          local exDirs = { "up", "left", "right", "down" }
          -- deterministic steering per party.asm MenuState_2d/_c371b9:
          -- both reserve and group are 2-wide row-major (right/left +-1,
          -- down/up +-2); DOWN enters the group only from the reserve's
          -- right column ($4e==1), UP leaves it from the group's left
          -- column.  It is a swap-pair UI: A in 2d picks slot 1, A in
          -- 2e on a second cell swaps them (A on the same occupied cell
          -- opens Status -- never do that).
          -- SEEN on screen: the reserve is one horizontal row, the
          -- group one 4-wide row below it.  right/left = +-1 within a
          -- row; down enters the group, up leaves it.
          local function navTo(target)
            if ex.still > 90 then          -- wedged: jiggle out
              ex.di = ex.di % #exDirs + 1
              ex.still = 60
              tap(exDirs[ex.di])
              return
            end
            local cur, ga = idx(), H.readByte(0x4a)
            -- measured geometry: the reserve is an 8-wide 2-row grid
            -- (left dies at idx8's col 0, right dies at idx7's col 7),
            -- rows swap with up/down (+-8); the 4-wide group row sits
            -- below row 1
            if ga == 0x10 and target < 0x10 then tap("up"); return end
            if ga == 0 and target >= 0x10 then tap("down"); return end
            if ga == 0x10 then
              -- the group is the classic 2x2: $10 TL, $11 BL, $12 TR,
              -- $13 BR -- left/right swap columns (+-2), up/down rows
              local cc, cr = (cur - 0x10) >> 1, (cur - 0x10) & 1
              local tc, tr = (target - 0x10) >> 1, (target - 0x10) & 1
              if cc < tc then tap("right") elseif cc > tc then tap("left")
              elseif cr < tr then tap("down") elseif cr > tr then tap("up")
              end
              return
            end
            local crow, ccol = cur >> 3, cur & 7
            local trow, tcol = target >> 3, target & 7
            if ccol < tcol then tap("right")
            elseif ccol > tcol then tap("left")
            elseif crow < trow then tap("down")
            elseif crow > trow then tap("up")
            end
          end
          local function findReserve(c)
            for i = 0, 15 do if charAt(i) == c then return i end end
            return nil
          end
          if t % 300 == 0 then
            local rsv = {}
            for i = 0, 15 do rsv[#rsv+1] = string.format("%02X", charAt(i)) end
            H.log(string.format("  menu $26=%02X idx=%02X $4a=%02X $5a=%02X at=%02X grp=%d rsv=%s",
              H.readByte(0x26), idx(), H.readByte(0x4a), H.readByte(0x5a),
              charAt(idx()) or 0xEE, grpCount(), table.concat(rsv, ",")))
          end
          local s = H.readByte(0x26)
          if s == 0x2d then
            held = nil
            local goal = nextGoal()
            if goal == nil then tapB("start")
            else
              local c = charAt(idx())
              local wanted = false
              for _, wc in ipairs(WANT) do
                if c == wc and not inGroup(wc) then wanted = true end
              end
              if H.readByte(0x4a) == 0 and wanted then
                held = c; tapB("a")
              else
                local tgt = findReserve(goal)
                if tgt == nil then tapB("start")   -- goal vanished: bail
                else navTo(tgt) end
              end
            end
          elseif s == 0x2e then
            -- holding.  If WE didn't grab (a stray A from the dialog
            -- ride picked someone up -- observed holding Relm at menu
            -- open), or the hold has dragged on, cancel with B.
            ex.holdT = (ex.holdT or 0) + 1
            if held == nil or ex.holdT > 900 then
              tapB("b")
            elseif H.readByte(0x4a) == 0x10 and charAt(idx()) == 0xFF then
              tapB("a")
            else
              local tgt = firstEmptyGroupSlot()
              if tgt == nil then tapB("b") else navTo(tgt) end
            end
          else tapB("b") end
          if s ~= 0x2e and ex then ex.holdT = 0 end
          return
        end
        ex = nil
        if H.dialogWaiting() then
          local ph = t % 32
          if ph < 3 then H.setPad({ down = true })
          elseif ph >= 8 and ph < 11 then H.setPad({ "a" })
          else H.setPad({}) end
          return
        end
        if not H.hasControl() then H.setPad({}); return end
        -- anchor near the room center (50,55); a face-tap can step, so
        -- drifting is expected -- walk back whenever >3 tiles out.  The
        -- roster NPCs wander; face-pressing all four ways from the
        -- center reaches whoever wanders adjacent.
        local dx, dy = 50 - H.fieldX(), 55 - H.fieldY()
        if math.abs(dx) + math.abs(dy) > 3 then
          local d = math.abs(dx) >= math.abs(dy)
            and (dx > 0 and "right" or "left")
            or (dy > 0 and "down" or "up")
          H.setPad({ [d] = true })
          return
        end
        w.st = w.st + 1
        local ph = w.st % 90
        if ph < 2 then H.setPad({ [dirs[w.di]] = true })
        elseif ph < 14 then H.setPad({})
        elseif ph < 18 then H.setPad({ "a" })
        elseif ph < 89 then H.setPad({})
        else
          w.di = w.di % #dirs + 1
          H.setPad({})
        end
      end),
    }, "MOG seated")
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("party bytes: mog=%02X relm=%02X",
      H.readByte(0x1850 + 10), H.readByte(0x1850 + 8)))
    H.screenshot("party_changed")
  end),
  H.saveState("wob_mog_party.mss"),
  H.logStep(function() return "done" end),
})
