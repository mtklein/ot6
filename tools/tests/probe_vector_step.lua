-- probe_vector_step.lua -- measurement instrument for gen_vector_sneak.
--
-- navTo on VECTOR (map 242) logged EVERY rightward step landing two tiles
-- east of its plan -- "(42,38)->right landed (44,38)" -- and the party's x
-- stayed even for the whole walk, which would put the odd-x sneak ledge
-- {43,38} and the odd-x sympathizer {45,39} out of reach.  This dumps the
-- raw movement state per frame through a held RIGHT so the mechanism is
-- measured rather than guessed: party pixel coords ($086a/$086d via the
-- $0803 leader offset), the engine's OWN tile position bytes $af/$b0 (what
-- CheckEvent / CheckEntrance / the trigger tables compare against), the
-- movement type $087c, facing $087f, and the z byte $b2.
local H = dofile("tools/tests/lib/ot6.lua")

local function po() return H.readWord(0x0803) end
local function dump(tag)
  H.log(string.format(
    "[%s] f%d fieldXY=(%d,%d) px=(%d,%d) sub=(%02X,%02X) $af/$b0=(%d,%d) "
    .. "$1FC0/$1FC1=(%d,%d) mv=%02X face=%d z=%02X algn=%s ctl=%s",
    tag, H.frame, H.fieldX(), H.fieldY(),
    H.readWord(0x086a + po()), H.readWord(0x086d + po()),
    H.readByte(0x0869 + po()), H.readByte(0x086c + po()),
    H.readByte(0x00af), H.readByte(0x00b0),
    H.readByte(0x1FC0), H.readByte(0x1FC1),
    H.readByte(0x087c + po()), H.readByte(0x087f + po()),
    H.readByte(0x00b2), tostring(H.tileAligned()), tostring(H.hasControl())))
end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/vector_doorstep.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("map=%d  xmask=$%02X ymask=$%02X",
      H.mapId() & 0x1ff, H.readByte(0x0086), H.readByte(0x0087)))
    dump("boot")
  end),

  -- one held RIGHT for 120 frames, sampled every frame
  (function() local n = 0
    return H.driveUntil(function() return n >= 120 end, 400, {
      H.call(function() n = n + 1; H.setPad({ right = true }); dump("R" .. n) end),
    }, "hold RIGHT 120 frames")
  end)(),
  H.release(), H.waitFrames(30),
  H.call(function() dump("after-right") end),

  -- then a single 8-frame tap, the way a verified-step walker presses
  H.hold({ "right" }), H.waitFrames(8), H.release(), H.waitFrames(40),
  H.call(function() dump("after-tap") end),
  H.hold({ "down" }), H.waitFrames(24), H.release(), H.waitFrames(40),
  H.call(function() dump("after-down") end),

  -- and the model's own view of the neighbourhood
  H.call(function()
    local x, y = H.fieldX(), H.fieldY()
    for _, d in ipairs({ "up", "right", "down", "left" }) do
      H.log(string.format("canStep(%d,%d,%s) = %s", x, y, d,
        tostring(H.canStep(x, y, d))))
    end
    local p = H.bfsPath(43, 38)
    H.log("bfsPath -> (43,38): " .. (p and (#p .. " steps: " .. table.concat(p, ",")) or "NO PATH"))
    local q = H.bfsPath(45, 38)
    H.log("bfsPath -> (45,38): " .. (q and (#q .. " steps: " .. table.concat(q, ",")) or "NO PATH"))
  end),
})
