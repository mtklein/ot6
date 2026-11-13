-- gen_wob_base_guards.lua -- a branch beside the raid on Vector (#281, docs/design/wob-side-trips.md section 1):
-- boot `blackjack` (EDGAR, SABIN, LOCKE and CELES on foot by the Blackjack outside Vector, the first point the
-- southern continent can be reached), walk east to the Imperial Base and fight its guards.  Until the Narshe meeting sets
-- $0076 the base's ten soldiers stand ($045E-$0467, NPCProp::_377) and a touch is a fight: the magitek rider NPC_1
-- at (15,9) starts battle 40 (Mega Armor $102 + ProtoArmor $165, formation 417; _cb2599), every other soldier
-- battle 39 (Commando x4, formation 416; _cb2583/_cb258e).  Either way the party is "Chucked out" to the world at
-- (164,194).  A loss is a game over (_ca5ea9).  The leg goes in until both have been won.  No leg boots what it
-- leaves (the state `wob_base_guards`); gen_vector_entry goes on from the post-Opera save.
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, CELES, EDGAR, SABIN = 1, 6, 4, 5
local NAMES = { [LOCKE] = "LOCKE", [CELES] = "CELES", [EDGAR] = "EDGAR", [SABIN] = "SABIN" }
local FOUR = { EDGAR, SABIN, LOCKE, CELES }
local MAP_BASE = 377
local BASE_DOOR = { 165, 194 }
local RIDER = 0x10                       -- NPC_1, the magitek rider at (15,9): battle 40
local FORM_COMMANDOS, FORM_ARMORS = 416, 417
local FIGHT = { tactical = true, boost = true, items = true, healPercent = 50 }
H.NAV_REFIRE_HOLD = true
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, say, kitLine, sw, settled = K.map, K.say, K.kitLine, K.sw, K.settled

local won, seen = {}, nil
local function scan()
  while seen < #H.outcomes do
    seen = seen + 1
    local o = H.outcomes[seen]
    local f = o.form & 0x3FF
    if o.kind == "won" then won[f] = true end
    H.log(string.format("[guard] formation %d %s after %d ticks", f, o.kind, o.tick or -1))
  end
end
local function wonLine()
  return string.format("416 Commando x4 %s; 417 Mega Armor + ProtoArmor %s", won[FORM_COMMANDOS] and "won" or "-",
    won[FORM_ARMORS] and "won" or "-")
end

-- one visit: in by the west gate, a guard's fight, chucked out to (164,194)
local function visit(n)
  local target = nil
  return H.cond(function() scan(); return not (won[FORM_COMMANDOS] and won[FORM_ARMORS]) end, {
    H.fieldCare({ threshold = 1.0, tag = "before the base, visit " .. n }),
    H.worldNavTo(BASE_DOOR[1], BASE_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == MAP_BASE and not H.worldMode() end }),
    H.waitUntil(function() return map() == MAP_BASE and settled() end, 2400, "the Imperial Base: map 377", 1),
    H.call(function()
      -- the rider while his fight is wanted; else whichever foot soldier is nearest
      target = nil
      if not won[FORM_ARMORS] then
        target = RIDER
      else
        local bd = nil
        for o = 0x11, 0x19 do
          local ox, oy = H.objX(o), H.objY(o)
          if ox ~= 0 or oy ~= 0 then
            local d = math.abs(ox - H.fieldX()) + math.abs(oy - H.fieldY())
            if bd == nil or d < bd then target, bd = o, d end
          end
        end
      end
      H.assertEq(target ~= nil, true, "a guard stands in the base ($045E-$0467 still shown)")
      say("guard", string.format("visit %d: toward obj $%02X at (%d,%d); %s", n, target, H.objX(target),
        H.objY(target), wonLine()))
    end),
    -- a soldier walks into the party as often as the party into him: any touch starts his fight
    H.withReset((function()
      local t = 0
      return H.driveUntil(function() return H.battleLoadStarted() or H.dialogWaiting() or H.worldMode() end, 6000, {
        H.call(function()
          t = t + 1
          if not H.hasControl() then H.setPad({}); return end
          local ox, oy = H.objX(target), H.objY(target)
          local dx, dy = ox - H.fieldX(), oy - H.fieldY()
          if math.abs(dx) + math.abs(dy) == 1 then
            local face = dx == 1 and "right" or dx == -1 and "left" or dy == 1 and "down" or "up"
            H.setPad(t % 16 < 4 and { face, "a" } or { face })
            return
          end
          local best = nil
          for _, s in ipairs({ { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 } }) do
            local p = H.bfsPath(ox + s[1], oy + s[2])
            if p and #p > 0 and (best == nil or #p < #best) then best = p end
          end
          if best and H.tileAligned() then H.setPad({ H.movePress(best[1]) }) elseif not best then H.setPad({}) end
        end),
      }, "toward the guard")
    end)(), function() end),
    H.release(),
    H.advanceStory(function()
      return H.worldMode() and H.worldSettled() and not H.battleLoadStarted()
    end, 120000, { playBattles = "tactical", fight = FIGHT }),
    H.waitWorldSettled("chucked out to the world", 2400, 30),
    H.call(function()
      scan()
      H.assertEq(H.worldX() == 164 and H.worldY() == 194, true, "chucked out to the world at (164,194) (_cb2569)")
      say("guard", string.format("visit %d done; %s", n, wonLine()))
    end),
  }, {})
end

local steps = {
  H.loadState("build/states/blackjack.mss.lua"),
  K.watches(),
  H.call(function()
    seen = #H.outcomes
    say("wob", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(sw(0x0076), 0, "the guards still stand: $0076 clear (the Narshe meeting sets it)")
    H.assertEq(sw(0x045E), 1, "the magitek rider is shown ($045E)")
  end),
  -- @@setup-end

  -- @@stage walk
  -- On foot: the Blackjack does not fly from here.  A on its tile walks aboard (lab bj3: the hold, map 7), but the
  -- wheel's _caf532 returns while $016F is clear (lab: clear in both the blackjack and n128_won states), so a
  -- player walks the plain east to the base, as the banquet's guests do (gen_wob_base_treasure).
  H.call(function()
    H.assertEq(H.worldBfs(164, 194) ~= nil, true, "the Imperial Base's world tile (164,194) on foot from the boot "
      .. "tile by the Blackjack")
  end),
  -- @@stage guards
}
for n = 1, 6 do steps[#steps + 1] = visit(n) end
for _, s in ipairs({
  H.call(function()
    scan()
    H.assertEq(won[FORM_ARMORS] == true, true, "formation 417 (Mega Armor + ProtoArmor) won")
    H.assertEq(won[FORM_COMMANDOS] == true, true, "formation 416 (Commando x4) won")
  end),
  H.fieldCare({ threshold = 1.0, tag = "after the guards" }),
  H.call(function()
    say("wob", "outside the base")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveState("wob_base_guards.mss"),
  H.logStep(function()
    return string.format("wob_base_guards generated: EDGAR L%d SABIN L%d LOCKE L%d CELES L%d by the Imperial Base, "
      .. "world (%d,%d); %s", K.lv(EDGAR), K.lv(SABIN), K.lv(LOCKE), K.lv(CELES), H.worldX(), H.worldY(), wonLine())
  end),
}) do steps[#steps + 1] = s end
H.run({ maxFrames = 600000 }, steps)
