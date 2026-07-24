-- probe_opera_world.lua -- boot zozo_done, exit to the world, drive toward
-- the Jidoor approach (27,129), and when movement stalls dump the world tile
-- props + passability around the party and screenshot. Read-only.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function killBitAll()
  for s=0,5 do if H.readByte(0x3aa8+s*2)%2==1 then
    H.writeByte(0x3eec+s*2, H.readByte(0x3eec+s*2)|0x80) end end
end
local DIRS = { "up","right","down","left" }

H.run({ maxFrames = 40000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_done.mss.lua"),
  H.waitFrames(120),
  H.navTo(62, 45, { maxFrames = 12000 }),
  (function() local hb=0
    return H.driveUntil(function() return H.worldMode() end, 4000, {
      H.call(function() hb=hb+1
        if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
        if H.dialogWaiting() then H.setPad(hb%8<4 and {"a"} or {}); return end
        H.setPad({ right=true }) end) }, "onto world-exit column") end)(),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() and bright()>=15 end,
    2000, "world control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[world] landed (%d,%d) worldId=%d",
      H.worldX(), H.worldY(), H.worldId()))
  end),
  (function()
    local hb, plan, idx, lastx, lasty, stuck = 0, nil, 1, -1, -1, 0
    return H.driveUntil(function()
      return (H.worldX()==27 and H.worldY()==129) or stuck > 1500
    end, 30000, {
      H.call(function()
        hb = hb + 1
        if H.battleLoadStarted() then killBitAll(); H.setPad(hb%8<4 and {"a"} or {}); return end
        if not H.worldHasControl() then H.setPad({}); return end
        if not H.worldAligned() then return end
        local x, y = H.worldX(), H.worldY()
        if x==lastx and y==lasty then stuck = stuck + 1 else stuck = 0; lastx=x; lasty=y end
        if hb % 600 == 0 or stuck == 800 then
          local s = ""
          for _, d in ipairs(DIRS) do
            s = s .. string.format("%s=%s ", d, tostring(H.worldCanStep(x, y, d)))
          end
          H.log(string.format("[wf%d] (%d,%d) tile=%02X prop=%04X pass:%s",
            hb, x, y,
            H.readByte(0x7F0000 + (y&0xFF)*256 + (x&0xFF)),
            H.worldTileProp(x, y), s))
        end
        if not plan or idx > #plan then
          plan = H.worldBfs(27, 129); idx = 1
          if not plan then H.log("[wf] NO BFS PATH"); H.setPad({}); return end
        end
        local dir = plan[idx]; idx = idx + 1
        H.setPad({ [dir] = true })
      end),
    }, "drive to Jidoor approach")
  end)(),
  H.call(function()
    local x, y = H.worldX(), H.worldY()
    H.log(string.format("=== STUCK/DONE at (%d,%d) ===", x, y))
    for dy = -2, 2 do
      local row = string.format("y%d: ", y+dy)
      for dx = -3, 3 do
        local p = H.worldTileProp(x+dx, y+dy)
        row = row .. string.format("%s%04X ", (dx==0 and dy==0) and "*" or " ", p)
      end
      H.log(row)
    end
    H.screenshot("world_stuck")
  end),
})
