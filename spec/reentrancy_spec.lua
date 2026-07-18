-- 재진입 가드 테스트 (이슈 #6).
-- 순수 Lua (busted 없이). assert 기반.
--
-- on_evict 콜백이 캐시 메서드를 다시 호출하면 연결 리스트가
-- 깨지거나 무한 루프에 빠질 수 있다. _busy 카운터로 이를 감지.

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

local function assert_error(fn, msg)
  local ok = pcall(fn)
  if ok then
    error(msg or "expected error, but call succeeded", 2)
  end
end

print("reentrancy guard:")

test("정상 사용 시 가드가 간섭하지 않음", function()
  local cache = LRU.new(3)
  cache:set("a", 1)
  cache:set("b", 2)
  assert_eq(cache:get("a"), 1)
  assert_eq(cache:get("b"), 2)
  assert_eq(cache._busy, 0, "busy after operation")
end)

test("on_evict에서 get 재호출 시 에러", function()
  local cache = LRU.new(2)
  cache:set("a", 1)
  cache:set("b", 2)
  cache.on_evict = function(_)
    cache:get("a")
  end
  assert_error(function()
    cache:set("c", 3)
  end, "reentrant get should error")
end)

test("on_evict에서 set 재호출 시 에러", function()
  local cache = LRU.new(2)
  cache:set("a", 1)
  cache:set("b", 2)
  cache.on_evict = function(_)
    cache:set("x", 999)
  end
  assert_error(function()
    cache:set("c", 3)
  end, "reentrant set should error")
end)

test("on_evict에서 delete 재호출 시 에러", function()
  local cache = LRU.new(2)
  cache:set("a", 1)
  cache:set("b", 2)
  cache.on_evict = function(_)
    cache:delete("a")
  end
  assert_error(function()
    cache:set("c", 3)
  end, "reentrant delete should error")
end)

test("콜백 없으면 재진입 에러 없음", function()
  local cache = LRU.new(2)
  cache:set("a", 1)
  cache:set("b", 2)
  local ok = pcall(function()
    cache:set("c", 3)
  end)
  assert_true(ok, "no callback should not error")
  assert_eq(cache:get("a"), nil, "a should be evicted")
  assert_eq(cache:get("b"), 2)
  assert_eq(cache:get("c"), 3)
end)

test("가드 후 캐시 정상 복귀", function()
  local cache = LRU.new(2)
  cache:set("a", 1)
  cache:set("b", 2)
  cache.on_evict = function()
    cache:get("a")
  end
  local ok = pcall(function()
    cache:set("c", 3)
  end)
  assert_true(not ok, "should have errored")
  assert_eq(cache._busy, 0, "busy should reset after error")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
