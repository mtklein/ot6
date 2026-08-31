-- @manual
-- probe_throw.lua -- map SHADOW's Throw window (menu state $24): cursor
-- cells, list base, and the confirm flow, so newFightDriver can learn the
-- verb (owner: unknown menus are missed opportunities -- Shadow's throw
-- can be useful).  Boots forest_done (SABIN/CYAN/SHADOW on the Phantom
-- Train), walks into a random, Fights with everyone but SHADOW, and on
-- his menu: steer to the Throw row, A, then dump the window's state while
-- stepping the cursor; one A on a row (to see the target flow), then B out.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, MSTATE, ACTOR, BCHID = 0x7BCA, 0x7BC2, 0x62CA, 0x3ED8
local ST_CMD, ST_TGT, ST_THROW = 0x05, 0x38, 0x24
local CMD_THROW = 0x08
local CMDTBL, CMDROW = 0x202E, 0x890F

local function cmdRow(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + r * 3) == cmd then return r end
  end
  return nil
end

local function dumpThrow(tag)
  local cur = {}
  for a = 0x893B, 0x8953 do cur[#cur + 1] = string.format("%02X", H.readByte(a)) end
  local lst = {}
  for i = 0, 9 do
    local b = 0x4005 + i * 3
    lst[#lst + 1] = string.format("%02X.%02X.%02X",
      H.readByte(b), H.readByte(b + 1), H.readByte(b + 2))
  end
  local inv = {}
  for i = 0, 7 do
    local b = 0x2686 + i * 5
    inv[#inv + 1] = string.format("%02X*%d", H.readByte(b), H.readByte(b + 3))
  end
  H.log(string.format("[throw %s] st=%02X | cur $893B..53: %s", tag,
    H.readByte(MSTATE), table.concat(cur, " ")))
  H.log(string.format("[throw %s] wItemList $4005: %s | battinv $2686: %s",
    tag, table.concat(lst, " "), table.concat(inv, " ")))
  H.log(string.format("[throw %s] 7A80..90: %s", tag, (function()
    local w = {}
    for a = 0x7A80, 0x7A90 do w[#w + 1] = string.format("%02X", H.readByte(a)) end
    return table.concat(w, " ")
  end)()))
end

local ph, phase, pressGap, done = 0, "seek", 0, false
local holdBtn, holdN = nil, 0
local hb = 0
-- press a button for 4 consecutive frames, then release into a gap
local function press(b, gapAfter)
  holdBtn, holdN, pressGap = b, 4, gapAfter or 12
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/forest_done.mss.lua"),
  H.waitFrames(60),
  -- roll a random on the train map
  H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.call(function()
      ph = (ph + 1) % 64
      if H.hasControl() and H.tileAligned() then
        H.setPad(ph < 32 and { left = true } or { right = true })
      else
        H.setPad({})
      end
    end),
  }, "a train random rolls"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 15),
  H.waitFrames(120),

  H.driveUntil(function() return done end, 20000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 300 == 0 then
        H.log(string.format("[hb] f%d st=%02X menu=%02X actor=%d char=%d phase=%s",
          H.frame, H.readByte(MSTATE), H.readByte(MENU),
          H.readByte(ACTOR) & 3,
          H.readByte(BCHID + (H.readByte(ACTOR) & 3) * 2), tostring(phase)))
      end
      if holdN > 0 then
        holdN = holdN - 1
        H.setPad({ [holdBtn] = true })
        return
      end
      if pressGap > 0 then pressGap = pressGap - 1; H.setPad({}); return end
      if H.readByte(MENU) == 0 then H.setPad(ph < 2 and { "a" } or {}); return end
      local st = H.readByte(MSTATE)
      local actor = H.readByte(ACTOR) & 3
      if st == ST_CMD then
        local id = H.readByte(BCHID + actor * 2)
        local row = cmdRow(actor, CMD_THROW)
        if id ~= 3 or row == nil then
          -- not SHADOW: Fight through
          local fr = cmdRow(actor, 0x00) or 0
          local cur = H.readByte(CMDROW + actor) & 3
          if cur ~= fr then
            H.setPad(ph < 3 and { cur < fr and "down" or "up" } or {})
          else
            H.setPad(ph < 3 and { "a" } or {})
          end
          return
        end
        local cur = H.readByte(CMDROW + actor) & 3
        if cur ~= row then
          H.setPad(ph < 3 and { cur < row and "down" or "up" } or {})
        else
          H.setPad(ph < 3 and { "a" } or {})
        end
        return
      end
      -- $2B = open throw window (builds wItemList), $2D = throw item
      -- select (btlgfx UpdateMenuState_2b/2d); the machine runs only on
      -- the interactive $2D
      if st == 0x2D then
        if phase == "seek" then
          dumpThrow("baseline")
          phase = "down1"
          press("down", 12)
          return
        elseif phase == "down1" then
          dumpThrow("after down")
          phase = "up1"
          press("up", 12)
          return
        elseif phase == "up1" then
          dumpThrow("before A")
          phase = "post"
          press("a", 12)
          return
        end
        H.setPad({})
        return
      end
      -- a non-SHADOW Fight's target select: confirm the default target
      if st == ST_TGT and phase == "seek" then
        H.setPad(ph < 3 and { "a" } or {})
        return
      end
      if st == ST_TGT and phase == "post" then
        dumpThrow("target select reached (A on a row -> ST_TGT)")
        phase = "cancel"
        H.setPad({})
        return
      end
      if phase == "cancel" then
        -- back all the way out, then Fight to keep the battle moving
        if st == ST_TGT or st == ST_THROW then
          H.setPad(ph < 3 and { "b" } or {})
          return
        end
        if st == ST_CMD then
          done = true
          H.setPad({})
          return
        end
        H.setPad({})
        return
      end
      if phase == "post" then
        -- A on the row went somewhere unexpected; dump and finish
        dumpThrow("post-A state " .. string.format("%02X", st))
        phase = "cancel"
        H.setPad({})
        return
      end
      H.setPad({})
    end),
  }, "throw window mapped"),
  H.call(function()
    H.setPad({})
    H.log("throw probe complete")
    H.screenshot("throw_probe")
  end),
})
