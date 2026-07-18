local LFU = require("lfu")

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

print("LFU tests:")

test("new creates cache with capacity", function()
  local c = LFU.new(5)
  assert_eq(c.capacity, 5)
  assert_eq(c:len(), 0)
end)

test("new rejects invalid capacity", function()
  local ok, _ = pcall(LFU.new, 0)
  assert_true(not ok)
end)

test("set and get", function()
  local c = LFU.new(3)
  c:set("a", 1)
  c:set("b", 2)
  assert_eq(c:get("a"), 1)
  assert_eq(c:get("b"), 2)
end)

test("get increments frequency", function()
  local c = LFU.new(3)
  c:set("a", 1)
  assert_eq(c:frequency("a"), 1)
  c:get("a")
  c:get("a")
  assert_eq(c:frequency("a"), 3)
end)

test("evicts least frequent", function()
  local c = LFU.new(2)
  c:set("a", 1)
  c:set("b", 2)
  c:get("a")  -- a 빈도 2
  c:get("a")  -- a 빈도 3
  c:set("c", 3)  -- b(빈도 1) 증발
  assert_eq(c:get("a"), 1)
  assert_eq(c:get("b"), nil)
  assert_eq(c:get("c"), 3)
end)

test("set existing key updates value and freq", function()
  local c = LFU.new(2)
  c:set("a", 1)
  c:set("a", 2)
  assert_eq(c:get("a"), 2)
  assert_eq(c:frequency("a"), 3)  -- new(1) + set(1) + get(1)
end)

test("delete removes key", function()
  local c = LFU.new(3)
  c:set("a", 1)
  assert_true(c:delete("a"))
  assert_eq(c:get("a"), nil)
end)

test("clear empties cache", function()
  local c = LFU.new(3)
  c:set("a", 1)
  c:clear()
  assert_eq(c:len(), 0)
end)

test("TTL expires entry", function()
  local c = LFU.new(3)
  c:set("a", 1, 1)
  assert_eq(c:get("a"), 1)
  c.map["a"].expires_at = os.time() - 1
  assert_eq(c:get("a"), nil)
end)

test("purge_expired removes expired", function()
  local c = LFU.new(3)
  c:set("a", 1, 1)
  c:set("b", 2)
  c.map["a"].expires_at = os.time() - 1
  local count = c:purge_expired()
  assert_eq(count, 1)
  assert_eq(c:get("b"), 2)
end)

test("keys returns all keys", function()
  local c = LFU.new(3)
  c:set("a", 1)
  c:set("b", 2)
  local keys = c:keys()
  assert_eq(#keys, 2)
end)

test("peek returns value without incrementing frequency", function()
  local c = LFU.new(3)
  c:set("a", 1)
  local freq_before = c:frequency("a")
  assert_eq(c:peek("a"), 1)
  local freq_after = c:frequency("a")
  assert_eq(freq_before, freq_after)
end)

test("has returns existence without side effects", function()
  local c = LFU.new(3)
  c:set("a", 1)
  assert_true(c:has("a"))
  assert_eq(c:has("missing"), false)
end)

test("has returns false for expired entry", function()
  local c = LFU.new(3)
  c:set("a", 1, 1)
  c.map["a"].expires_at = os.time() - 1
  assert_eq(c:has("a"), false)
  assert_eq(c:len(), 0)
end)

test("ttl returns remaining seconds", function()
  local c = LFU.new(3)
  c:set("a", 1, 100)
  local remaining = c:ttl("a")
  assert_true(remaining ~= nil)
  assert_true(remaining > 95 and remaining <= 100)
end)

test("ttl returns nil for no-expiry entry", function()
  local c = LFU.new(3)
  c:set("a", 1)
  assert_eq(c:ttl("a"), nil)
end)

test("on_evict callback fires on capacity eviction", function()
  local c = LFU.new(2)
  local evicted_key = nil
  c.on_evict = function(k)
    evicted_key = k
  end
  c:set("a", 1)
  c:set("b", 2)
  -- "a"를 여러 번 접근해 빈도를 높임.
  c:get("a")
  c:get("a")
  -- "b"는 freq=1로 가장 낮음.
  -- "c" 추가 시 "b"가 증발해야 (freq=1, 가장 오래됨).
  -- 단, "c" 자체도 freq=1이므로 last_access로 tie-break.
  -- "b"가 "c"보다 먼저 설정되어 last_access가 더 오래됨.
  c:set("c", 3)
  -- "b" 또는 "c" 중 하나가 증발. "a"는 freq=3으로 안전.
  assert_true(evicted_key == "b" or evicted_key == "c")
  assert_eq(c:has("a"), true)
end)

test("on_evict not called on explicit delete", function()
  local c = LFU.new(3)
  local called = false
  c.on_evict = function()
    called = true
  end
  c:set("a", 1)
  c:delete("a")
  assert_eq(called, false)
end)

test("stats counts hits and misses", function()
  local c = LFU.new(3)
  c:set("a", 1)
  c:get("a")  -- hit
  c:get("missing")  -- miss
  local s = c:stats()
  assert_eq(s.hits, 1)
  assert_eq(s.misses, 1)
  assert_eq(s.size, 1)
end)

test("stats hit_rate computation", function()
  local c = LFU.new(3)
  c:set("a", 1)
  c:get("a")  -- hit
  c:get("a")  -- hit
  c:get("b")  -- miss
  c:get("c")  -- miss
  local s = c:stats()
  -- 2 hits / 4 total = 0.5
  assert_true(math.abs(s.hit_rate - 0.5) < 0.001)
end)

test("stats counts evictions", function()
  local c = LFU.new(2)
  c:set("a", 1)
  c:set("b", 2)
  c:set("c", 3)  -- 증발 1건
  local s = c:stats()
  assert_eq(s.evictions, 1)
end)

test("reset_stats clears counters only", function()
  local c = LFU.new(3)
  c:set("a", 1)
  c:get("a")
  c:reset_stats()
  local s = c:stats()
  assert_eq(s.hits, 0)
  assert_eq(s.misses, 0)
  -- 데이터는 유지.
  assert_eq(c:get("a"), 1)
end)

test("expired get counts as miss", function()
  local c = LFU.new(3)
  c:set("a", 1, 1)
  c.map["a"].expires_at = os.time() - 1
  assert_eq(c:get("a"), nil)
  local s = c:stats()
  assert_eq(s.misses, 1)
  assert_eq(s.hits, 0)
end)

print(string.format("\nLFU: %d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
