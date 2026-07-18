-- Sweeper 모듈 테스트.
-- 순수 Lua (busted 없음). lru_spec/lfu_spec과 동일한 패턴.

local LRU = require("lru")
local LFU = require("lfu")
local Sweeper = require("sweeper")

local passed = 0
local failed = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print(string.format("  ✓ %s", name))
  else
    failed = failed + 1
    print(string.format("  ✗ %s: %s", name, err))
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "assertion", tostring(b), tostring(a)), 2)
  end
end

local function assert_true(v, msg)
  if not v then
    error(msg or "expected true", 2)
  end
end

print("Sweeper tests:")

test("new creates sweeper with cache and interval", function()
  local c = LRU.new(5)
  local s = Sweeper.new(c, 10)
  assert_eq(s.interval, 10)
  assert_eq(s.running, false)
  assert_eq(s.sweeps, 0)
  assert_eq(s.purged, 0)
end)

test("new rejects non-table cache", function()
  local ok, _ = pcall(Sweeper.new, "notcache", 10)
  assert_true(not ok)
end)

test("new rejects cache without purge_expired", function()
  local ok, _ = pcall(Sweeper.new, { set = function() end }, 10)
  assert_true(not ok)
end)

test("new rejects non-positive interval", function()
  local c = LRU.new(5)
  local ok, _ = pcall(Sweeper.new, c, 0)
  assert_true(not ok)
  local ok2, _ = pcall(Sweeper.new, c, -1)
  assert_true(not ok2)
  local ok3, _ = pcall(Sweeper.new, c, "x")
  assert_true(not ok3)
end)

test("sweep removes expired entries and returns count", function()
  local c = LRU.new(5)
  c:set("a", 1, 1)
  c:set("b", 2)  -- TTL 없음
  -- a를 만료시킴.
  c.map["a"].expires_at = os.time() - 1
  local s = Sweeper.new(c, 10)
  local removed = s:sweep()
  assert_eq(removed, 1)
  assert_eq(c:get("a"), nil)
  assert_eq(c:get("b"), 2)
end)

test("sweep returns 0 when nothing expired", function()
  local c = LRU.new(5)
  c:set("a", 1)
  c:set("b", 2)
  local s = Sweeper.new(c, 10)
  local removed = s:sweep()
  assert_eq(removed, 0)
end)

test("sweep increments sweep counter", function()
  local c = LRU.new(5)
  local s = Sweeper.new(c, 10)
  s:sweep()
  s:sweep()
  assert_eq(s.sweeps, 2)
end)

test("sweep accumulates purged count", function()
  local c = LRU.new(5)
  c:set("a", 1, 1)
  c:set("b", 2, 1)
  c.map["a"].expires_at = os.time() - 1
  c.map["b"].expires_at = os.time() - 1
  local s = Sweeper.new(c, 10)
  local removed = s:sweep()
  assert_eq(removed, 2)
  assert_eq(s.purged, 2)
  -- 두 번째 스윕은 제거할 게 없음.
  s:sweep()
  assert_eq(s.purged, 2)
  assert_eq(s.sweeps, 2)
end)

test("sweep works with LFU cache", function()
  local c = LFU.new(5)
  c:set("a", 1, 1)
  c:set("b", 2)
  c.map["a"].expires_at = os.time() - 1
  local s = Sweeper.new(c, 10)
  local removed = s:sweep()
  assert_eq(removed, 1)
  assert_eq(c:get("a"), nil)
  assert_eq(c:get("b"), 2)
end)

test("on_evict not triggered by sweep (purge_expired 경로)", function()
  -- purge_expired는 on_evict를 호출하지 않음 (명시적 삭제와 동일 취급).
  -- 이 동작을 확인해 스윕이 의도치 않은 콜백을 발생시키지 않음을 검증.
  local c = LRU.new(5)
  local called = false
  c.on_evict = function()
    called = true
  end
  c:set("a", 1, 1)
  c.map["a"].expires_at = os.time() - 1
  local s = Sweeper.new(c, 10)
  s:sweep()
  assert_eq(called, false)
end)

