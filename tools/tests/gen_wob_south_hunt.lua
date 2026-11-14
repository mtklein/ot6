-- gen_wob_south_hunt.lua -- a branch beside gen_vector_entry (docs/design/wob-side-trips.md, #282): Continue the
-- `post-opera-v1` battery (CELES, LOCKE, EDGAR and SABIN on foot at (137,203), set down on the southern continent
-- after the opera) and walk the forests there that no story leg walks until every formation of each pool has been
-- won (K.worldHunt, lib/ot6_field.lua: the pool asserted against the ROM's, the hunt bounded by the worst draws):
-- the forest east of the save (world group 20: Bug, FossilFang) and the forest north-west of it (group 17: Ralph,
-- Wyvern, ChickenLip; group 18 by Maranda deals the same pool, so one walk wins both).  No leg boots what it leaves
-- (the state `wob_south_hunt`); gen_vector_entry goes on from the same save.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, EDGAR, SABIN, CELES = 1, 4, 5, 6
local NAMES = { [LOCKE] = "LOCKE", [EDGAR] = "EDGAR", [SABIN] = "SABIN", [CELES] = "CELES" }
local FOUR = { CELES, LOCKE, EDGAR, SABIN }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local lv, say, kitLine, watches = K.lv, K.say, K.kitLine, K.watches

-- the zones (laps and landing tiles read from the ROM's world map: WorldTileProp's passable and landable bits,
-- WorldBattleGroup for each tile's group; docs/design/wob-side-trips.md section 1)
local ZONES = {
  { what = "the forest east of the save (group 20)", lap = { { 142, 203 }, { 143, 203 } },
    forms = { [139] = "FossilFang x2", [140] = "FossilFang, Bug x3", [141] = "Bug x3", [142] = "Bug x6" } },
  { what = "the forest north-west of the save (group 17)", lap = { { 119, 193 }, { 119, 194 } },
    forms = { [145] = "Ralph, Wyvern, ChickenLip x2", [149] = "ChickenLip x5" } },
}
-- every World of Balance entrance and event trigger (route_data's short entrances and triggers of world 0),
-- kept off every walk: Albrook's door (138,203) is the tile east of the save
local DOORS = { {21,92}, {22,92}, {22,93}, {26,39}, {26,131}, {27,39}, {27,130}, {28,131}, {30,6}, {30,48}, {31,48},
  {33,9}, {45,154}, {54,85}, {64,76}, {65,76}, {66,226}, {66,227}, {73,93}, {75,102}, {77,235}, {84,33}, {85,112},
  {85,113}, {86,111}, {86,112}, {90,99}, {98,92}, {102,100}, {104,64}, {117,61}, {118,61}, {119,149}, {120,149},
  {120,187}, {121,187}, {125,150}, {138,203}, {139,203}, {156,84}, {157,84}, {165,35}, {165,194}, {166,194},
  {169,194}, {177,92}, {178,82}, {178,92}, {179,71}, {185,93}, {214,148}, {220,115}, {229,130}, {250,128} }
-- ---- the Zombie guards: Albrook's relic counter before the forests ----------------------------------------------
-- The FossilFang's Special, Bone (MonsterProp +$1F = $41: no damage, status 1 bit 1), turns its target into a Zombie,
-- whose turns are the engine's (it swings at the party) and whom no Fenix Down reaches; the Revivify that cures it
-- leaves the member at an eighth of its HP, under the next Sand Storm, which the FossilFang casts on its own turns and
-- answers every Fight with (AIScript::_35: `if_cmd FIGHT / attack SAND_STORM`), the whole party at ~160-200 a hit.
-- In the sweep on main's 88042db5 the Zombie chain was most of the forest's deaths
-- (build/attempts/wt/v043-south-hunt/before/).  Only CELES's Ribbon guards it.  Albrook, the door beside the save,
-- sells the Amulet (relic shop 40, 5000 GP: ItemProp +6 = $07, Dark, Zombie, Poison) at the counter in map 330: a
-- player who has read the Bone buys one for each member nothing guards and wears it for the forests (an area
-- overlay, docs/guidelines' gear baseline: on for the stretch, off at its end).
local AMULET = 0xB3
local AMULETS = "Amulets"
H.GEAR_OVERLAYS[AMULETS] = { items = { AMULET }, where = "gen_wob_south_hunt (the southern forests' FossilFangs)",
  why = "the FossilFang's Bone (Zombie) on the members no Ribbon guards" }
local function relicAt(ch, s) return H.readByte(0x1600 + 37 * ch + 0x1F + s) end
local function guardsZombie(id)
  return id ~= 0xFF and (H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + 6) & 0x02) ~= 0
end
local function zombieGuarded(ch) return guardsZombie(relicAt(ch, 4)) or guardsZombie(relicAt(ch, 5)) end
-- the relic slot an Amulet takes: a slot holding the same relic as the other (a second RunningShoes adds nothing)
-- first, else the one whose relic the relic rule ranks lower; never a two-weapon relic or an assigned prize
local function amuletSlot(ch)
  local a, b = relicAt(ch, 4), relicAt(ch, 5)
  local function ok(id)
    if id == 0xFF then return true end
    for _, p in ipairs(H.GEAR_PRIZES) do if p == id then return false end end
    local cl = H.relicClass(id)
    return not (cl and cl.hands)
  end
  local function rank(id)
    if id == 0xFF then return -1 end
    local cl = H.relicClass(id)
    return cl and cl.rank or 0
  end
  if a == b and ok(b) then return 5 end
  local best = nil
  for _, s in ipairs({ 5, 4 }) do
    local id = relicAt(ch, s)
    if ok(id) and (best == nil or rank(id) < rank(relicAt(ch, best))) then best = s end
  end
  return best
end
local function amuletsWanted()
  local t = {}
  for _, ch in ipairs(FOUR) do
    if K.partyOf(ch) == 1 and not zombieGuarded(ch) and H.wearsItem(ch, AMULET) and amuletSlot(ch) ~= nil then
      t[#t + 1] = ch
    end
  end
  return t
end
local function mapNow() return H.mapId() & 0x3FF end
local displaced = {}          -- { ch=, slot=, id= }: the relic each Amulet took the slot of, back on after the forests
local function albrookAmulets()
  local want = 0
  local hb = 0
  return H.seqStep({
    H.call(function()
      want = #amuletsWanted()
      local t = {}
      for _, ch in ipairs(amuletsWanted()) do t[#t + 1] = NAMES[ch] end
      H.log(string.format("[amulet] the members no relic guards from Zombie: %s; Amulets in the bag %d; gil %d",
        #t > 0 and table.concat(t, ", ") or "none", H.invCountOf(AMULET), H.gil()))
    end),
    -- Albrook's gate is the tile east of the save (138,203); the Relic menu is opened in town, on a field map
    H.driveUntil(function() return mapNow() == 323 end, 1200, { H.hold({ "right" }) }, "into Albrook (138,203)"),
    H.release(),
    H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 1200, "Albrook control", 5),
    H.cond(function() return want > H.invCountOf(AMULET) end, {
      H.crossDoor(44, 12, 330, 37, 30, "Albrook's relic counter: door 323 (44,12) -> 330 (37,30)"),
      H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 2400, "the relic counter's room", 10),
      H.waitFrames(60),
      H.shopTalk(37, 25, "Albrook relic shop"),
      H.call(function()
        H.assertEq(H.readByte(0x0201), 40, "the counter opened shop 40 ($0201), the relic shop that sells the Amulet")
      end),
      H.buyItem(AMULET, function() return want - H.invCountOf(AMULET) end, "AMULET for each member no relic guards"),
      H.shopClose("Albrook relic shop"),
      -- out: the (37,31) event trigger below the arrival tile (_cc6136 -> 323 (44,14))
      H.navTo(37, 30, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
      H.driveUntil(function() return mapNow() == 323 end, 900, {
        H.call(function()
          hb = hb + 1
          if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
          H.setPad({ down = true })
        end) }, "held DOWN onto the (37,31) trigger -> Albrook 323"),
      H.release(),
      H.waitUntil(function()
        return mapNow() == 323 and H.hasControl() and H.tileAligned()
          and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
      end, 2400, "back on Albrook's streets", 5),
    }, {}),
    -- on: each member no relic guards, in the slot amuletSlot names, the relic there back in the bag
    H.lazy(function()
      local steps = {}
      for _, ch in ipairs(amuletsWanted()) do
        local slot = amuletSlot(ch)
        displaced[#displaced + 1] = { ch = ch, slot = slot, id = relicAt(ch, slot) }
        local label = string.format("an Amulet on %s (relic slot %d, for %02X)", NAMES[ch], slot, relicAt(ch, slot))
        steps[#steps + 1] = H.keepGear(ch, label, H.equipKit(ch, { { slot, AMULET } }, { tag = label }))
      end
      return H.seqStep(steps)
    end),
    H.call(function()
      for _, ch in ipairs(FOUR) do
        H.assertEq(zombieGuarded(ch), true, string.format("%s wears a Zombie guard for the forests (a Ribbon or an "
          .. "Amulet: the FossilFang's Bone)", NAMES[ch]))
      end
      H.log("[kit] " .. kitLine(FOUR))
    end),
    H.overlayOn(AMULETS),
    -- back out to the save's tile: map 323's west column is a long entrance to (137,203) (gen_vector_entry's walk
    -- out, from the item shop's side of town)
    H.navTo(2, 17, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
    H.release(),
    H.driveUntil(function() return H.worldMode() end, 8000, {
      H.call(function()
        hb = hb + 1
        if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
        H.setPad(hb % 240 < 120 and { left = true } or { up = true })
      end) }, "back out of Albrook to the world"),
    H.waitUntil(function()
      return H.worldHasControl() and H.worldAligned() and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
        and H.worldX() == 137 and H.worldY() == 203
    end, 2400, "back on the world at (137,203)", 5),
  })
end

local won = {}
local function lowest()
  local m = 99
  for _, ch in ipairs(FOUR) do m = math.min(m, lv(ch)) end
  return m
end

local function zone(z)
  local steps = {}
  -- topped up before the walk: the walk between the forests crosses group 15 (the Jokers' Acid Rain and Bolt 2)
  steps[#steps + 1] = H.fieldCare({ threshold = H.CARE_BEFORE_FIGHTS, tag = "before the walk to " .. z.what })
  -- onto the lap before the hunt starts, so the battles of the walk there (other groups) do not count against the
  -- hunt's bound
  steps[#steps + 1] = H.worldNavTo(z.lap[1][1], z.lap[1][2], { maxFrames = 40000, playBattles = "tactical",
    fight = FIGHT, avoid = DOORS, careThreshold = H.CARE_BEFORE_FIGHTS })
  steps[#steps + 1] = H.fieldCare({ threshold = 1.0, tag = "before " .. z.what })
  steps[#steps + 1] = H.call(function()
    say("hunt", string.format("%s: lowest L%d", z.what, lowest()))
    H.log("[kit] " .. kitLine(FOUR))
  end)
  steps[#steps + 1] = K.worldHunt({ what = z.what, lap = z.lap, forms = z.forms, won = won, avoid = DOORS,
    careThreshold = H.CARE_BEFORE_FIGHTS })
  steps[#steps + 1] = H.call(function()
    say("hunt", string.format("%s: done; lowest L%d", z.what, lowest()))
  end)
  return H.seqStep(steps)
end

local route = {}
for _, z in ipairs(ZONES) do route[#route + 1] = zone(z) end

H.run({ maxFrames = 3000000 }, {
  H.bootCheckpoint("post-opera-v1"),
  watches(),
  H.call(function()
    say("wob", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.log(string.format("[wob] the Blackjack parked at (%d,%d)", H.readByte(0x1F62), H.readByte(0x1F63)))
    for _, ch in ipairs(FOUR) do
      H.assertEq(K.partyOf(ch), 1, string.format("%s is seated (post-opera-v1: gen_post_opera_checkpoint's party)",
        NAMES[ch]))
    end
  end),
  -- @@setup-end
  albrookAmulets(),
  H.seqStep(route),
  H.fieldCare({ threshold = 1.0, tag = "after the hunts" }),
  -- the forests' overlay off: each Amulet gives its slot back to the relic it took it from.  (Not the gear baseline:
  -- its relic rule ranks the Amulet a guard and puts one back over EDGAR's second RunningShoes, so a baseline run
  -- here leaves the overlay worn; nothing boots this state, and no save is made.)
  H.lazy(function()
    local steps = {}
    for _, d in ipairs(displaced) do
      if d.id ~= 0xFF then
        local label = string.format("after the forests: %s's %02X back in relic slot %d", NAMES[d.ch], d.id, d.slot)
        steps[#steps + 1] = H.keepGear(d.ch, label, H.equipKit(d.ch, { { d.slot, d.id } }, { tag = label }))
      end
    end
    return H.seqStep(steps)
  end),
  H.call(function()
    for _, d in ipairs(displaced) do
      H.assertEq(d.id == 0xFF or relicAt(d.ch, d.slot) == d.id, true, string.format("after the forests: %s's relic slot %d holds what it held "
        .. "before the Amulet", NAMES[d.ch], d.slot))
    end
  end),
  H.overlayOff(AMULETS),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wob_south_hunt.mss"),
  H.logStep(function()
    local t = {}
    for f in pairs(won) do t[#t + 1] = f end
    table.sort(t)
    for i, f in ipairs(t) do t[i] = tostring(f) end
    return string.format("wob_south_hunt generated: CELES L%d, LOCKE L%d, EDGAR L%d, SABIN L%d at world (%d,%d); "
      .. "formations won: %s", lv(CELES), lv(LOCKE), lv(EDGAR), lv(SABIN), H.worldX(), H.worldY(),
      table.concat(t, " "))
  end),
})
