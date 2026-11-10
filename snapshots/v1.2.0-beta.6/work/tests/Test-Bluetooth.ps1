param([string]$LuaLibraryPath = $env:BPL_LUA53_DLL)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$modRoot = Join-Path $taskRoot 'package\bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink'
$audioRoot = Join-Path $taskRoot 'package\r6\audioware\BluetoothPersonalLink'
# Media validation is performed separately by the package builder after authentic
# recordings are selected. These tests exercise the actual Lua against mock banks.
$assetChecks = @()
if ([string]::IsNullOrWhiteSpace($LuaLibraryPath)) { throw 'Pass -LuaLibraryPath pointing to a local Lua 5.3 DLL, or set BPL_LUA53_DLL. No Lua runtime is bundled.' }
$resolvedLuaPath = (Resolve-Path -LiteralPath $LuaLibraryPath -ErrorAction Stop).ProviderPath
$nativeSource = @'
using System;
using System.Runtime.InteropServices;
public static class BluetoothTestLua {
 [DllImport(@"__BPL_LUA_LIBRARY__", CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr luaL_newstate();
 [DllImport(@"__BPL_LUA_LIBRARY__", CallingConvention=CallingConvention.Cdecl)] public static extern void luaL_openlibs(IntPtr s);
 [DllImport(@"__BPL_LUA_LIBRARY__", CallingConvention=CallingConvention.Cdecl)] public static extern int luaL_loadbufferx(IntPtr s, byte[] b, UIntPtr n, string name, string mode);
 [DllImport(@"__BPL_LUA_LIBRARY__", CallingConvention=CallingConvention.Cdecl)] public static extern int lua_pcallk(IntPtr s, int a, int r, int e, IntPtr c, IntPtr k);
 [DllImport(@"__BPL_LUA_LIBRARY__", CallingConvention=CallingConvention.Cdecl)] public static extern int lua_getglobal(IntPtr s, string name);
 [DllImport(@"__BPL_LUA_LIBRARY__", CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr lua_tolstring(IntPtr s, int i, IntPtr len);
 [DllImport(@"__BPL_LUA_LIBRARY__", CallingConvention=CallingConvention.Cdecl)] public static extern void lua_close(IntPtr s);
}
'@
Add-Type -TypeDefinition ($nativeSource.Replace('__BPL_LUA_LIBRARY__', $resolvedLuaPath.Replace('"','""')))
if (!(Test-Path -LiteralPath (Join-Path $modRoot 'init.lua'))) { throw 'The candidate addon source is not ready yet.' }
$syntaxFiles = @(Get-ChildItem -LiteralPath $modRoot -Recurse -File -Filter '*.lua') + @(Get-Item -LiteralPath (Join-Path $PSScriptRoot 'test-bluetooth.lua'))
foreach ($file in $syntaxFiles) {
    $state = [BluetoothTestLua]::luaL_newstate()
    try {
        [byte[]]$bytes = [IO.File]::ReadAllBytes($file.FullName)
        $code = [BluetoothTestLua]::luaL_loadbufferx($state,$bytes,[UIntPtr]::new([uint64]$bytes.Length),$file.Name,'t')
        if ($code -ne 0) { throw [Runtime.InteropServices.Marshal]::PtrToStringAnsi([BluetoothTestLua]::lua_tolstring($state,-1,[IntPtr]::Zero)) }
        Write-Output ('PASS syntax: ' + $file.Name)
    } finally { [BluetoothTestLua]::lua_close($state) }
}
$prefix = "_TEST_MOD_ROOT='" + $modRoot.Replace('\','/').Replace("'","\'") + "'`n"
$source = $prefix + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'test-bluetooth.lua'))
[byte[]]$sourceBytes = [Text.Encoding]::UTF8.GetBytes($source)
$state = [BluetoothTestLua]::luaL_newstate()
try {
    [BluetoothTestLua]::luaL_openlibs($state)
    $code = [BluetoothTestLua]::luaL_loadbufferx($state,$sourceBytes,[UIntPtr]::new([uint64]$sourceBytes.Length),'bluetooth-tests','t')
    if ($code -eq 0) { $code = [BluetoothTestLua]::lua_pcallk($state,0,0,0,[IntPtr]::Zero,[IntPtr]::Zero) }
    if ($code -ne 0) { throw [Runtime.InteropServices.Marshal]::PtrToStringAnsi([BluetoothTestLua]::lua_tolstring($state,-1,[IntPtr]::Zero)) }
    $null = [BluetoothTestLua]::lua_getglobal($state,'_TEST_CHECKS_JSON')
    $checksText = [Runtime.InteropServices.Marshal]::PtrToStringAnsi([BluetoothTestLua]::lua_tolstring($state,-1,[IntPtr]::Zero))
    if (!$checksText) { throw 'The callback tests did not publish their assertions.' }
    $checks = $checksText | ConvertFrom-Json
    $report = [ordered]@{
        pass=$true;checkedUtc=[DateTime]::UtcNow.ToString('o')
        actualSourceSHA256=(Get-FileHash -LiteralPath (Join-Path $modRoot 'init.lua')).Hash
        syntaxFilesChecked=$syntaxFiles.Count;checks=$checks;behavioralGroups=$checks.Count;audioAssetChecks=$assetChecks
        parser='Installed Lua 5.3 DLL; Lua 5.1-compatible addon syntax'
        gameLaunched=$false;liveGameModified=$false;installerModified=$false
        limitation='Actual addon callbacks execute in an isolated Lua VM with mocked game/audio objects. Native hook timing, audible playback and NightCoop require an in-game test.'
    }
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'TEST-RESULTS.json'),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $report|ConvertTo-Json -Depth 6
} finally { [BluetoothTestLua]::lua_close($state) }
