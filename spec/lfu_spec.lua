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

print(string.format("\nLFU: %d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
