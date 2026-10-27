-- @suite savestate=wor_doma
-- field_relicribbon.lua -- the relic rule keeps every Ribbon worn (#486 review; guidelines: a Ribbon goes on the
-- moment it's in the bag), read on wor_doma (gen_wor_doma: CELES, RELM, CYAN and TERRA beside the Falcon by Doma,
-- the bag as the leg left it).  On the play at 2db501e2 the plan there gave CYAN's Ribbon slot to a Genji Glove
-- and his other to a Hyper Wrist, and the Ribbon sat in the bag through Doma.
--
-- H.relicPlan reads only and logs its decisions; nothing here presses a button or writes emulated state.  The
-- expectation is the fixture's own: the Ribbons in the bag or on a seated member, against the seated members
-- who can wear one in a slot the plan does not keep (a relic it does not rank, or a two-weapon relic), each
-- asserted by name first; the plan puts on as many Ribbons as both allow, one a member.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_doma.mss.lua"
local RIBBON = 0xCA
local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM", "SETZER",
  "MOG", "GAU", "GOGO", "UMARO" }
local function prop(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function wears(ch, id) return (((prop(id, 1) | (prop(id, 2) << 8)) >> ch) & 1) == 1 end
local function relicAt(ch, s) return H.readByte(0x1600 + 37 * ch + 0x1F + s) end
local function kept(id)
  if id == 0xFF then return false end
  local cl = H.relicClass(id)
  return cl == nil or cl.hands == true
end
H.run({ maxFrames = 3000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    local act = H.readByte(0x1A6D) & 7
    local members, inBag = {}, H.invCountOf(RIBBON)
    local onSeated, able = 0, 0
    for ch = 0, 13 do
      if (H.readByte(0x1850 + ch) & 7) == act then
        members[#members + 1] = { ch, NAMES[ch] }
        if relicAt(ch, 4) == RIBBON or relicAt(ch, 5) == RIBBON then onSeated = onSeated + 1 end
        if wears(ch, RIBBON) and not (kept(relicAt(ch, 4)) and kept(relicAt(ch, 5))) then able = able + 1 end
      end
    end
    local have = inBag + onSeated
    H.log(string.format("[relicribbon] seated %d; Ribbons: %d in the bag, %d on seated members; %d seated member(s) "
      .. "can wear one in a slot the plan does not keep", #members, inBag, onSeated, able))
    H.assertEq(have >= 2, true, "the party holds two or more Ribbons in the bag or on seated members")
    H.assertEq(able >= 2, true, "two or more seated members can wear a Ribbon in a slot the plan does not keep")
    local plan = H.relicPlan(members, { tag = "relicribbon" })
    local planned = 0
    for _, p in ipairs(plan) do
      local n = 0
      for s = 4, 5 do if (p.want[s] or p.cur[s]) == RIBBON then n = n + 1 end end
      H.assertEq(n <= 1, true, string.format("%s is planned at most one Ribbon", p.name))
      planned = planned + n
    end
    local want = math.min(have, able)
    H.assertEq(planned, want, string.format("the plan puts on %d Ribbon(s): every Ribbon the seated party holds, while "
      .. "a seated member who can wear one goes without", want))
    H.log(string.format("[relicribbon] PASSED: %d Ribbon(s) planned on the seated party", planned))
  end),
})
