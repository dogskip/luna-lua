-- 순수 Lua 테스트 (busted 없이).
-- assert 기반. 실패 시 error로 중단.

local LRU = require("lru")

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

print("LRU tests:")

test("new creates cache with capacity", function()
  local c = LRU.new(5)
  assert_eq(c.capacity, 5)
  assert_eq(c:len(), 0)
end)

test("new rejects invalid capacity", function()
  local ok, _ = pcall(LRU.new, 0)
  assert_true(not ok)
  local ok2, _ = pcall(LRU.new, -1)
  assert_true(not ok2)
  local ok3, _ = pcall(LRU.new, "x")
  assert_true(not ok3)
end)

test("set and get", function()
  local c = LRU.new(3)
  c:set("a", 1)
  c:set("b", 2)
  assert_eq(c:get("a"), 1)
  assert_eq(c:get("b"), 2)
end)

test("evicts LRU when capacity exceeded", function()
  local c = LRU.new(2)
  c:set("a", 1)
  c:set("b", 2)
  c:set("c", 3)  -- a 증발
  assert_eq(c:get("a"), nil)
  assert_eq(c:get("b"), 2)
  assert_eq(c:get("c"), 3)
end)

test("get updates recency", function()
  local c = LRU.new(2)
  c:set("a", 1)
  c:set("b", 2)
  c:get("a")  -- a를 최근으로
  c:set("c", 3)  -- b 증발 (a가 더 최근)
  assert_eq(c:get("a"), 1)
  assert_eq(c:get("b"), nil)
  assert_eq(c:get("c"), 3)
end)

test("set existing key updates value", function()
  local c = LRU.new(2)
  c:set("a", 1)
  c:set("a", 2)
  assert_eq(c:get("a"), 2)
  assert_eq(c:len(), 1)
end)

test("delete removes key", function()
  local c = LRU.new(3)
  c:set("a", 1)
  assert_true(c:delete("a"))
  assert_eq(c:get("a"), nil)
  assert_eq(c:len(), 0)
end)

test("delete returns false for missing key", function()
  local c = LRU.new(3)
  assert_eq(c:delete("nope"), false)
end)

test("clear empties cache", function()
  local c = LRU.new(3)
  c:set("a", 1)
  c:set("b", 2)
  c:clear()
  assert_eq(c:len(), 0)
  assert_eq(c:get("a"), nil)
end)

