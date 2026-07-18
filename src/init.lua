-- luna-lua — LRU/LFU 캐시 라이브러리.
--
-- 두 가지 캐시 정책을 제공한다:
--   - LRU: 가장 오래전에 접근한 항목 증발 (doubly linked list)
--   - LFU: 가장 적게 접근한 항목 증발 (빈도 기반, tie-break LRU)
--
-- 두 정책 모두 TTL 만료를 지원한다.
--
-- 부가 모듈:
--   - Sweeper: 백그라운드 스윕으로 만료 항목 주기적 제거
--   - Preload: 키-값 쌍 리스트 일괄 적재 (캐시 워밍)

local luna = {}

luna.LRU = require("lru")
luna.LFU = require("lfu")
luna.Sweeper = require("sweeper")
luna.Preload = require("preload")

return luna
