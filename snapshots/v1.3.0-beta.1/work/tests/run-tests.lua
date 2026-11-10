-- Run with Lua 5.3+: lua run-tests.lua [path/to/BluetoothPersonalLink]
local script = (arg and arg[0]) or "run-tests.lua"
local directory = script:match("^(.*[/\\])") or "./"
_TEST_MOD_ROOT = (arg and arg[1]) or (directory .. "../../package/bin/x64/plugins/cyber_engine_tweaks/mods/BluetoothPersonalLink")
_TEST_MOD_ROOT = _TEST_MOD_ROOT:gsub("\\", "/")
dofile(directory .. "test-bluetooth.lua")
print("Behavioral checks: " .. tostring(_TEST_CHECKS_JSON))
