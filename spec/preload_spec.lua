-- Preload 모듈 테스트.
-- 순수 Lua (busted 없음). lru_spec/lfu_spec과 동일한 패턴.

local LRU = require("lru")
local LFU = require("lfu")
local Preload = require("preload")

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

print("Preload tests:")

test("load inserts all entries", function()
  local c = LRU.new(10)
  local entries = {
    { key = "a", value = 1 },
    { key = "b", value = 2 },
    { key = "c", value = 3 },
  }
  local r = Preload.load(c, entries)
  assert_eq(r.loaded, 3)
  assert_eq(r.rejected, 0)
  assert_eq(c:get("a"), 1)
  assert_eq(c:get("b"), 2)
  assert_eq(c:get("c"), 3)
  assert_eq(c:len(), 3)
end)

test("load with TTL applies expiry", function()
  local c = LRU.new(10)
  local entries = {
    { key = "a", value = 1, ttl = 100 },
  }
  Preload.load(c, entries)
  -- TTL이 설정되었는지 확인.
  local remaining = c:ttl("a")
  assert_true(remaining ~= nil)
  assert_true(remaining > 95 and remaining <= 100)
end)

test("load preserves existing entries", function()
  local c = LRU.new(10)
  c:set("existing", 99)
  local entries = {
    { key = "a", value = 1 },
    { key = "b", value = 2 },
  }
  Preload.load(c, entries)
  -- 기존 항목 보존.
  assert_eq(c:get("existing"), 99)
  assert_eq(c:get("a"), 1)
  assert_eq(c:get("b"), 2)
  assert_eq(c:len(), 3)
end)

test("load updates existing key on conflict", function()
  local c = LRU.new(10)
  c:set("a", 1)
  local entries = {
    { key = "a", value = 999 },
  }
  Preload.load(c, entries)
  assert_eq(c:get("a"), 999)
  assert_eq(c:len(), 1)
end)

test("load rejects invalid cache", function()
  local ok, _ = pcall(Preload.load, "notcache", {})
  assert_true(not ok)
end)

test("load rejects cache without set", function()
  local ok, _ = pcall(Preload.load, { purge_expired = function() end }, {})
  assert_true(not ok)
end)

test("load rejects non-table entries", function()
  local c = LRU.new(10)
  local ok, _ = pcall(Preload.load, c, "notarray")
  assert_true(not ok)
end)

test("load skips malformed entries", function()
  local c = LRU.new(10)
  local entries = {
    { key = "a", value = 1 },
    "not-a-table",  -- 건너뜀.
    { value = 2 },  -- key 없음, 건너뜀.
    { key = "b", value = 2 },
  }
  local r = Preload.load(c, entries)
  assert_eq(r.loaded, 2)
  assert_eq(r.rejected, 2)
  assert_eq(c:get("a"), 1)
  assert_eq(c:get("b"), 2)
end)

test("load with reject_on_overflow rejects excess", function()
  local c = LRU.new(2)
  local entries = {
    { key = "a", value = 1 },
    { key = "b", value = 2 },
    { key = "c", value = 3 },  -- 용량 초과, 거부.
  }
  local r = Preload.load(c, entries, { reject_on_overflow = true })
  assert_eq(r.loaded, 2)
  assert_eq(r.rejected, 1)
  assert_eq(c:get("a"), 1)
  assert_eq(c:get("b"), 2)
  assert_eq(c:get("c"), nil)
  assert_eq(c:len(), 2)
end)

test("load without reject_on_overflow evicts via cache policy", function()
  local c = LRU.new(2)
  local entries = {
    { key = "a", value = 1 },
    { key = "b", value = 2 },
    { key = "c", value = 3 },  -- LRU 정책에 따라 "a" 증발.
  }
  local r = Preload.load(c, entries)
  assert_eq(r.loaded, 3)
  assert_eq(r.rejected, 0)
  -- LRU라 "a"가 증발했을 것.
  assert_eq(c:get("a"), nil)
  assert_eq(c:get("b"), 2)
  assert_eq(c:get("c"), 3)
end)

test("load with reject_on_overflow updates existing key within capacity", function()
  local c = LRU.new(2)
  c:set("a", 1)
  -- "a" 갱신은 새 공간 필요 없음.
  local entries = {
    { key = "a", value = 100 },
    { key = "b", value = 2 },
  }
  local r = Preload.load(c, entries, { reject_on_overflow = true })
  assert_eq(r.loaded, 2)
  assert_eq(r.rejected, 0)
  assert_eq(c:get("a"), 100)
  assert_eq(c:get("b"), 2)
end)

test("load works with LFU cache", function()
  local c = LFU.new(5)
  local entries = {
    { key = "a", value = 1 },
    { key = "b", value = 2 },
  }
  local r = Preload.load(c, entries)
  assert_eq(r.loaded, 2)
  assert_eq(c:get("a"), 1)
  assert_eq(c:get("b"), 2)
end)

test("reload clears cache then loads", function()
  local c = LRU.new(10)
  c:set("old1", 1)
  c:set("old2", 2)
  local entries = {
    { key = "new1", value = 10 },
    { key = "new2", value = 20 },
  }
  local r = Preload.reload(c, entries)
  assert_eq(r.loaded, 2)
  assert_eq(c:get("old1"), nil)
  assert_eq(c:get("old2"), nil)
  assert_eq(c:get("new1"), 10)
  assert_eq(c:get("new2"), 20)
  assert_eq(c:len(), 2)
end)

test("reload rejects cache without clear", function()
  local ok, _ = pcall(Preload.reload, { set = function() end }, {})
  assert_true(not ok)
end)

test("load empty entries returns zeros", function()
  local c = LRU.new(5)
  local r = Preload.load(c, {})
  assert_eq(r.loaded, 0)
  assert_eq(r.rejected, 0)
  assert_eq(c:len(), 0)
end)

print(string.format("\nPreload: %d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
