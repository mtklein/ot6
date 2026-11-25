-- @suite savestate=wor_kohlingen
-- field_gearplan.lua -- the gear policy's plan (#434, H.gearPlan), read on
-- the Narshe party after the battle (kefka_won: LOCKE, EDGAR, SABIN and
-- CELES in Arvis's house, the purse and bag as the leg left them).
--
-- H.gearPlan reads only (the party's records, the bag, the purse, the ROM's
-- item records) and logs its decisions; nothing here presses a button or
-- writes emulated state.  Stocks are built from the ROM's item table, so
-- every expectation is derived from the fixture's live state, and each
-- precondition is asserted by name first:
--   1. the budget: Narshe's two counters' stock (shops 0 and 1) is planned
--      within the purse less H.gearReserve, and a reserve of the whole
--      purse plans nothing;
--   2. the command's weapon: a member with Runic is never planned a blade
--      without the runic property, however strong (budget unbounded);
--   3. the break keys: a member whose hand holds a class no other seated
--      hand holds is not planned a weapon without it that is worth less
--      than GEAR_KEY more and brings no new class; one that keeps the class
--      and is worth more is planned.
-- The negative controls (each rule switched off turns this red) are
-- recorded in the commit that adds the file.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_kohlingen.mss.lua"
local RUNIC = 11
local function prop(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function wears(ch, id) return (((prop(id, 1) | (prop(id, 2) << 8)) >> ch) & 1) == 1 and (prop(id, 2) & 0x40) == 0 end
local function isWeapon(id) return (prop(id, 0) & 0x87) == 1 end
local function worn(ch, s) return H.readByte(0x1600 + 37 * ch + 0x1F + s) end
local function hasCmd(ch, cmd)
  for k = 0, 3 do if H.readByte(0x1600 + 37 * ch + 0x16 + k) == cmd then return true end end
  return false
end
local function bitsOf(v) local n = 0; while v ~= 0 do n = n + (v & 1); v = v >> 1 end; return n end
local function stockOf(ids)
  local out = {}
  for _, id in ipairs(ids) do out[#out + 1] = { id = id, price = H.itemPrice(id) } end
  return out
end
local function planned(plan, ch, slot, id)
  for _, k in ipairs(plan) do
    if k.char == ch and k.slot == slot and (id == nil or k.item == id) then return k end
  end
  return nil
end
local UNBOUNDED = -100000000      -- a reserve that leaves the budget unbounded

H.run({ maxFrames = 600 }, {
  H.loadState(STATE),
  H.waitFrames(5),
  H.call(function()
    local seated = H.seatedMembers()
    H.log(string.format("[gearplan] seated %d, gil %d", #seated, H.gil()))
    H.assertEq(#seated >= 2, true, "the fixture seats a party of two or more")

    -- 1. the budget
    local narshe = {}
    for _, shop in ipairs({ 80, 81 }) do
      for _, id in pairs(H.shopStock(shop)) do narshe[#narshe + 1] = id end
    end
    local reserve = H.gearReserve()
    local budget = H.gil() - reserve
    local plan = H.gearPlan(stockOf(narshe), { tag = "gearplan budget" })
    local spent = 0
    for _, k in ipairs(plan) do spent = spent + k.price end
    H.log(string.format("[gearplan] 1: %d piece(s), %d GP of the budget %d", #plan, spent, budget))
    H.assertEq(#plan > 0, true, "Maranda's counters (shops 80 and 81) offer this party an upgrade it can afford")
    H.assertEq(spent <= budget, true, string.format("the plan (%d GP) stays within the budget (%d GP)", spent, budget))
    local none = H.gearPlan(stockOf(narshe), { tag = "gearplan all reserved", reserve = H.gil() })
    H.assertEq(#none, 0, "a reserve of the whole purse plans nothing")

    -- 2. Runic keeps its blade
    local runic = nil
    for _, ch in ipairs(seated) do if hasCmd(ch, RUNIC) then runic = ch end end
    H.assertEq(runic ~= nil, true, "a seated member has the Runic command (CELES)")
    local cur = worn(runic, 0)
    local strong = {}
    for id = 0, 0xFE do
      if isWeapon(id) and wears(runic, id) and (prop(id, 19) & 0x80) == 0
          and H.gearValue(runic, id) > H.gearValue(runic, cur) + H.GEAR_KEY then
        strong[#strong + 1] = id
      end
    end
    H.log(string.format("[gearplan] 2: char %d wears $%02X; %d stronger blades without the runic property",
      runic, cur, #strong))
    H.assertEq(#strong > 0, true, "the ROM holds a stronger non-runic blade the Runic member can wear")
    plan = H.gearPlan(stockOf(strong), { tag = "gearplan runic", reserve = UNBOUNDED, pairs = true })
    H.assertEq(planned(plan, runic, 0) == nil, true, "the Runic member is planned no blade without the runic property")

    -- 3. the break keys
    local function others(ch, slot)
      local k = 0
      for _, m in ipairs(seated) do
        for s = 0, 1 do
          local id = worn(m, s)
          if not (m == ch and s == slot) and id ~= 0xFF and isWeapon(id) then k = k | H.gearWeaponKeys(id) end
        end
      end
      return k
    end
    -- the sole holder of a class, chosen among every seated hand whose key is its own for one the ROM offers both
    -- a weaker-by-less-than-a-key weapon that drops the key and a stronger one that keeps it (the fixture's dress
    -- decides which hands hold what: on the area-dressed replay the first unique hand held the strongest weapon of
    -- its keys, "the ROM holds a stronger weapon that keeps the class: got false",
    -- build/attempts/wt/v051-six-classes/suites/field_gearplan-gate9.log)
    -- each half of the case on a sole holder whose premise the fixture holds: one whose hand the ROM offers a
    -- weaker-by-less-than-a-key weapon that drops its key, one it offers a stronger weapon that keeps it (on the
    -- area-dressed replay no hand had both: EDGAR's Blizzard keys ice alone and nothing stronger keeps ice, SETZER's
    -- Trump keys Ranged and no weaker weapon drops it without a key of its own)
    local D, K, uniques = nil, nil, 0
    for _, ch in ipairs(seated) do
      if ch ~= runic then
        for s = 0, 1 do
          local id = worn(ch, s)
          if id ~= 0xFF and isWeapon(id) then
            local own = H.gearWeaponKeys(id) & ~others(ch, s)
            if own ~= 0 then
              uniques = uniques + 1
              local d, k = {}, {}
              for w = 0, 0xFE do
                if isWeapon(w) and wears(ch, w) and w ~= id then
                  local cls, gain = H.gearWeaponKeys(w), H.gearValue(ch, w) - H.gearValue(ch, id)
                  local new = cls & ~others(ch, s) & ~own
                  if (cls & own) == 0 and new == 0 and gain > 0 and gain < H.GEAR_KEY then d[#d + 1] = w end
                  if (cls & own) == own and gain > 0 then k[#k + 1] = w end
                end
              end
              if D == nil and #d > 0 then D = { ch = ch, s = s, id = id, key = own, list = d } end
              if K == nil and #k > 0 then K = { ch = ch, s = s, id = id, key = own, list = k } end
            end
          end
        end
      end
    end
    H.assertEq(uniques > 0, true, "a seated member's hand holds a break class no other hand holds")
    H.assertEq(D ~= nil, true, "the ROM holds a weapon worth less than a key more that drops a sole holder's class")
    H.log(string.format("[gearplan] 3: char %d slot %d holds $%02X, the only key $%X; %d stronger-by-less-than-a-key "
      .. "weapons without it", D.ch, D.s, D.id, D.key, #D.list))
    plan = H.gearPlan(stockOf(D.list), { tag = "gearplan drop", reserve = UNBOUNDED })
    H.assertEq(planned(plan, D.ch, D.s) == nil, true,
      "the sole holder of a break class is not planned a weapon that drops it for less than a key")
    H.assertEq(K ~= nil, true, "the ROM holds a stronger weapon that keeps a sole holder's class")
    H.log(string.format("[gearplan] 3: char %d slot %d holds $%02X, the only key $%X; %d stronger weapons with it",
      K.ch, K.s, K.id, K.key, #K.list))
    plan = H.gearPlan(stockOf(K.list), { tag = "gearplan keep", reserve = UNBOUNDED })
    local k = planned(plan, K.ch, K.s)
    H.assertEq(k ~= nil and (H.gearWeaponKeys(k.item) & K.key) == K.key, true,
      "the sole holder is planned a stronger weapon that keeps the class")
    H.log("[gearplan] ok")
  end),
})
