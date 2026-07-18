-- 캐시 프리로드 모듈.
--
-- 키-값 쌍 리스트를 한 번에 캐시에 적재한다. 시작 시 자주
-- 쓰는 항목을 미리 채워 넣어 콜드 캐시 미스를 줄이는 용도.
--
-- 용량 초과 시: 캐시 정책(LRU/LFU)에 따라 증발이 일어나므로,
-- 호출자가 명시적으로 거부하길 원하면 reject_on_overflow=true를
-- 전달한다. 이 경우 전체 적재를 시도하지 않고, 초과분만큼
-- 거부된 항목 수를 반환한다.
--
-- 보안: entries는 {key=..., value=..., ttl=...} 형태의 테이블.
-- 키/값 타입은 캐시 정책에 위임. nil 키는 건너뜀.

local Preload = {}
Preload.__index = Preload

-- 캐시에 entries를 일괄 적재.
-- cache: set(key, value, ttl) 메서드를 가진 캐시 객체.
-- entries: 배열 형태의 { {key=, value=, ttl=}, ... }.
-- opts: 선택적 옵션 테이블.
--   reject_on_overflow (bool): 용량 초과 시 거부 여부.
--     true면 적재 전 여유 공간을 확인해 초과분을 거부.
--     false/생략이면 캐시 정책에 맡김 (증발 발생).
--
-- 반환: { loaded = 적재 성공 수, rejected = 거부/건너뜀 수 }
function Preload.load(cache, entries, opts)
  if type(cache) ~= "table" then
    error("cache must be a table", 2)
  end
  if type(cache.set) ~= "function" then
    error("cache must implement set()", 2)
  end
  if type(entries) ~= "table" then
    error("entries must be a table (array)", 2)
  end

  opts = opts or {}
  local reject_on_overflow = opts.reject_on_overflow == true

  local loaded = 0
  local rejected = 0

  -- 용량 확인이 필요한 경우, 캐시의 capacity/len을 사용.
  -- capacity가 없는 캐시(무제한)면 거부 로직은 스킵.
  local capacity = cache.capacity
  local has_capacity = type(capacity) == "number" and capacity > 0

  for _, entry in ipairs(entries) do
    if type(entry) ~= "table" or entry.key == nil then
      -- 잘못된 항목은 건너뜀.
      rejected = rejected + 1
    elseif reject_on_overflow and has_capacity then
      -- 여유 공간 확인 후 적재.
      local current = cache:len() or 0
      -- 이미 같은 키가 있으면 갱신이므로 추가 공간 불필요.
      local exists = false
      if type(cache.has) == "function" then
        exists = cache:has(entry.key)
      end
      if exists then
        cache:set(entry.key, entry.value, entry.ttl)
        loaded = loaded + 1
      elseif current < capacity then
        cache:set(entry.key, entry.value, entry.ttl)
        loaded = loaded + 1
      else
        rejected = rejected + 1
      end
    else
      -- 캐시 정책에 맡김 (증발 허용).
      cache:set(entry.key, entry.value, entry.ttl)
      loaded = loaded + 1
    end
  end

  return { loaded = loaded, rejected = rejected }
end

-- 캐시를 비우고 entries를 처음부터 적재 (하드 리셋 후 프리로드).
-- cache: clear()와 set()을 지원하는 캐시 객체.
-- entries: Preload.load와 동일한 형태.
-- 반환: Preload.load와 동일.
function Preload.reload(cache, entries)
  if type(cache) ~= "table" then
    error("cache must be a table", 2)
  end
  if type(cache.clear) ~= "function" then
    error("cache must implement clear()", 2)
  end
  cache:clear()
  return Preload.load(cache, entries)
end

return Preload
