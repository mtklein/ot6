-- probe_896f.lua -- write-watcher over the battlefield $2105 shadow
-- ($7E896F): every writer PC and value through one Cirpius battle with a
-- Terra cast, so the 16x16 flips name their own writers (the instrument
-- behind battle_hudanim16's file:line citations).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/kolts_cave.mss.lua"
local DANGER = 0x1f6e
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CHARIX = 0x3ED9
local CMDTBL = 0x202E
local ST_SPELL, ST_TGT = 0x0e, 0x38

local function map() return H.mapId() & 0x1ff end

local writers = {}
local nWrites = 0
local function armWatch()
  emu.addMemoryCallback(function(addr, value)
    nWrites = nWrites + 1
    local s = emu.getState()
    local pc = string.format("%02X/%04X", s["cpu.k"], s["cpu.pc"])
    local key = string.format("%s=%02X", pc, value)
    writers[key] = (writers[key] or 0) + 1
    if writers[key] == 1 then
      H.log(string.format("[896f] writer %s (write #%d)", key, nWrites))
    end
  end, emu.callbackType.write, 0x7E896F, 0x7E896F)
end

local function bcmd(slot, i) return H.readByte(CMDTBL + slot*12 + i*3) end
local lastSt, lastActor, phase = -1, -1, 0
local function driveMenus()
  if H.readByte(MENU) == 0 then lastSt, lastActor, phase = -1, -1, 0 return nil end
  local st = H.readByte(MSTATE)
  local actor = H.readByte(ACTOR)
  if st ~= lastSt or actor ~= lastActor then lastSt, lastActor, phase = st, actor, 0 end
  phase = phase + 1
  local step = math.floor((phase - 1) / 12) + 1
  if ((phase - 1) % 12) >= 4 then return nil end
  if H.readByte(CHARIX + actor*2) == 0x00 then
    if st == ST_SPELL or st == ST_TGT then return {"a"} end
    local downs, seen = nil, 0
    for i = 0, 3 do
      local c = bcmd(actor, i)
      if c == 0x02 then downs = seen end
      if c ~= 0xff then seen = seen + 1 end
    end
    if downs == nil then return {"a"} end
    if step <= downs then return {"down"} end
    return {"a"}
  end
  return {"a"}
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        H.writeWord(DANGER, 0xff00)
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a cave encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.call(armWatch),
  (function()
    local n = 0
    return H.driveUntil(function()
      n = n + 1
      return n >= 1600
    end, 2200, {
      H.call(function()
        local b = driveMenus()
        if b then H.setPad(b) else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "watched rounds")
  end)(),
  H.call(function()
    H.setPad({})
    local t = {}
    for k, v in pairs(writers) do t[#t+1] = string.format("%s x%d", k, v) end
    table.sort(t)
    H.log("[896f] writers: " .. table.concat(t, "; "))
    H.log(string.format("[896f] total writes %d", nWrites))
  end),
})