test("keys returns all keys", function()
  local c = LRU.new(3)
  c:set("a", 1)
  c:set("b", 2)
  local keys = c:keys()
  assert_eq(#keys, 2)
end)

test("TTL expires entry", function()
  local c = LRU.new(3)
  -- TTL 1초. os.time() 기반이라 테스트는 1초 대기 필요.
  -- 여기서는 만료 로직만 검증 (직접 노드 조작).
  c:set("a", 1, 1)
  assert_eq(c:get("a"), 1)
  -- 노드의 expires_at를 과거로 조작해 만료 시뮬레이션.
  local node = c.map["a"]
  node.expires_at = os.time() - 1
  assert_eq(c:get("a"), nil)
end)

test("purge_expired removes expired entries", function()
  local c = LRU.new(3)
  c:set("a", 1, 1)
  c:set("b", 2)  -- TTL 없음
  -- a를 만료시킴.
  c.map["a"].expires_at = os.time() - 1
  local count = c:purge_expired()
  assert_eq(count, 1)
  assert_eq(c:get("a"), nil)
  assert_eq(c:get("b"), 2)
end)

test("peek returns value without updating order", function()
  local c = LRU.new(3)
  c:set("a", 1)
  c:set("b", 2)
  c:set("c", 3)
  -- peek("a")는 접근 순서를 갱신하지 않아야.
  assert_eq(c:peek("a"), 1)
  -- "d" 추가 시 가장 오래된 "a"가 증발해야 (peek이 순서를 안 바꿨으므로).
  c:set("d", 4)
  assert_eq(c:peek("a"), nil)
  assert_eq(c:peek("b"), 2)
end)

test("has returns existence without side effects", function()
  local c = LRU.new(3)
  c:set("a", 1)
  assert_true(c:has("a"))
  assert_eq(c:has("missing"), false)
end)

test("has returns false for expired entry", function()
  local c = LRU.new(3)
  c:set("a", 1, 1)
  c.map["a"].expires_at = os.time() - 1
  assert_eq(c:has("a"), false)
  -- 만료 항목이 제거되었는지.
  assert_eq(c:len(), 0)
end)

test("ttl returns remaining seconds", function()
  local c = LRU.new(3)
  c:set("a", 1, 100)
  local remaining = c:ttl("a")
  assert_true(remaining ~= nil)
  assert_true(remaining > 95 and remaining <= 100)
end)

test("ttl returns nil for no-expiry entry", function()
  local c = LRU.new(3)
  c:set("a", 1)
  assert_eq(c:ttl("a"), nil)
end)

test("ttl returns 0 for expired entry", function()
  local c = LRU.new(3)
  c:set("a", 1, 1)
  c.map["a"].expires_at = os.time() - 1
  assert_eq(c:ttl("a"), 0)
end)

test("on_evict callback fires on capacity eviction", function()
  local c = LRU.new(2)
  local evicted_key = nil
  local evicted_val = nil
  c.on_evict = function(k, v)
    evicted_key = k
    evicted_val = v
  end
  c:set("a", 1)
  c:set("b", 2)
  c:set("c", 3)  -- "a" 증발 예상.
  assert_eq(evicted_key, "a")
  assert_eq(evicted_val, 1)
end)

test("on_evict not called on explicit delete", function()
  local c = LRU.new(3)
  local called = false
  c.on_evict = function()
    called = true
  end
  c:set("a", 1)
  c:delete("a")
  assert_eq(called, false)
end)

test("stats counts hits and misses", function()
  local c = LRU.new(3)
  c:set("a", 1)
  c:get("a")  -- hit
  c:get("a")  -- hit
  c:get("missing")  -- miss
  local s = c:stats()
  assert_eq(s.hits, 2)
  assert_eq(s.misses, 1)
  assert_eq(s.size, 1)
  assert_eq(s.capacity, 3)
end)

test("stats hit_rate computation", function()
  local c = LRU.new(3)
  c:set("a", 1)
  c:get("a")  -- hit
  c:get("b")  -- miss
  local s = c:stats()
  -- 1 hit / 2 total = 0.5
  assert_true(math.abs(s.hit_rate - 0.5) < 0.001)
end)

test("stats counts evictions", function()
  local c = LRU.new(2)
  c:set("a", 1)
  c:set("b", 2)
  c:set("c", 3)  -- "a" 증발
  c:set("d", 4)  -- "b" 증발
  local s = c:stats()
  assert_eq(s.evictions, 2)
end)

test("stats hit_rate zero when no access", function()
  local c = LRU.new(3)
  c:set("a", 1)
  local s = c:stats()
  assert_eq(s.hit_rate, 0)
  assert_eq(s.hits, 0)
  assert_eq(s.misses, 0)
end)

test("reset_stats clears counters only", function()
  local c = LRU.new(3)
  c:set("a", 1)
  c:get("a")
  c:get("missing")
  c:reset_stats()
  local s = c:stats()
  assert_eq(s.hits, 0)
  assert_eq(s.misses, 0)
  -- 데이터는 유지.
  assert_eq(c:get("a"), 1)
end)

test("expired get counts as miss", function()
  local c = LRU.new(3)
  c:set("a", 1, 1)
  c.map["a"].expires_at = os.time() - 1
  assert_eq(c:get("a"), nil)
  local s = c:stats()
  assert_eq(s.misses, 1)
  assert_eq(s.hits, 0)
end)

print(string.format("\nLRU: %d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
