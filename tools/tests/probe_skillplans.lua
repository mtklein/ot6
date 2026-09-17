-- @manual
-- probe_skillplans.lua -- the fight driver's skill verbs through the real
-- menu (#188): newFightDriver plays whole natural battles with the verb
-- asked for, and the run checks that each verb was pressed home and that
-- the unknown-menu ledger stayed empty while it was.
--
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1 \
--     tools/tests/run.sh tools/tests/probe_skillplans.lua
--
-- Sections, each until the engine has executed its verb twice (at most
-- four battles):
--   slot    cold Continue terra-returned-v1 (LOCKE/EDGAR/SABIN/SETZER at the
--           grounded Blackjack, battle_slotsboot's boot); opts.slot + boost
--   swdtech camp_escaped (SABIN/CYAN/SHADOW, world map); opts.bushido
--   runic   zozo_arrival (LOCKE/EDGAR/SABIN/CELES, Zozo map 221); opts.runic
--   blitz   vargas_won (TERRA/LOCKE/EDGAR/SABIN, Mt. Kolts map 98);
--           opts.tactical with keyed = false and tools = false, so SABIN's
--           line is the driver's own Pummel
-- The encounters are the areas' own randoms; the battles are played by the
-- driver, not scripted.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local PATTERN = {
  slot = "Slot: spinning",
  swdtech = "SwdTech %$%x%x committed",
  runic = "Runic confirmed",
  blitz = "Blitz %$5D committed",
}
local landed = {}
local rawLog = H.log
H.log = function(s, ...)
  if type(s) == "string" then
    for k, p in pairs(PATTERN) do
      if s:find(p) then landed[k] = (landed[k] or 0) + 1 end
    end
  end
  return rawLog(s, ...)
end

-- what the battle engine actually executed: ExecCmd's command ($B5) and
-- attack ($B6) for a party entity (X < 8), the driver's own exec hook
local CMD_OF = { slot = 0x0F, swdtech = 0x07, runic = 0x0B, blitz = 0x0A }
local executed = {}
local execArmed = false
local function armExec()
  if execArmed then return end
  execArmed = true
  local a = H.sym("ExecCmd@battle_code")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if x < 8 and x % 2 == 0 then
      local cmd, atk = H.readByte(0xB5), H.readByte(0xB6)
      for k, c in pairs(CMD_OF) do
        if c == cmd then
          executed[k] = (executed[k] or 0) + 1
          rawLog(string.format("[skillplans] f%d engine executes %s (cmd $%02X atk $%02X) "
            .. "for entity %d", H.frame, k, cmd, atk, x // 2))
        end
      end
    end
  end, emu.callbackType.exec, a, a)
end

local function map() return H.mapId() & 0x1ff end

-- pace a two-tile lane on the current field map until a battle loads
local function fieldEncounter(what)
  local lane, m0 = nil, nil
  local BACK = { left = "right", right = "left", up = "down", down = "up" }
  return H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      m0 = m0 or map()
      if map() ~= m0 then error("paced off map " .. m0 .. " (now " .. map() .. ")", 0) end
      local x, y = H.fieldX(), H.fieldY()
      if lane == nil then
        for _, d in ipairs({ "right", "left", "up", "down" }) do
          if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
        end
        if lane == nil then H.setPad({}) return end
      end
      H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    end),
    H.waitFrames(1),
  }, what)
end

local function worldEncounter(what)
  local ph = 0
  local pattern = { "down", "down", "right", "right", "up", "up", "left", "left" }
  return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.call(function()
      if not H.worldMode() or not H.worldHasControl() then H.setPad({}) return end
      ph = ph + 1
      H.setPad({ [pattern[(math.floor(ph / 20) % #pattern) + 1]] = true })
    end),
  }, what)
end

local function section(key, encounter, opts, backOnField)
  local F = H.newFightDriver("skill-" .. key, opts)
  local steps = {
    H.call(function()
      armExec()
      H.vars.ledger0 = #H.unknownMenu.order
      H.log(string.format("[skillplans] section %s: opts runic=%s slot=%s bushido=%s "
        .. "tactical=%s", key, tostring(opts.runic), tostring(opts.slot),
        tostring(opts.bushido), tostring(opts.tactical)))
    end),
  }
  for n = 1, 4 do
    steps[#steps + 1] = H.cond(function() return (executed[key] or 0) >= 2 end, {}, {
      encounter(key .. " encounter " .. n),
      H.release(),
      H.waitUntil(function() return H.battleActive() end, 900, key .. " battle " .. n .. " armed", 5),
      H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
        H.call(function() F.frame() end),
      }, key .. " battle " .. n .. " played"),
      H.call(function()
        F.idle()
        H.setPad({})
        H.log(string.format("[skillplans] %s battle %d over at f%d: %s landed %d",
          key, n, H.frame, key, landed[key] or 0) .. string.format(", executed %d",
          executed[key] or 0))
      end),
      H.waitUntil(backOnField, 3000, key .. " back in control after battle " .. n, 5),
      H.waitFrames(30),
    })
  end
  steps[#steps + 1] = H.call(function()
    H.log("[skillplans] " .. key .. " ledger: " .. H.unknownMenuReport())
    H.assertEq((landed[key] or 0) >= 1, true, key .. ": the driver pressed the verb home")
    H.assertEq((executed[key] or 0) >= 1, true, key .. ": the engine executed the verb")
    H.assertEq(#H.unknownMenu.order, H.vars.ledger0,
      key .. ": no unknown menu state sampled while the verb was played")
  end)
  return H.repeatN(1, steps)
end

local function fieldControl() return H.hasControl() and H.tileAligned() end
local function worldControl() return H.worldMode() and H.worldHasControl() end

H.run({ maxFrames = 400000 }, {
  -- slot: the checkpoint's cold Continue (battle_slotsboot's boot)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "cold Continue to the world", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("terra-returned-v1") end),
  (function()
    local ph2 = 0
    return H.driveUntil(function()
      return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
         and H.worldHasControl() and H.worldAligned()
    end, 8000, {
      H.call(function()
        ph2 = ph2 + 1
        H.setPad((ph2 % 45) < 6 and { b = true } or {})
      end),
    }, "disembark the grounded Blackjack")
  end)(),
  H.release(),
  H.waitFrames(30),
  section("slot", worldEncounter, { slot = true, boost = true }, worldControl),

  H.loadState("build/states/camp_escaped.mss.lua"),
  H.waitFrames(30),
  section("swdtech", worldEncounter, { bushido = true }, worldControl),

  H.loadState("build/states/zozo_arrival.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(fieldControl, 3000, "zozo field control"),
  section("runic", fieldEncounter, { runic = true }, fieldControl),

  H.loadState("build/states/vargas_won.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(fieldControl, 3000, "kolts field control"),
  section("blitz", fieldEncounter, { tactical = true, keyed = false, tools = false }, fieldControl),

  H.call(function()
    H.log(string.format("[skillplans] landed: slot=%d swdtech=%d runic=%d blitz=%d; "
      .. "executed: slot=%d swdtech=%d runic=%d blitz=%d",
      landed.slot or 0, landed.swdtech or 0, landed.runic or 0, landed.blitz or 0,
      executed.slot or 0, executed.swdtech or 0, executed.runic or 0, executed.blitz or 0))
  end),
})
