-- LFU (Least Frequently Used) 캐시.
--
-- 접근 빈도가 가장 낮은 항목을 증발시킨다. 빈도가 같으면
-- 가장 오래된 것(LRU)을 증발시킨다 (tie-breaking).
--
-- 구현: 빈도별로 linked list를 유지하는 대신, 단순화해
-- 각 노드에 frequency를 두고, 증발 시 전체 순회로 최소 빈도를 찾는다.
-- O(n) 증발이지만, Lua 테이블 순회는 빠르고 캐시 크기가 작으면 충분하다.
-- 대규모용으로는 빈도별 버킷 구조가 더 효율적이다.

local LFU = {}
LFU.__index = LFU

local Node = {}
Node.__index = Node

function Node.new(key, value, ttl)
  local self = setmetatable({}, Node)
  self.key = key
  self.value = value
  self.freq = 1  -- 접근 빈도
  self.last_access = os.time()  -- tie-breaking용
  self.expires_at = nil
  if ttl and ttl > 0 then
    self.expires_at = os.time() + ttl
  end
  return self
end

function Node:is_expired(now)
  if self.expires_at == nil then
    return false
  end
  return (now or os.time()) >= self.expires_at
end

function LFU.new(capacity)
  if type(capacity) ~= "number" or capacity <= 0 then
    error("capacity must be a positive number", 2)
  end
  local self = setmetatable({}, LFU)
  self.capacity = capacity
  self.size = 0
  self.map = {}
  self.on_evict = nil  -- 증발 콜백: function(key, value)
  return self
end

function LFU:get(key)
  local node = self.map[key]
  if node == nil then
    return nil
  end
  if node:is_expired() then
    self:_remove(key)
    return nil
  end
  -- 접근 빈도 증가.
  node.freq = node.freq + 1
  node.last_access = os.time()
  return node.value
end

-- 빈도 증가 없이 값만 조회.
function LFU:peek(key)
  local node = self.map[key]
  if node == nil then
    return nil
  end
  if node:is_expired() then
    self:_remove(key)
    return nil
  end
  return node.value
end

-- 키 존재 여부. 빈도 갱신 없음.
function LFU:has(key)
  local node = self.map[key]
  if node == nil then
    return false
  end
  if node:is_expired() then
    self:_remove(key)
    return false
  end
  return true
end

-- 남은 TTL (초). 만료 없음이면 nil, 만료 시 0.
function LFU:ttl(key)
  local node = self.map[key]
  if node == nil then
    return nil
  end
  if node.expires_at == nil then
    return nil
  end
  local now = os.time()
  local remaining = node.expires_at - now
  if remaining <= 0 then
    self:_remove(key)
    return 0
  end
  return remaining
end

function LFU:set(key, value, ttl)
  local node = self.map[key]
  if node then
    node.value = value
    node.freq = node.freq + 1
    node.last_access = os.time()
    if ttl and ttl > 0 then
      node.expires_at = os.time() + ttl
    end
    return
  end

  node = Node.new(key, value, ttl)
  self.map[key] = node
  self.size = self.size + 1

  if self.size > self.capacity then
    self:_evict_lfu()
  end
end

-- 최소 빈도 항목 증발. 빈도 같으면 가장 오래된 것.
function LFU:_evict_lfu()
  local min_freq = nil
  local min_key = nil
  local min_time = nil
  local min_node = nil

  for k, n in pairs(self.map) do
    if min_freq == nil or n.freq < min_freq or
       (n.freq == min_freq and n.last_access < min_time) then
      min_freq = n.freq
      min_key = k
      min_time = n.last_access
      min_node = n
    end
  end

  if min_key then
    self.map[min_key] = nil
    self.size = self.size - 1
    -- 용량 초과 증발 시 콜백 호출.
    if self.on_evict and min_node then
      self.on_evict(min_key, min_node.value)
    end
  end
end

function LFU:_remove(key)
  if self.map[key] then
    self.map[key] = nil
    self.size = self.size - 1
    return true
  end
  return false
end

function LFU:delete(key)
  return self:_remove(key)
end

function LFU:purge_expired()
  local now = os.time()
  local count = 0
  local to_remove = {}
  for k, n in pairs(self.map) do
    if n:is_expired(now) then
      table.insert(to_remove, k)
    end
  end
  for _, k in ipairs(to_remove) do
    self:_remove(k)
    count = count + 1
  end
  return count
end

function LFU:keys()
  local keys = {}
  for k, _ in pairs(self.map) do
    table.insert(keys, k)
  end
  return keys
end

function LFU:len()
  return self.size
end

function LFU:clear()
  self.map = {}
  self.size = 0
end

-- 항목의 현재 빈도 조회 (테스트/디버그용).
function LFU:frequency(key)
  local node = self.map[key]
  return node and node.freq or nil
end

return LFU
