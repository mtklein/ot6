-- probe_opera_occ.lua -- boot aria_postfork; dump the OBJECT-COLLISION map
-- ($7E2000 bit7: '.'=free '#'=occupied) over x[4..15] y[6..27], and test canStep
-- for the transitions the climb needs, to learn which tiles NPCs block.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function occFree(x,y) return (H.readByte(0x7E2000 + (y&0xFF)*256 + (x&0xFF)) & 0x80) ~= 0 end
local function p1(x,y) return H.readByte(0x7E7600 + H.maptile(x,y)) end
H.run({ maxFrames = 4000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/aria_postfork.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(),236,"boot 236")
    H.log(string.format("[pos] CELES (%d,%d) z=%d", H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3))
    -- occupancy grid
    local hdr="   y\\x"; for x=4,15 do hdr=hdr..string.format(" %2d",x) end
    H.log("[occ]"..hdr)
    for y=6,27 do
      local row=string.format("   %3d ",y)
      for x=4,15 do row=row..(occFree(x,y) and "  ." or "  #") end
      H.log("[occ] "..row)
    end
    -- canStep tests for the climb transitions (live z from CELES tile, but
    -- canStep uses party z; move party is at (5,21) so tests reflect that z)
    local function t(x,y,mv) H.log(string.format("[step] canStep(%d,%d,%s)=%s p1cur=%02x p1dst=%02x occDst=%s",
      x,y,mv,tostring(H.canStep(x,y,mv)),p1(x,y),
      p1(x+({up={0,-1},down={0,1},left={-1,0},right={1,0}})[mv][1],
         y+({up={0,-1},down={0,1},left={-1,0},right={1,0}})[mv][2]),
      tostring(occFree(x+({up={0,-1},down={0,1},left={-1,0},right={1,0}})[mv][1],
         y+({up={0,-1},down={0,1},left={-1,0},right={1,0}})[mv][2])))) end
    t(11,19,"right"); t(11,19,"up"); t(13,19,"up"); t(13,18,"left")
    t(14,19,"up"); t(14,18,"up"); t(12,18,"up"); t(12,15,"up")
    H.screenshot("occ")
  end),
  H.logStep(function() return "occ dump done" end),
})
