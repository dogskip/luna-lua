# luna-lua

Lua로 구현한 LRU/LFU 캐시 라이브러리. TTL 만료를 지원한다.

## 특징

- **LRU**: doubly linked list + hash map으로 O(1) 접근
- **LFU**: 빈도 기반 증발, tie-break으로 LRU
- **TTL**: 항목별 만료 시간 설정
- **purge_expired**: 만료 항목 일괄 제거
- **입력 검증**: capacity, TTL 검증

## 사용법

### LRU

```lua
local LRU = require("lru")
local cache = LRU.new(100)  -- 최대 100항목

cache:set("key", "value")
cache:set("temp", "data", 60)  -- 60초 후 만료

local val = cache:get("key")  -- "value"
cache:delete("key")
cache:purge_expired()  -- 만료 항목 제거
```

### LFU

```lua
local LFU = require("lfu")
local cache = LFU.new(100)

cache:set("key", "value")
cache:get("key")  -- 빈도 증가
print(cache:frequency("key"))  -- 현재 빈도
```

## 알고리즘

### LRU (Least Recently Used)

가장 오래전에 접근한 항목을 증발시킨다.

- doubly linked list로 접근 순서 유지 (head = 최근, tail = 오래됨)
- hash map으로 키 → 노드 매핑 (O(1) 조회)
- 접근 시 해당 노드를 head로 이동
- 용량 초과 시 tail 증발

### LFU (Least Frequently Used)

가장 적게 접근한 항목을 증발시킨다.

- 각 노드에 frequency 카운터
- get 시 frequency 증가
- 용량 초과 시 최소 frequency 항목 증발
- 빈도 같으면 last_access가 오래된 것 (LRU tie-break)

### TTL

- `set(key, value, ttl)`에서 ttl초 후 만료
- `get` 시 만료 확인, 만료면 자동 삭제 후 nil 반환
- `purge_expired`로 일괄 제거

## 보안 고려사항

- **입력 검증**: capacity는 양수, TTL은 양수만 허용. 잘못된 값은 error.
- **메모리 한계**: capacity 상한으로 무한 증가 방지.
- **만료 처리**: 만료 항목이 get 시 자동 제거되어 오래된 데이터 반환 방지.

## 설계 결정

### 왜 LFU가 O(n)인가?

LFU의 증발은 전체 순회로 최소 빈도를 찾는다. 빈도별 버킷 구조를 쓰면 O(1)이 가능하지만, Lua 테이블 순회는 빠르고 캐시 크기가 작으면 충분하다. 대규모용으로는 버킷 구조로 확장 가능하다.

### 왜 순수 Lua인가?

외부 의존성(luarocks, busted) 없이 동작하도록 했다. 테스트도 순수 Lua `assert`로 작성해 어디서든 실행 가능하다.

## 개발

```bash
# 테스트 실행
LUA_PATH="src/?.lua;;" lua spec/lru_spec.lua
LUA_PATH="src/?.lua;;" lua spec/lfu_spec.lua
```

## 라이선스

MIT