test("start sets running flag and schedules next_run", function()
  local c = LRU.new(5)
  local s = Sweeper.new(c, 10)
  local before = os.time()
  s:start()
  assert_eq(s.running, true)
  assert_true(s.next_run ~= nil)
  assert_true(s.next_run >= before + 10)
  assert_true(s.next_run <= before + 11)
end)

test("start is idempotent", function()
  local c = LRU.new(5)
  local s = Sweeper.new(c, 10)
  assert_eq(s:start(), true)
  local first_run = s.next_run
  -- 이미 실행 중이면 no-op.
  assert_eq(s:start(), false)
  assert_eq(s.next_run, first_run)
end)

test("stop clears running flag and next_run", function()
  local c = LRU.new(5)
  local s = Sweeper.new(c, 10)
  s:start()
  s:stop()
  assert_eq(s.running, false)
  assert_eq(s.next_run, nil)
end)

test("stop is idempotent", function()
  local c = LRU.new(5)
  local s = Sweeper.new(c, 10)
  assert_eq(s:stop(), false)  -- 실행 중이 아니면 no-op.
end)

test("tick does nothing when not running", function()
  local c = LRU.new(5)
  c:set("a", 1, 1)
  c.map["a"].expires_at = os.time() - 1
  local s = Sweeper.new(c, 10)
  -- start() 호출 안 함.
  local removed = s:tick()
  assert_eq(removed, 0)
  -- 만료 항목이 그대로 남아있어야.
  assert_eq(c:len(), 1)
end)

test("tick does nothing before next_run", function()
  local c = LRU.new(5)
  c:set("a", 1, 1)
  c.map["a"].expires_at = os.time() - 1
  local s = Sweeper.new(c, 100)  -- 100초 후 스윕 예약.
  s:start()
  -- 예약 시각이 안 됐으므로 제거 안 함.
  local removed = s:tick()
  assert_eq(removed, 0)
  assert_eq(c:len(), 1)
end)

test("tick runs sweep when next_run reached", function()
  local c = LRU.new(5)
  c:set("a", 1, 1)
  c:set("b", 2)
  c.map["a"].expires_at = os.time() - 1
  local s = Sweeper.new(c, 1)
  s:start()
  -- next_run을 과거로 조작해 즉시 실행되게.
  s.next_run = os.time() - 1
  local removed = s:tick()
  assert_eq(removed, 1)
  assert_eq(c:get("a"), nil)
  assert_eq(c:get("b"), 2)
  -- 실행 후 next_run이 갱신되었는지.
  assert_true(s.next_run ~= nil)
  assert_true(s.next_run > os.time())
end)

test("tick reschedules after sweep", function()
  local c = LRU.new(5)
  local s = Sweeper.new(c, 5)
  s:start()
  -- next_run을 과거로 조작해 즉시 실행되게.
  local past = os.time() - 10
  s.next_run = past
  local before = os.time()
  s:tick()
  -- next_run이 now + interval 부근으로 갱신되었는지.
  assert_true(s.next_run ~= nil)
  assert_true(s.next_run >= before + 4)
  assert_true(s.next_run <= before + 6)
  -- 과거 시각이 아니라 미래로 예약되었는지.
  assert_true(s.next_run > past)
end)

test("stats returns sweep counters", function()
  local c = LRU.new(5)
  c:set("a", 1, 1)
  c.map["a"].expires_at = os.time() - 1
  local s = Sweeper.new(c, 10)
  s:sweep()
  local st = s:stats()
  assert_eq(st.sweeps, 1)
  assert_eq(st.purged, 1)
  assert_eq(st.interval, 10)
  assert_eq(st.running, false)
end)

test("reset_stats clears counters only", function()
  local c = LRU.new(5)
  local s = Sweeper.new(c, 10)
  s:start()
  s:sweep()
  s:reset_stats()
  local st = s:stats()
  assert_eq(st.sweeps, 0)
  assert_eq(st.purged, 0)
  -- 실행 상태는 유지.
  assert_eq(st.running, true)
end)

print(string.format("\nSweeper: %d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
