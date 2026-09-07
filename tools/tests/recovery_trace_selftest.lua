-- @manual standalone: lua tools/tests/recovery_trace_selftest.lua
-- Ledger regressions without Mesen. No engine/game state is fabricated.
-- Only the library's top-level input callback registration needs a stub.
emu = {eventType={inputPolled=1}, addEventCallback=function() return 1 end}
local H = dofile('tools/tests/lib/ot6.lua')
local events = {}
local t = H.newRecoveryTrace('test', function(e) events[#events + 1] = e end)
local function plan(actor, frame, all)
  t.plan(actor, {kind='heal', spell=45, target=1, all=all,
    boostLeft=all and 2 or 0, reason='in danger'}, frame)
end
plan(0, 10)
t.confirm(0, 20, 2, 0)
t.confirm(0, 30, 2, 0)
assert(#events == 3 and events[3].event == 'confirm')
-- A changed HP cannot resolve a plan that was never accepted or started.
t.resolve(0, 40, {100, 200, 300, 400}, 20, 2)
assert(#events == 3)
t.drop(0, 50, 'cursor_stalled')
assert(events[4].event == 'drop' and events[4].elapsed_frames == 40)
plan(0, 60, true)
plan(1, 61)
t.submit(0, 70, 2, 45, 15)
t.start(0, 80, 2, 47, 15, {10,20,30,40}, 50, 2)
t.resolve(1, 81, {20,30,40,50}, 10, 0) -- unrelated actor: no attribution
assert(events[#events].event == 'start')
t.resolve(0, 100, {10,120,130,40}, 10, 2)
local r = events[#events]
assert(r.event == 'resolve' and r.attack == 47 and r.requested == 45)
assert(r.hp_net == '0,100,100,0' and r.mp_net == -40 and r.all)
t.close(110, 'battle_ended')
assert(events[#events].event == 'drop' and events[#events].actor == 1)
plan(0, 120)
t.submit(0, 130, 2, 45, 2)
t.close(140, 'battle_ended')
assert(events[#events].event == 'unresolved')
assert(events[#events].last_stage == 'submit')
-- Planning again while the engine queues a prior action is not cancellation.
plan(0, 150)
t.submit(0, 160, 2, 45, 2)
local queuedID = events[#events].id
plan(0, 165)
t.drop(0, 170, 'actor_changed')
t.start(0, 180, 2, 45, 2, {10,20,30,40}, 20, 1)
t.resolve(0, 190, {10,20,30,40}, 15, 1) -- zero-effect command still resolved
assert(events[#events].id == queuedID)
assert(events[#events].event == 'resolve' and events[#events].hp_net == '0,0,0,0')
local n = #events
t.close(200, 'state_reload')
t.close(201, 'run_ended')
assert(#events == n) -- no duplicate terminal records
print('recovery_trace_selftest: PASS')
