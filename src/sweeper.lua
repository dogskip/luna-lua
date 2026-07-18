-- 백그라운드 스윕 모듈.
--
-- 주기적으로 캐시의 purge_expired()를 호출해 TTL 만료 항목을
-- 제거한다. Lua는 단일 스레드이므로 진짜 백그라운드 스레드가
-- 아니라, start() 시 매 호출마다 os.time()으로 다음 스윕 시각을
-- 계산하고, tick()에서 만료 여부를 판단해 실행하는 구조다.
--
-- 사용 패턴:
--   local sweeper = Sweeper.new(cache, 30)  -- 30초 간격
--   sweeper:start()
--   ... (메인 루프에서 주기적으로 sweeper:tick() 호출) ...
--   sweeper:stop()
--
-- 또는 수동으로 sweep()을 직접 호출해도 된다.
--
-- 보안: 캐시 객체의 메서드만 호출하므로 외부 입력 경로 없음.
-- interval은 양수 검증. 타이머 핸들은 stop() 시 반드시 정리.

local Sweeper = {}
Sweeper.__index = Sweeper

-- 새 스윕 인스턴스 생성.
-- cache: purge_expired() 메서드를 가진 캐시 객체 (LRU/LFU).
-- interval: 스윕 간격 (초). 양수여야 함.
function Sweeper.new(cache, interval)
  if type(cache) ~= "table" then
    error("cache must be a table", 2)
  end
  if type(cache.purge_expired) ~= "function" then
    error("cache must implement purge_expired()", 2)
  end
  if type(interval) ~= "number" or interval <= 0 then
    error("interval must be a positive number", 2)
  end
  local self = setmetatable({}, Sweeper)
  self.cache = cache
  self.interval = interval
  self.running = false
  self.next_run = nil  -- 다음 스윕 예정 시각 (os.time 기준)
  -- 누적 통계.
  self.sweeps = 0  -- 실행한 스윕 횟수
  self.purged = 0  -- 제거한 항목 총합
  return self
end

-- 한 번의 스윕 실행. 만료 항목 제거 후 제거된 수 반환.
-- 캐시의 purge_expired()를 호출하고 통계를 갱신.
function Sweeper:sweep()
  local removed = self.cache:purge_expired()
  if type(removed) ~= "number" then
    removed = 0
  end
  self.sweeps = self.sweeps + 1
  self.purged = self.purged + removed
  return removed
end

-- 자동 스윕 시작. 다음 실행 시각을 interval 초 뒤로 예약.
-- 이미 실행 중이면 no-op.
function Sweeper:start()
  if self.running then
    return false
  end
  self.running = true
  self.next_run = os.time() + self.interval
  return true
end

-- 자동 스윕 중지. 타이머 상태 정리.
-- 실행 중이 아니면 no-op.
function Sweeper:stop()
  if not self.running then
    return false
  end
  self.running = false
  self.next_run = nil
  return true
end

-- 자동 스윕 틱. 메인 루프에서 주기적으로 호출.
-- 예약 시각이 지났으면 sweep() 실행 후 다음 예약 잡기.
-- 실행 여부와 관계없이, 이번 틱에서 제거한 항목 수 반환
-- (실행 안 했으면 0).
function Sweeper:tick()
  if not self.running then
    return 0
  end
  local now = os.time()
  if self.next_run == nil or now < self.next_run then
    return 0
  end
  -- 스윕 실행 후 다음 예약.
  local removed = self:sweep()
  self.next_run = now + self.interval
  return removed
end

-- 스윕 통계 반환.
function Sweeper:stats()
  return {
    sweeps = self.sweeps,
    purged = self.purged,
    running = self.running,
    interval = self.interval,
    next_run = self.next_run,
  }
end

-- 통계 카운터만 초기화 (실행 상태는 유지).
function Sweeper:reset_stats()
  self.sweeps = 0
  self.purged = 0
end

return Sweeper
