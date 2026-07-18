-- LRU (Least Recently Used) 캐시.
--
-- O(1) 접근을 위해 doubly linked list + hash map을 사용한다.
-- hash map은 키 → 노드, linked list는 접근 순서를 유지한다.
-- 가장 최근에 접근한 노드가 head, 가장 오래된 것이 tail.
-- 용량 초과 시 tail을 증발시킨다.
--
-- 동시성: Lua는 단일 스레드이므로 별도 락 불필요. 단, 코루틴
-- 양보 중에 상태가 바뀔 수 있으므로, 콜백(evict) 내에서 양보하지
-- 않는 것이 안전하다.

local LRU = {}
LRU.__index = LRU

-- 노드 구조체.
local Node = {}
Node.__index = Node

function Node.new(key, value, ttl)
  local self = setmetatable({}, Node)
  self.key = key
  self.value = value
  self.prev = nil
  self.next = nil
  -- TTL: 만료 시각 (os.time() 기준). nil이면 만료 없음.
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

-- 새 LRU 캐시 생성.
-- capacity: 최대 항목 수. 0 이하면 에러.
function LRU.new(capacity)
  if type(capacity) ~= "number" or capacity <= 0 then
    error("capacity must be a positive number", 2)
  end
  local self = setmetatable({}, LRU)
  self.capacity = capacity
  self.size = 0
  self.map = {}  -- key → Node
  self.head = nil  -- 가장 최근
  self.tail = nil  -- 가장 오래된
  return self
end

-- 노드를 head로 이동 (가장 최근으로).
function LRU:_move_to_head(node)
  if node == self.head then
    return
  end
  -- 현재 위치에서 제거.
  self:_unlink(node)
  self:_push_front(node)
end

-- 노드를 리스트에서 분리.
function LRU:_unlink(node)
  if node.prev then
    node.prev.next = node.next
  else
    self.head = node.next
  end
  if node.next then
    node.next.prev = node.prev
  else
    self.tail = node.prev
  end
  node.prev = nil
  node.next = nil
end

-- 노드를 head 앞에 삽입.
function LRU:_push_front(node)
  node.next = self.head
  node.prev = nil
  if self.head then
    self.head.prev = node
  end
  self.head = node
  if self.tail == nil then
    self.tail = node
  end
end

-- 키로 값 조회. 접근 시 head로 이동.
-- 만료된 항목은 자동 삭제 후 nil 반환.
function LRU:get(key)
  local node = self.map[key]
  if node == nil then
    return nil
  end
  if node:is_expired() then
    self:_remove_node(node)
    return nil
  end
  self:_move_to_head(node)
  return node.value
end

-- 키-값 설정. 기존 키면 갱신, 아니면 추가.
-- 용량 초과 시 tail(LRU) 증발.
function LRU:set(key, value, ttl)
  local node = self.map[key]
  if node then
    -- 갱신.
    node.value = value
    if ttl and ttl > 0 then
      node.expires_at = os.time() + ttl
    else
      node.expires_at = nil
    end
    self:_move_to_head(node)
    return
  end

  -- 새 노드.
  node = Node.new(key, value, ttl)
  self.map[key] = node
  self:_push_front(node)
  self.size = self.size + 1

  -- 용량 초과 시 tail 증발.
  if self.size > self.capacity then
    self:_evict_tail()
  end
end

-- tail(LRU 항목) 증발.
function LRU:_evict_tail()
  if self.tail == nil then
    return
  end
  self:_remove_node(self.tail)
end

-- 노드 제거.
function LRU:_remove_node(node)
  self:_unlink(node)
  self.map[node.key] = nil
  self.size = self.size - 1
end

-- 키 삭제.
function LRU:delete(key)
  local node = self.map[key]
  if node then
    self:_remove_node(node)
    return true
  end
  return false
end

-- 만료된 모든 항목 제거. 반환값: 제거된 항목 수.
function LRU:purge_expired()
  local now = os.time()
  local count = 0
  local node = self.tail
  while node do
    local prev = node.prev
    if node:is_expired(now) then
      self:_remove_node(node)
      count = count + 1
    end
    node = prev
  end
  return count
end

-- 모든 키 반환 (순서 보장 안 됨).
function LRU:keys()
  local keys = {}
  for k, _ in pairs(self.map) do
    table.insert(keys, k)
  end
  return keys
end

-- 현재 크기.
function LRU:len()
  return self.size
end

-- 캐시 비우기.
function LRU:clear()
  self.map = {}
  self.head = nil
  self.tail = nil
  self.size = 0
end

return LRU
