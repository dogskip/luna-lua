-- luacheck 설정.
-- https://luacheck.readthedocs.io/en/stable/config.html

std = "lua53"

-- 전역 변수 허용 목록.
globals = {
  "LRU",
  "LFU",
}

-- 무시할 경고.
ignore = {
  "212", -- 미사용 인자 (self 등).
  "213", -- 미사용 암묵적 인자.
}

-- 파일별 예외.
files["spec/"] = {
  -- 테스트에서는 전역 함수 사용 허용.
  globals = { "test", "passed", "failed" },
  ignore = { "112", "113" },
}

-- 최대 줄 길이.
max_line_length = 120
