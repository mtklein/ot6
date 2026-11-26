-- gen_wor_icedragon.lua -- a branch beside the Narshe arc (wt/v052-tg-wor2, #561): the Ice Dragon's battle as it
-- comes up, for battle_icedragon.  The dragon (map 34 NPC_2, _cc36df: event battle 132) wanders the cliffs below the
-- save point, so the line meets it on gen_wor_narshe's walk past it or touches it from the save point in
-- gen_wor_tritoch, whichever the draw deals; neither leg can promise its capture.  This leg boots gen_wor_narshe's
-- capture of the party arriving on map 34 (`icedragon_field`), walks up beside the dragon and presses into it
-- (gen_wor_tritoch's touchNpc), and captures the battle as it comes up (`icedragon_entry`, H.battleOpenCapture); it
-- then fights it out with the walk's driver options (gen_wor_narshe's FIGHT, the line's when it met the dragon on the
-- walk) and checks the dragon beaten.  No leg boots what it leaves (`wor_icedragon`): the fight's XP stays off the
-- main line, which goes on from gen_wor_narshe's own play.
-- Nothing is written; every step, menu and fight is a button press.
local H = dofile("tools/tests/lib/ot6.lua")

local ICEDRAGON, ICEDRAGON_FORMATION = 0x149, 366
local MAP_CLIFF_SAVE = 34
local FIGHT = {}
local CAP = H.battleOpenCapture(ICEDRAGON, "icedragon_entry.mss")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
end

-- map 34's NPCs are the save point (NPC_1, object $10, posted on (25,5)) and the Ice Dragon (NPC_2, object $11), which
-- wanders.  (gen_wor_tritoch's dragonObj, the one object anywhere but the save point, reads after a Continue; on the
-- walk in, two objects of the map before stand at junk tiles too: "$28(110,16) $29(87,45)",
-- build/attempts/wt/v052-tg-wor2/dev/probe_objs.log, so this leg's first run failed "got 3, want 1")
local function dragonObj()
  local o = 0x11
  H.log(string.format("[npc] the Ice Dragon: object $%02X at (%d,%d); the save point $10 at (%d,%d)", o, H.objX(o),
    H.objY(o), H.objX(0x10), H.objY(0x10)))
  H.assertEq(H.objX(0x10) == 25 and H.objY(0x10) == 5 and not (H.objX(o) == 0 and H.objY(o) == 0), true,
    "map 34's save point is object $10 on (25,5) and the Ice Dragon object $11 stands on the map")
  return o
end
local function begun()
  return (H.battleLoadStarted() and H.formationHas({ [ICEDRAGON] = true })) or sw(0x0695) == 0
end

-- (gen_wor_tritoch's touchNpc) the object's live tile is read every step; a random battle that comes up on the way
-- is fought with the walk's driver
local function touchDragon()
  local ph, pressed, inBattle = 0, 0, false
  local drv = H.fightDriverFor("touchNpc", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  return H.seqStep({
    H.cond(function() return not begun() end, {
      H.lazy(function()
        local o = dragonObj()
        local function side()
          local ox, oy = H.objX(o), H.objY(o)
          for _, d in ipairs({ { 0, -1 }, { -1, 0 }, { 1, 0 }, { 0, 1 } }) do
            if H.bfsPath(ox + d[1], oy + d[2]) then return { ox + d[1], oy + d[2] } end
          end
          return { ox, oy - 1 }
        end
        return H.seqStep({
          H.navTo(function() return side()[1] end, function() return side()[2] end,
            { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, arrive = function()
              return begun() or math.abs(H.objX(o) - H.fieldX()) + math.abs(H.objY(o) - H.fieldY()) == 1
            end }),
          H.withReset(H.driveUntil(begun, 40000, {
            H.call(function()
              ph = (ph + 1) % 8
              if H.battleLoadStarted() then
                if H.formationHas({ [ICEDRAGON] = true }) then H.setPad({}); return end
                inBattle = true; drv.frame(); return
              end
              if inBattle then drv.idle(); inBattle = false end
              pressed = pressed + 1
              if pressed > 1200 then
                error("timeout after 1200 frames of presses toward the Ice Dragon (34 NPC_2): touch it")
              end
              if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
              local dx, dy = H.objX(o) - H.fieldX(), H.objY(o) - H.fieldY()
              local dir = dx > 0 and "right" or dx < 0 and "left" or dy > 0 and "down" or "up"
              H.setPad(ph < 4 and { [dir] = true, a = true } or { [dir] = true })
            end),
          }, "the Ice Dragon (34 NPC_2): touch it"), function() ph, pressed, inBattle = 0, 0, false end),
          H.release(),
        })
      end),
    }, {}),
  })
end

H.run({ maxFrames = 300000 }, {
  H.loadState("build/states/icedragon_field.mss.lua"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control on the cliffs (34)", 5),
  H.call(function()
    H.assertEq(map(), MAP_CLIFF_SAVE, "booted on the cliffs' save point map (34), gen_wor_narshe's capture as the "
      .. "party arrives")
    H.assertEq(sw(0x0695), 1, "the Ice Dragon still stands on the cliffs ($0695 set): gen_wor_narshe's capture is "
      .. "made before the walk past it")
  end),
  -- @@setup-end
  CAP.arm(),
  touchDragon(),
  H.advanceStory(function()
    return sw(0x0695) == 0 and not H.battleLoadStarted() and map() == MAP_CLIFF_SAVE and settled()
  end, 120000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    local n = 0
    for _, o in ipairs(H.outcomes or {}) do
      if (o.form & 0x1FF) == ICEDRAGON_FORMATION then
        n = n + 1
        H.log(string.format("[boss] the Ice Dragon: battle $%03X %s after %d ticks, %d seated", o.form & 0x1FF,
          o.kind, o.tick or -1, o.seatedN or -1))
      end
    end
    H.assertEq(sw(0x0695), 0, "the Ice Dragon is beaten ($0695 clear, _cc36df)")
  end),
  CAP.emit(),
  H.saveState("wor_icedragon.mss"),
  H.logStep("wor_icedragon generated: the Ice Dragon's battle captured as it came up, and won"),
})
