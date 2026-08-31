-- @manual
-- probe_targetall.lua -- which input toggles ALL-ALLIES in battle target
-- select, and which RAM cell witnesses it?  Boots worldmap_narshe
-- (TERRA L5 + LOCKE), walks the plains until a random encounter, opens
-- TERRA's Magic -> Cure -> target select, then presses one candidate
-- button at a time, dumping the target-state window after each press.
-- Read the log; the lib change (party-wide boosted cure) is written from
-- what this measures, not from folklore.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, MSTATE, ACTOR = 0x7BCA, 0x7BC2, 0x62CA
local BCHID = 0x3ED8
local ST_CMD, ST_MAGIC, ST_TGT = 0x05, 0x0E, 0x38
local CURE = 0x2D
local CMDTBL = 0x202E

local function cmdRow(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + r * 3) == cmd then return r end
  end
  return nil
end

local function dumpTgt(tag)
  local w = {}
  for a = 0x7B70, 0x7B92 do w[#w + 1] = string.format("%02X", H.readByte(a)) end
  H.log(string.format("[tgt %s] st=%02X chars=$7B7D=%02X mons=$7B7E=%02X | 7B70..92: %s",
    tag, H.readByte(MSTATE), H.readByte(0x7B7D), H.readByte(0x7B7E),
    table.concat(w, " ")))
end

local phase, ph, sub = "wait", 0, 0
local probes = { "r", "l" }
local pi, pressGap = 0, 0
local done = false
local function dumpPads(tag)
  local dp = {}
  for a = 0x2E, 0x40 do dp[#dp + 1] = string.format("%02X", H.readByte(a)) end
  local pa = {}
  for a = 0x7A80, 0x7A90 do pa[#pa + 1] = string.format("%02X", H.readByte(a)) end
  H.log(string.format("[pads %s] $04=%02X $0A=%02X 7B7D=%02X 7B7E=%02X 7B7F=%02X | $2E..$40: %s | 7A80..90: %s",
    tag, H.readByte(0x04), H.readByte(0x0A),
    H.readByte(0x7B7D), H.readByte(0x7B7E), H.readByte(0x7B7F),
    table.concat(dp, " "), table.concat(pa, " ")))
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/worldmap_narshe.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world map")
  end),
  -- pace the plains until a battle rolls
  H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.call(function()
      ph = (ph + 1) % 64
      if H.worldMode() and H.worldHasControl() then
        H.setPad(ph < 32 and { down = true } or { up = true })
      else
        H.setPad({})
      end
    end),
  }, "a plains random rolls"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 15),
  H.waitFrames(120),

  -- drive to TERRA's Magic -> Cure -> target select, then probe buttons
  H.driveUntil(function() return done end, 20000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.readByte(MENU) == 0 then H.setPad(ph < 2 and { "a" } or {}); return end
      local st = H.readByte(MSTATE)
      local actor = H.readByte(ACTOR) & 3
      if st == ST_CMD then
        local id = H.readByte(BCHID + actor * 2)
        if id ~= 0 then
          -- not TERRA: Fight through this menu (row of cmd 0)
          local row = cmdRow(actor, 0x00) or 0
          local cur = H.readByte(0x890F + actor) & 3
          if cur ~= row then
            H.setPad(ph < 3 and { cur < row and "down" or "up" } or {})
          else
            H.setPad(ph < 3 and { "a" } or {})
          end
          return
        end
        local row = cmdRow(actor, 0x02)
        if row == nil then H.log("TERRA has no Magic row?!"); done = true; return end
        local cur = H.readByte(0x890F + actor) & 3
        if cur ~= row then
          H.setPad(ph < 3 and { cur < row and "down" or "up" } or {})
        else
          H.setPad(ph < 3 and { "a" } or {})
        end
        return
      end
      if st == ST_MAGIC then
        -- find Cure's cell in the compacted list
        local base = H.readWord(0x302C + actor * 2)
        if not H.vars.listDumped then
          H.vars.listDumped = true
          for i = 0, 5 do
            local rec = base + (i + 1) * 4
            H.log(string.format("[mlist] cell %d @%04X: id=%02X fl=%02X tgt=%02X mp=%02X",
              i, rec, H.readByte(rec), H.readByte(rec + 1),
              H.readByte(rec + 2), H.readByte(rec + 3)))
          end
        end
        local cell = nil
        for i = 0, 53 do
          local rec = base + (i + 1) * 4
          if H.readByte(rec) == CURE then cell = i break end
          if H.readByte(rec) == 0xFF then break end
        end
        if cell == nil then H.log("Cure not in list?!"); done = true; return end
        local wr, wc = cell // 2, cell % 2
        local row = H.readByte(0x8913) + H.readByte(0x891B)
        local col = H.readByte(0x8917)
        if col ~= wc then H.setPad(ph < 3 and { wc > col and "right" or "left" } or {}); return end
        if row ~= wr then H.setPad(ph < 3 and { wr > row and "down" or "up" } or {}); return end
        H.vars.viaMagic = true
        H.setPad(ph < 3 and { "a" } or {})
        return
      end
      if st == ST_TGT then
        -- only probe CURE's target select (reached through the magic grid);
        -- a Fight target select (first actor LOCKE) is just confirmed
        if not H.vars.viaMagic then
          H.setPad(ph < 2 and { "a" } or {})
          return
        end
        if pressGap > 0 then pressGap = pressGap - 1; H.setPad({}); return end
        if pi == 0 then
          dumpTgt("baseline")
          pi = 1; pressGap = 10
          return
        end
        if pi <= #probes then
          local b = probes[pi]
          if sub < 12 then
            H.setPad({ [b] = true }); sub = sub + 1
            dumpPads(b .. " f" .. sub)
            return
          else
            H.setPad({})
            dumpTgt("after " .. b)
            sub = 0; pi = pi + 1; pressGap = 20
            return
          end
        end
        dumpTgt("final")
        done = true
        H.setPad({})
        return
      end
      -- transitional
      H.setPad({})
    end),
  }, "target-select probe complete"),
  H.call(function()
    H.setPad({})
    H.log("probe done; B out and end the fight is not this probe's job")
    H.screenshot("targetall_probe")
  end),
})
