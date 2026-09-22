-- @manual
-- probe_verbs_boost.lua -- the boost multiplier on the two verbs
-- battle_procboost cannot reach from fc_alcove: Tempest's Wind Slash (a
-- weapon's on-hit spell from its attacker effect, not CheckWeaponMagic) and
-- Relm's Sketch.
--
--   forest_done  CYAN / SHADOW / SABIN in the Phantom Forest.  Tempest is
--                Cyan's katana alone (ItemProp equip mask $8004) and no fixture
--                with Cyan carries one, so one Tempest is written into an empty
--                bag slot (declared in tools/state_write_waivers.txt); the
--                equip is the field menu's (H.equipKit), and the swing, the
--                50% attacker-effect roll and the Wind Slash pass are the
--                ROM's.  Expected: every Wind Slash ($b6 = $65) leaves
--                Ot6BoostDmg unmultiplied.
--   thamasa_done TERRA / LOCKE / STRAGO / RELM on the world map below
--                Thamasa.  Relm's Sketch at boost 3, aimed at a monster whose
--                sketch set holds more than Battle/Special (those run as Fight
--                and are exempt as one): the sketched attack runs with $b5 =
--                GetCmdForAI of it under the queued command $0d; expected x8.
--                (Esper Mountain's two species sketch only Battle/Special and
--                a no-damage $B1, so ultros_won cannot show it.)
-- Each: pace to a random encounter (running from ones with nothing to aim
-- at), everyone Defends until the actor's bank holds 3, snapshot, then
-- boosted tries at longer idle waits until the case happens.  Every
-- Ot6BoostDmg call the actor makes is logged ($11b0 in and out, $b5/$b6,
-- $3a7c/$3a7d, pending, OT6_WEAPSPELL).

local H = dofile("tools/tests/lib/ot6.lua")

local BOOST = 3
local CYAN, RELM = 0x02, 0x08
local TEMPEST, WIND_SLASH = 0x2E, 0x65
local TRIES, WAIT_STEP = 16, 48

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local ST_CMD, ST_DEF, ST_TGT = 0x05, 0x27, 0x38
local BANK, PEND = 0x3E9C, 0x3E9D
local CMD_FIGHT, CMD_SKETCH = 0x00, 0x0D

local slot, snap, armed, weapspell = nil, nil, nil, nil
local fixture

local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end

