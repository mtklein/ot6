-- probe_itemuse.lua -- measure the battle Item menu's press semantics, on
-- the exact fixture that wedged: cyan_defence (CYAN alone, battle 46).
-- Drives the commander talk, waits for CYAN's command menu, steers to the
-- ITEM row, and then logs EVERY relevant byte per A-press pulse while
-- trying to use the top item: menu state $7BC2, cursor cells, the
-- select-mode cells w7e7b02/w7e7baf/w7e7ba8/w7e7b03, and the first two
-- battle-inventory rows ($2686 stride 5).  PASS = target select ($38)
-- reached and the item resolved (row count decremented).  Read-only.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_ITEM, ST_TGT = 0x05, 0x0A, 0x38
local CMD_ITEM = 0x01
local CMDTBL, CMDROW, ITEMIDX = 0x202E, 0x890F, 0x8947
local BATTINV = 0x2686
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end
local function row(i)
  return string.format("r%d=%02X,%02X,%02X,%02X,%02X", i,
    H.readByte(BATTINV + i * 5), H.readByte(BATTINV + i * 5 + 1),
    H.readByte(BATTINV + i * 5 + 2), H.readByte(BATTINV + i * 5 + 3),
    H.readByte(BATTINV + i * 5 + 4))
end
local function snap(tag)
  local a = H.readByte(ACTOR)
  H.log(string.format(
    "[itemuse %s] f%d st=%02X actor=%d cmdrow=%d itm=%d b02=%02X baf=%02X " ..
    "ba8=%02X b03=%04X tchars=%02X tmons=%02X %s %s", tag, H.frame,
    H.readByte(MSTATE), a, H.readByte(CMDROW + a) & 3,
    H.readByte(0x8947 + a) + H.readByte(0x894F + a), H.readByte(0x7B02),
    H.readByte(0x7BAF),
    H.readByte(0x7BA8), H.readWord(0x7B03),
    H.readByte(0x7B7D), H.readByte(0x7B7E), row(0), row(1))
    .. string.format(" pad=%02X%02X menu=%02X", H.readByte(0x0004),
      H.readByte(0x0005), H.readByte(MENU)))
end

local objXf = function(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local objYf = function(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local facing = function() return H.readByte(0x087f + H.readWord(0x0803)) end
local FACE = { up = 0, right = 1, down = 2, left = 3 }

local reached38, resolved = false, false

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/cyan_defence.mss.lua"),
  H.waitFrames(30),
  -- walk to the commander (obj 16) and poke him
  H.navTo(function() return objXf(16) end, function() return objYf(16) - 1 end,
    { maxFrames = 15000, honest = true }),
  (function()
    local phase = 0
    return H.driveUntil(function() return inBattle() end, 4000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        local dx, dy = objXf(16) - H.fieldX(), objYf(16) - H.fieldY()
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        if facing() ~= FACE[dir] then H.setPad({ [dir] = true }); return end
        H.setPad(phase < 4 and { "a" } or {})
      end),
    }, "battle 46 up")
  end)(),
  -- wait for a settled command menu
  H.waitUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD
  end, 3000, "CYAN's command menu", 5),
  H.waitFrames(30),
  H.call(function() snap("cmd") end),
  -- steer to the ITEM row (closed loop with absolute-jump fallback)
  (function()
    local tick, btn, stall = 0, nil, 0
    return H.driveUntil(function()
      return H.readByte(MSTATE) == ST_ITEM
    end, 4000, {
      H.call(function()
        tick = tick + 1
        local ph = tick % 20
        if ph == 0 then
          local a = H.readByte(ACTOR)
          local want = nil
          for i = 0, 3 do
            if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_ITEM then want = i end
          end
          local cur = H.readByte(CMDROW + a) & 3
          snap("steer want=" .. tostring(want))
          if want == nil then btn = nil
          elseif cur == want then btn = { "a" }
          else
            stall = stall + 1
            if stall > 3 then
              btn = { ({ [0]="up",[1]="left",[2]="right",[3]="down" })[want] }
              stall = 0
            else
              btn = { cur < want and "down" or "up" }
            end
          end
        end
        H.setPad(ph < 5 and btn or {})
      end),
    }, "item window open ($0A)")
  end)(),
  H.waitFrames(20),
  H.call(function() snap("item-open") end),
  -- now: EXACT fighter cadence -- steer to row 1 (Potion) then A pulses,
  -- 30-frame pulses with 6-frame holds, button recomputed at ph==0
  (function()
    local tick, pulses, btn = 0, 0, nil
    return H.driveUntil(function()
      if H.readByte(MSTATE) == ST_TGT then reached38 = true end
      return reached38 or pulses > 40
    end, 5000, {
      H.call(function()
        tick = tick + 1
        local ph = tick % 30
        if ph == 0 then
          pulses = pulses + 1
          local a = H.readByte(ACTOR)
          local cur = H.readByte(0x8947 + a) + H.readByte(0x894F + a)
          if cur < 1 then btn = { "down" }
          elseif cur > 1 then btn = { "up" }
          else btn = { "a" } end
          snap("pulse" .. pulses .. "->" .. tostring(btn[1]))
        end
        H.setPad(ph < 6 and btn or {})
      end),
    }, "target select ($38) after fighter-cadence pulses")
  end)(),
  H.call(function()
    snap(reached38 and "AT-38" or "NEVER-38")
    H.assertEq(reached38, true, "the item confirm reached target select")
  end),
  -- confirm the default target and watch the item resolve
  (function()
    local tick, n0 = 0, nil
    return H.driveUntil(function()
      if n0 == nil then n0 = H.readByte(BATTINV + 5 + 3) end
      if H.readByte(BATTINV + 5 + 3) < n0 then resolved = true end
      return resolved
    end, 2400, {
      H.call(function()
        tick = tick + 1
        local ph = tick % 20
        H.setPad(ph < 5 and { "a" } or {})
      end),
    }, "item resolved (row 1 count fell)")
  end)(),
  H.call(function()
    snap("done")
    H.log("[itemuse] PASS: select->use->target->resolve measured")
  end),
})
