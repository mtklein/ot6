-- probe_opera_objscan.lua -- boot aria_postfork, scan all 16 field objects'
-- positions (stride 0x29, X@086a Y@086d) to locate Draco (NPC_4) for the chase.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local STRIDE=0x29
local function objX(i) return H.readWord(0x086a + i*STRIDE) >> 4 end
local function objY(i) return H.readWord(0x086d + i*STRIDE) >> 4 end
local function objType(i) return H.readByte(0x087c + i*STRIDE) & 0x0F end
local function scan(tag)
  local po = H.readWord(0x0803)
  H.log(string.format("[%s] f%d map=%d party pobj=$%02x -> obj#%d  CELES(fieldX/Y)=(%d,%d) | 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d",
    tag, H.frame, map(), po, po//STRIDE, H.fieldX(), H.fieldY(), sw(0x0057), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2)))
  for i=0,15 do
    local x,y,t = objX(i), objY(i), objType(i)
    if x<200 and y<200 and (x~=0 or y~=0) then
      H.log(string.format("   obj#%2d off=$%03x (%3d,%3d) type=%d", i, i*STRIDE, x, y, t))
    end
  end
end
H.run({ maxFrames = 8000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/aria_postfork.mss.lua"),
  H.waitFrames(60),
  H.call(function() H.assertEq(map(),236,"boot 236 postfork"); scan("t0"); H.screenshot("objscan0") end),
  -- let Draco's idle/scripted motion run a bit, rescan (moving obj = Draco)
  H.waitFrames(120),
  H.call(function() scan("t180") end),
  H.waitFrames(120),
  H.call(function() scan("t300") end),
  H.logStep(function() return "objscan done" end),
})
