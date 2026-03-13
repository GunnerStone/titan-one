<#
  _bridge.ps1 — 32-bit PowerShell bridge for titan_one Python package.
  Communicates via JSON lines on stdin/stdout.

  IMPORTANT: gcapi_Write only persists for one device poll cycle.
  We run a background thread that continuously writes the current output
  state to the device every ~10ms. Commands just update the state buffer.

  Launched automatically by TitanOneController — not meant to be run directly.
#>
param([string]$DllPath)

$ErrorActionPreference = "Stop"

# ---------- Load DLL via P/Invoke + output loop helper ----------
$escaped = $DllPath.Replace('\','\\')

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class GCAPI
{
    public const int OUTPUT_TOTAL = 36;

    [DllImport("$escaped", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcdapi_Load")]
    public static extern byte Load();

    [DllImport("$escaped", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcdapi_Unload")]
    public static extern void Unload();

    [DllImport("$escaped", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcapi_IsConnected")]
    public static extern byte IsConnected();

    [DllImport("$escaped", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcapi_GetFWVer")]
    public static extern ushort GetFWVer();

    [DllImport("$escaped", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcapi_Write")]
    public static extern byte Write(sbyte[] output);

    [DllImport("$escaped", CallingConvention = CallingConvention.StdCall, EntryPoint = "gcdapi_DevicePID")]
    public static extern ushort DevicePID();
}

public static class OutputLoop
{
    private static sbyte[] _state = new sbyte[GCAPI.OUTPUT_TOTAL];
    private static readonly object _lock = new object();
    private static Thread _thread;
    private static volatile bool _running;

    public static void SetState(sbyte[] newState)
    {
        lock (_lock)
        {
            Array.Copy(newState, _state, GCAPI.OUTPUT_TOTAL);
        }
    }

    public static void Start()
    {
        _running = true;
        _thread = new Thread(() =>
        {
            sbyte[] buf = new sbyte[GCAPI.OUTPUT_TOTAL];
            while (_running)
            {
                lock (_lock)
                {
                    Array.Copy(_state, buf, GCAPI.OUTPUT_TOTAL);
                }
                try { GCAPI.Write(buf); } catch {}
                Thread.Sleep(8);  // ~120Hz write rate
            }
        });
        _thread.IsBackground = true;
        _thread.Start();
    }

    public static void Stop()
    {
        _running = false;
        if (_thread != null) _thread.Join(1000);
    }
}
"@

# ---------- Helpers ----------
function Send-Response($obj) {
    $json = $obj | ConvertTo-Json -Compress
    [Console]::Out.WriteLine($json)
    [Console]::Out.Flush()
}

function Send-Ok($extra) {
    $resp = @{ status = "ok" }
    if ($extra) { foreach ($k in $extra.Keys) { $resp[$k] = $extra[$k] } }
    Send-Response $resp
}

function Send-Error($msg) {
    Send-Response @{ status = "error"; message = $msg }
}

# Track state
$apiLoaded = $false

# ---------- Command loop ----------
try {
    while ($true) {
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { break }  # stdin closed
        $line = $line.Trim()
        if ($line -eq "") { continue }

        try {
            $msg = $line | ConvertFrom-Json
        } catch {
            Send-Error "Invalid JSON: $line"
            continue
        }

        switch ($msg.cmd) {
            "connect" {
                try {
                    $loadOk = [GCAPI]::Load()
                    if (-not $loadOk) {
                        Send-Error "gcdapi_Load() failed. Ensure Gtuner is closed."
                        continue
                    }
                    $apiLoaded = $true

                    # Wait for device with retries
                    $connected = $false
                    for ($i = 0; $i -lt 15; $i++) {
                        if ([GCAPI]::IsConnected()) { $connected = $true; break }
                        Start-Sleep -Milliseconds 300
                    }
                    if (-not $connected) {
                        [GCAPI]::Unload()
                        $apiLoaded = $false
                        Send-Error "Device not detected. Check USB connection and ensure Gtuner is closed."
                        continue
                    }

                    # Start the continuous output loop
                    [OutputLoop]::Start()

                    $fw = [GCAPI]::GetFWVer()
                    $dpid = [GCAPI]::DevicePID()
                    Send-Ok @{ firmware = [int]$fw; device_pid = "0x$($dpid.ToString('X4'))" }
                } catch {
                    Send-Error "Connect failed: $_"
                }
            }

            "disconnect" {
                try {
                    [OutputLoop]::Stop()
                    if ($apiLoaded) {
                        [GCAPI]::Unload()
                        $apiLoaded = $false
                    }
                    Send-Ok
                } catch {
                    Send-Error "Disconnect failed: $_"
                }
            }

            "write" {
                # Update the shared state buffer. The background thread
                # continuously writes it to the device.
                try {
                    $output = New-Object sbyte[] ([GCAPI]::OUTPUT_TOTAL)
                    if ($msg.values) {
                        foreach ($prop in $msg.values.PSObject.Properties) {
                            $idx = [int]$prop.Name
                            $val = [sbyte]([math]::Max(-100, [math]::Min(100, [int]$prop.Value)))
                            $output[$idx] = $val
                        }
                    }
                    [OutputLoop]::SetState($output)
                    Send-Ok
                } catch {
                    Send-Error "Write failed: $_"
                }
            }

            "tap" {
                # Brief press: set state to pressed, sleep a few write cycles,
                # then set state back to zeros.
                try {
                    $output = New-Object sbyte[] ([GCAPI]::OUTPUT_TOTAL)
                    if ($msg.values) {
                        foreach ($prop in $msg.values.PSObject.Properties) {
                            $idx = [int]$prop.Name
                            $val = [sbyte]([math]::Max(-100, [math]::Min(100, [int]$prop.Value)))
                            $output[$idx] = $val
                        }
                    }
                    [OutputLoop]::SetState($output)
                    # Hold for ~2 write cycles (~16ms) so the device sees it
                    Start-Sleep -Milliseconds 20
                    $zeros = New-Object sbyte[] ([GCAPI]::OUTPUT_TOTAL)
                    [OutputLoop]::SetState($zeros)
                    Send-Ok
                } catch {
                    Send-Error "Tap failed: $_"
                }
            }

            "is_connected" {
                try {
                    $c = [GCAPI]::IsConnected()
                    Send-Ok @{ connected = [bool]$c }
                } catch {
                    Send-Error "IsConnected failed: $_"
                }
            }

            "ping" {
                Send-Ok
            }

            "quit" {
                [OutputLoop]::Stop()
                if ($apiLoaded) {
                    [GCAPI]::Unload()
                    $apiLoaded = $false
                }
                Send-Ok
                break
            }

            default {
                Send-Error "Unknown command: $($msg.cmd)"
            }
        }
    }
} finally {
    try { [OutputLoop]::Stop() } catch {}
    if ($apiLoaded) {
        try { [GCAPI]::Unload() } catch {}
    }
}
