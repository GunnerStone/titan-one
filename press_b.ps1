<#
  press_b.ps1 - Send a Nintendo Switch 'B' button press via Titan One GCAPI

  IMPORTANT: This must be run under 32-bit PowerShell because gcdapi.dll is 32-bit.
  Launch with:
    C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File press_b.ps1
#>

# Resolve absolute path to the DLL
$dllDir  = (Resolve-Path (Join-Path $PSScriptRoot "..\Gtuner3")).Path
$dllPath = Join-Path $dllDir "gcdapi.dll"
$escapedPath = $dllPath.Replace('\','\\')

Write-Host "DLL: $dllPath"
Write-Host "Arch: $([IntPtr]::Size * 8)-bit process"

if ([IntPtr]::Size -ne 4) {
    Write-Host "ERROR: This script must run in a 32-bit process. Use:" -ForegroundColor Red
    Write-Host '  C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File press_b.ps1' -ForegroundColor Yellow
    exit 1
}

# Define P/Invoke signatures
$csCode = @"
using System;
using System.Runtime.InteropServices;

public static class GCAPI
{
    public const int SWITCH_HOME = 0;
    public const int SWITCH_MINUS = 1;
    public const int SWITCH_PLUS = 2;
    public const int SWITCH_R = 3;
    public const int SWITCH_ZR = 4;
    public const int SWITCH_SR = 5;
    public const int SWITCH_L = 6;
    public const int SWITCH_ZL = 7;
    public const int SWITCH_SL = 8;
    public const int SWITCH_RX = 9;
    public const int SWITCH_RY = 10;
    public const int SWITCH_LX = 11;
    public const int SWITCH_LY = 12;
    public const int SWITCH_UP = 13;
    public const int SWITCH_DOWN = 14;
    public const int SWITCH_LEFT = 15;
    public const int SWITCH_RIGHT = 16;
    public const int SWITCH_X = 17;
    public const int SWITCH_A = 18;
    public const int SWITCH_B = 19;
    public const int SWITCH_Y = 20;
    public const int SWITCH_CAPTURE = 27;
    public const int OUTPUT_TOTAL = 36;

    [DllImport("$escapedPath", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcdapi_Load")]
    public static extern byte Load();

    [DllImport("$escapedPath", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcdapi_Unload")]
    public static extern void Unload();

    [DllImport("$escapedPath", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcapi_IsConnected")]
    public static extern byte IsConnected();

    [DllImport("$escapedPath", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcapi_GetFWVer")]
    public static extern ushort GetFWVer();

    [DllImport("$escapedPath", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcapi_Write")]
    public static extern byte Write(sbyte[] output);

    [DllImport("$escapedPath", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcdapi_DevicePID")]
    public static extern ushort DevicePID();

    [DllImport("$escapedPath", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcdapi_LoadDevice")]
    public static extern byte LoadDevice(ushort pid);
}
"@

Add-Type -TypeDefinition $csCode

# 1. Load the API
Write-Host "`nInitializing GCDAPI..."
$loadResult = [GCAPI]::Load()
if ($loadResult -eq 0) {
    Write-Host "gcdapi_Load() failed, trying gcdapi_LoadDevice(0x0003)..." -ForegroundColor Yellow
    $loadResult = [GCAPI]::LoadDevice(0x0003)
}
if ($loadResult -eq 0) {
    Write-Host "ERROR: gcdapi_Load() failed. Make sure Gtuner is NOT running and the device is plugged in." -ForegroundColor Red
    exit 1
}
Write-Host "GCDAPI loaded successfully." -ForegroundColor Green

# 2. Check connection (with retry - device may need a moment)
$devicePid = [GCAPI]::DevicePID()
Write-Host "Device PID: 0x$($devicePid.ToString('X4'))"

$connected = 0
for ($i = 0; $i -lt 10; $i++) {
    $connected = [GCAPI]::IsConnected()
    if ($connected) { break }
    Write-Host "  Waiting for device... (attempt $($i+1)/10)"
    Start-Sleep -Milliseconds 500
}

if ($connected -eq 0) {
    Write-Host "ERROR: No Titan One device detected after retries." -ForegroundColor Red
    Write-Host "  - Make sure Gtuner3 is CLOSED (Direct API conflicts with it)" -ForegroundColor Yellow
    Write-Host "  - Device must be connected to PC via the PROG USB port" -ForegroundColor Yellow
    Write-Host "  - Try unplugging and replugging the device" -ForegroundColor Yellow
    [GCAPI]::Unload()
    exit 1
}

$fw = [GCAPI]::GetFWVer()
Write-Host "Device connected! Firmware: $fw" -ForegroundColor Green

# 3. Press B button (value 100 = fully pressed)
Write-Host "`nPressing Nintendo Switch B button..."
$output = New-Object sbyte[] ([GCAPI]::OUTPUT_TOTAL)
$output[[GCAPI]::SWITCH_B] = [sbyte]100
$pressOk = [GCAPI]::Write($output)
Write-Host "Write (press): $(if ($pressOk) {'OK'} else {'FAILED'})"

# 4. Hold for 200ms
Start-Sleep -Milliseconds 200

# 5. Release (all zeros)
Write-Host "Releasing B button..."
$release = New-Object sbyte[] ([GCAPI]::OUTPUT_TOTAL)
$releaseOk = [GCAPI]::Write($release)
Write-Host "Write (release): $(if ($releaseOk) {'OK'} else {'FAILED'})"

# 6. Cleanup
Write-Host "`nUnloading GCDAPI..."
[GCAPI]::Unload()
Write-Host "Done!" -ForegroundColor Green