local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local ok, ws = pcall(function() return H.sym("OT6_WEAPSPELL") end)
  weapspell = ok and (ws & 0xFFFF) or nil
  local bd = H.sym("Ot6BoostDmg")
  local b0, b1, b2 = bd & 0xFF, (bd >> 8) & 0xFF, (bd >> 16) & 0xFF
  local sites = {}
  for off = 0x020000, 0x02FFFC do
    if H.readRomByte(off) == 0x22 and H.readRomByte(off + 1) == b0
       and H.readRomByte(off + 2) == b1 and H.readRomByte(off + 3) == b2 then
      sites[#sites + 1] = 0xC00000 + off + 4
    end
  end
  H.assertEq(#sites, 2, "Ot6BoostDmg has two call sites in bank $C2")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x ~= slot * 2 then return end
    armed.calls[#armed.calls + 1] = {
      b5 = H.readByte(0xB5), b6 = H.readByte(0xB6), a7c = H.readByte(0x3A7C),
      a7d = H.readByte(0x3A7D), pend = H.readByte(PEND + x),
      ws = weapspell and H.readByte(weapspell) or 0xFF, din = H.readWord(0x11B0) }
  end, emu.callbackType.exec, bd, bd)
  for _, ret in ipairs(sites) do
    emu.addMemoryCallback(function()
      if armed == nil or armed.endF or #armed.calls == 0 then return end
      local c = armed.calls[#armed.calls]
      if c.dout == nil then c.dout = H.readWord(0x11B0) end
    end, emu.callbackType.exec, ret, ret)
  end
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    if (emu.getState()["cpu.x"] & 0xFFFF) == slot * 2 then armed.endF = H.frame end
  end, emu.callbackType.exec, ae, ae)
end

local tick = 0
local function pulse(btn)
  tick = tick + 1
  H.setPad((btn and tick % 12 < 6) and { [btn] = true } or {})
end
local function defendOthers(except)
  if H.readByte(MENU) == 0 then pulse(nil) return end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == except then pulse(nil) return end
  if st == ST_CMD then pulse("right")
  elseif st == ST_DEF then pulse("a")
  else pulse(nil) end
end

local phase, held = "idle", nil
local function decide(c)
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if phase == "boost" then
    if st ~= ST_CMD or a ~= slot then return nil end
    if H.readByte(PEND + slot * 2) < BOOST then return "r" end
    phase = "cmd"
  end
  if phase == "cmd" then
    if st ~= ST_CMD then return nil end
    local want = cmdRow(slot, c.cmd)
    assert(want, c.name .. ": the actor has the command")
    local cur = H.readByte(CMDROW + slot) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    phase = "target"
    return "a"
  end
  if phase == "target" then
    if H.readByte(MENU) == 0 or a ~= slot then phase = "sent" return nil end
    if st == ST_CMD then return "a" end
    if st ~= ST_TGT then return nil end
    if c.target and H.readByte(0x7B7E) ~= (1 << c.target) then
      -- walk the monster cursor to the case's target: across the columns
      -- first, then along them, so either layout is covered
      c.steer = (c.steer or 0) + 1
      local k = c.steer % 10
      return k < 2 and "left" or k < 5 and "up" or k < 8 and "down" or "right"
    end
    c.pendAtConfirm, armed = H.readByte(PEND + slot * 2), c
    phase = "confirmed"
    return "a"
  end
end

local function tryCase(c, n)
  local req, waited, skip = nil, 0, false
  return {
    H.call(function()
      skip = c.hit ~= nil
      if skip then return end
      H.setPad({})
      req = H.requestLoadState(snap.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      if skip then return end
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      c.calls, c.endF, c.wait = {}, nil, (n - 1) * WAIT_STEP
      tick, phase, held, waited = 0, "reach", nil, 0
    end),
    H.driveUntil(function() return skip or phase == "sent" end, 6000 + (n - 1) * WAIT_STEP, {
      H.call(function()
        if phase == "reach" then
          if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD
             and (H.readByte(ACTOR) & 3) == slot then
            H.setPad({})
            waited = waited + 1
            if waited >= c.wait then phase, tick = "boost", 0 end
          else
            defendOthers(slot)
          end
          return
        end
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        if phase == "confirmed" and ph == 11 then phase = "sent" end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, string.format("%s, try %d", c.name, n)),
    H.driveUntil(function() return skip or (c.endF ~= nil and H.frame >= c.endF + 30) end, 6000, {
      H.call(function() defendOthers(slot) end),
    }, c.name .. " resolves, try " .. n),
    H.call(function()
      if skip then return end
      armed = nil
      H.setPad({})
      local parts = {}
      for _, k in ipairs(c.calls) do
        parts[#parts + 1] = string.format("b5=$%02X b6=$%02X 3a7c=$%02X 3a7d=$%02X p%d ws=$%02X %d->%s",
          k.b5, k.b6, k.a7c, k.a7d, k.pend, k.ws, k.din, tostring(k.dout))
      end
      H.log(string.format("[verbs] %s %s try %d (wait %d): pending at confirm %s: %s",
        fixture, c.name, n, c.wait, tostring(c.pendAtConfirm),
        #parts > 0 and table.concat(parts, " | ") or "no Ot6BoostDmg call"))
      if c.done(c) then c.hit = n end
    end),
  }
end

-- a sketch set worth aiming at: anything but Battle ($EE) and Special
-- ($EF), which run as Fight and are exempt as one.  Whether the attack
-- deals damage is read off the try (Ot6BoostDmg's damage in), not guessed.
local function sketchable(atk) return atk ~= 0xEE and atk ~= 0xEF end

local function section(path, char, setup, c)
  local steps = {
    H.call(function()
      snap, slot, armed = nil, nil, nil
      fixture = path:match("([^/]+)%.mss%.lua$")
    end),
    H.loadState(path),
    H.waitFrames(20),
    H.call(function() installObservers() end),
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() or (H.hasControl() and H.tileAligned())
    end, 3000, "control", 5),
  }
  for _, s in ipairs(setup) do steps[#steps + 1] = s end
  -- pace to encounters until one suits the case: any, for a Fight; one with
  -- a monster whose sketch set holds more than Battle/Special, for a Sketch
  -- (the others are left by holding L+R, the engine's own run)
  local st, lane, encounters = "pace", nil, 0
  local WDIRS, wdi, wn, wlast = { "down", "up" }, 1, 0, nil
  local BACK = { left = "right", right = "left", up = "down", down = "up" }
  local sk
  steps[#steps + 1] = H.driveUntil(function() return st == "found" end, 90000, {
    H.call(function()
      if st == "pace" then
        if H.battleLoadStarted() then st = "wait" H.setPad({}) return end
        if H.worldMode() then
          -- the world map: down and back up, turning every 24 frames of
          -- control
          if not H.worldHasControl() then H.setPad({}) return end
          wn = wn + 1
          local pos = H.worldX() * 256 + H.worldY()
          if wn >= 24 then wdi, wlast, wn = 3 - wdi, pos, 0 end
          H.setPad({ [WDIRS[wdi]] = true })
          return
        end
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "left", "right", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
          if lane == nil then H.setPad({}) return end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      elseif st == "wait" then
        H.setPad({})
        if not H.battleActive() then return end
        encounters = encounters + 1
        slot = nil
        for s = 0, 3 do
          if H.readByte(BCHID + s * 2) == char then slot = s end
        end
        assert(slot, fixture .. ": the actor is in the battle")
        sk = sk or (H.sym("MonsterSketch") & 0x3FFFFF)
        local mons = {}
        c.target = nil
        for m = 0, 5 do
          if H.readWord(0x3BFC + m * 2) > 0 then
            local id = H.readWord(0x2001 + m * 2)
            local a1, a2 = H.readRomByte(sk + id * 2), H.readRomByte(sk + id * 2 + 1)
            mons[#mons + 1] = string.format("slot%d id $%03X sketch $%02X/$%02X", m, id, a1, a2)
            if c.cmd == CMD_SKETCH and c.target == nil and (sketchable(a1) or sketchable(a2)) then
              c.target = m
            end
          end
        end
        H.log(string.format("[verbs] %s encounter %d: actor %d in slot %d, hands $%02X $%02X; "
          .. "monsters: %s%s", fixture, encounters, char, slot, H.readByte(0x3CA8 + slot * 2),
          H.readByte(0x3CA9 + slot * 2), table.concat(mons, ", "),
          c.target and string.format("; aiming at slot %d", c.target) or ""))
        if c.cmd ~= CMD_SKETCH or c.target ~= nil then st = "found"
        else
          assert(encounters < 12, fixture .. ": no encounter with a sketchable monster in 12")
          st = "flee"
        end
      elseif st == "flee" then
        if not H.battleLoadStarted()
           and (H.worldMode() and H.worldHasControl() or H.hasControl()) then
          st, lane = "pace", nil
          H.setPad({})
          return
        end
        H.setPad(H.battleLoadStarted() and { l = true, r = true } or {})
      end
    end),
  }, "an encounter for " .. c.name)
  for _, s in ipairs({
    H.driveUntil(function() return snap ~= nil end, 30000, {
      H.call(function()
        if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD
           and (H.readByte(ACTOR) & 3) == slot
           and H.readByte(BANK + slot * 2) >= BOOST and H.readByte(PEND + slot * 2) == 0 then
          H.setPad({})
          snap = H.requestSaveState()
          return
        end
        defendOthers(-1)
      end),
    }, "the actor's window with " .. BOOST .. " pips"),
    H.waitFrames(2),
    H.call(function() H.checkReq(snap, "snapshot") end),
  }) do steps[#steps + 1] = s end
  for n = 1, TRIES do
    for _, s in ipairs(tryCase(c, n)) do steps[#steps + 1] = s end
  end
  steps[#steps + 1] = H.call(function()
    H.log(string.format("[verbs] %s %s: %s", fixture, c.name,
      c.hit and ("happened on try " .. c.hit) or ("did not happen in " .. TRIES .. " tries")))
  end)
  return steps
end

local tempest = { name = "Cyan Fight with Tempest", cmd = CMD_FIGHT,
  done = function(c)
    for _, k in ipairs(c.calls) do if k.b5 == 0x02 and k.b6 == WIND_SLASH then return true end end
    return false
  end }
-- a sketch that lands a Battle or Special runs as command $00 and is exempt
-- as a Fight; the case is a sketched attack under any other command
local sketch = { name = "Relm Sketch", cmd = CMD_SKETCH,
  done = function(c)
    for _, k in ipairs(c.calls) do
      if k.b5 ~= CMD_SKETCH and k.b5 ~= CMD_FIGHT and k.din > 0 then return true end
    end
    return false
  end }

local steps = { H.waitFrames(20) }
for _, s in ipairs(section("build/states/forest_done.mss.lua", CYAN, {
  H.call(function()
    -- one Tempest into the first empty bag slot (probe expedient, declared)
    for s = 0, 255 do
      if H.readByte(0x1869 + s) == 0xFF then
        H.writeByte(0x1869 + s, TEMPEST)
        H.writeByte(0x1969 + s, 1)
        H.log(string.format("[verbs] forest_done: Tempest written into bag slot %d", s))
        return
      end
    end
    error("no empty bag slot")
  end),
  H.equipKit(CYAN, { { 0, TEMPEST } }),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * CYAN + 0x1F), TEMPEST, "Cyan's right hand holds Tempest")
  end),
}, tempest)) do steps[#steps + 1] = s end
-- thamasa_done stands on the world map at (249,128), the tile below
-- Thamasa's gate: walk three tiles south first, so the pacing lane (down and
-- up only) never steps back into town
local offThamasa = {
  H.worldNavTo(249, 131, { maxFrames = 3000 }),
}
for _, s in ipairs(section("build/states/thamasa_done.mss.lua", RELM, offThamasa, sketch)) do
  steps[#steps + 1] = s
end

H.run({ maxFrames = 300000 }, steps)
