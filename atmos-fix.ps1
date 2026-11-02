# Keeps the Logitech PRO X 2 LIGHTSPEED playback endpoint compatible with Dolby Atmos for Headphones.
#
# Logitech's driver package declares the headset as a 7.1 speaker (8-channel format, HX2E surround APO,
# logi_audio_surround upper filter). Windows does not offer headphone spatial sound on a 7.1 endpoint.
# This script rewrites those registry settings to plain stereo and is safe to run repeatedly: it only
# touches settings that are currently wrong.
#
#   (no switch)  apply the fix now                      -> reboot afterwards
#   -Check       report what would change, change nothing (works without admin)
#   -Install     copy to C:\ProgramData\AtmosFix, register a startup/logon task that re-applies the fix
#   -Uninstall   remove that task
#   -Restore     put back the original settings saved before the first change
#   -Quiet       log only (used by the scheduled task)
#
# Run from an elevated PowerShell (except -Check). Backups: C:\ProgramData\AtmosFix\backup

param([switch]$Install, [switch]$Uninstall, [switch]$Check, [switch]$Restore, [switch]$Quiet)

$ErrorActionPreference = 'Stop'
$root    = 'C:\ProgramData\AtmosFix'
$bakDir  = "$root\backup"
$aclDir  = "$root\acl"
$logFile = "$root\log.txt"
$taskName = 'AtmosFix'

$vidPid     = 'VID_046D&PID_0AF7'
$hx2eClsid  = '{A8CF6A24-68AE-499B-896A-0C631102AEB8}'
$hx2eNames  = '{d04e05a6-594b-4fb6-a80d-01af5eed7d1d},1', '{d04e05a6-594b-4fb6-a80d-01af5eed7d1d},5'
$filterName = 'logi_audio_surround'

$epRoot = 'SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
$dcRoot = 'SYSTEM\CurrentControlSet\Control\DeviceClasses\{6994ad04-93ef-11d0-a3cc-00a0c9223196}'
$enRoot = "SYSTEM\CurrentControlSet\Enum\USB\${vidPid}&MI_00"

$hklm = [Microsoft.Win32.Registry]::LocalMachine
$R    = [System.Security.AccessControl.RegistryRights]

function Log($msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    if (-not $Quiet) { Write-Host $msg }
    if (-not $Check -and (Test-Path $root)) { Add-Content -Path $logFile -Value $line -Encoding UTF8 }
}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Id($s) {
    $sha = [Security.Cryptography.SHA1]::Create()
    -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') })
}

Add-Type @'
using System; using System.Runtime.InteropServices;
public class Priv {
  [StructLayout(LayoutKind.Sequential, Pack = 1)] struct TokPriv { public int Count; public long Luid; public int Attr; }
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr tok);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool LookupPrivilegeValue(string host, string name, ref long luid);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr tok, bool disAll, ref TokPriv n, int len, IntPtr prev, IntPtr relen);
  public static bool Enable(string name) {
    IntPtr tok = IntPtr.Zero; TokPriv tp = new TokPriv(); tp.Count = 1; tp.Attr = 2;
    if (!OpenProcessToken(GetCurrentProcess(), 0x28, ref tok)) return false;
    if (!LookupPrivilegeValue(null, name, ref tp.Luid)) return false;
    return AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
  }
}
'@

# Takes ownership of $sub, runs $change on the opened key, then puts the saved security descriptor back.
function Edit-ProtectedKey($sub, [scriptblock]$change) {
    $aclFile = Join-Path $aclDir ((Get-Id $sub) + '.txt')
    $orig = $null
    if (Test-Path $aclFile) { $orig = (Get-Content $aclFile -Raw).Trim() }
    else {
        try {
            $k = $hklm.OpenSubKey($sub, 'ReadSubTree', $R::ReadPermissions)
            $orig = $k.GetAccessControl().GetSecurityDescriptorSddlForm('Owner,Group,Access'); $k.Close()
            Set-Content -Path $aclFile -Value $orig -Encoding ASCII
        } catch { Log "WARNING: could not read the original ACL of $sub; it will not be restored." }
    }
    $k = $hklm.OpenSubKey($sub, 'ReadWriteSubTree', $R::TakeOwnership)
    $acl = New-Object System.Security.AccessControl.RegistrySecurity
    $acl.SetOwner([Security.Principal.NTAccount]'BUILTIN\Administrators')
    $k.SetAccessControl($acl); $k.Close()

    $k = $hklm.OpenSubKey($sub, 'ReadWriteSubTree', $R::ChangePermissions)
    $acl = $k.GetAccessControl()
    $acl.SetAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule('BUILTIN\Administrators', 'FullControl', 'ContainerInherit', 'None', 'Allow')))
    $k.SetAccessControl($acl); $k.Close()

    $k = $hklm.OpenSubKey($sub, $true)
    try { & $change $k } finally { $k.Close() }

    if ($orig) {
        try {
            $k = $hklm.OpenSubKey($sub, 'ReadWriteSubTree', $R::ChangePermissions -bor $R::TakeOwnership)
            $acl = New-Object System.Security.AccessControl.RegistrySecurity
            $acl.SetSecurityDescriptorSddlForm($orig)
            $k.SetAccessControl($acl); $k.Close()
        } catch { Log "WARNING: ACL restore failed for $sub : $($_.Exception.Message)" }
    }
}

# Returns a copy of a WAVEFORMATEXTENSIBLE-bearing property blob rewritten as stereo, or $null if it is not a 7.1 format.
function ConvertTo-Stereo([byte[]]$b) {
    for ($o = 0; $o -le $b.Length - 40; $o++) {
        $tag = [BitConverter]::ToUInt16($b, $o); $ch = [BitConverter]::ToUInt16($b, $o + 2)
        $sr = [BitConverter]::ToUInt32($b, $o + 4); $bits = [BitConverter]::ToUInt16($b, $o + 14)
        if ($tag -eq 0xFFFE -and $ch -eq 8 -and [BitConverter]::ToUInt32($b, $o + 20) -eq 0x63F -and $bits -in 16, 24, 32) {
            $n = [byte[]]$b.Clone()
            $align = [uint16](2 * $bits / 8)
            [BitConverter]::GetBytes([uint16]2).CopyTo($n, $o + 2)
            [BitConverter]::GetBytes([uint32]($sr * $align)).CopyTo($n, $o + 8)
            [BitConverter]::GetBytes($align).CopyTo($n, $o + 12)
            [BitConverter]::GetBytes([uint32]3).CopyTo($n, $o + 20)
            return , $n
        }
    }
    return $null
}

function Open-Key($sub) { $hklm.OpenSubKey($sub) }

# Finds every registry key that carries a setting this script manages, with the operations that apply to it.
function Get-Targets {
    $t = @()

    $r = Open-Key $epRoot
    if ($r) {
        foreach ($g in $r.GetSubKeyNames()) {
            $p = Open-Key "$epRoot\$g\Properties"
            if (-not $p) { continue }
            $devId = [string]$p.GetValue('{b3f8fa53-0004-438e-9003-51a46e139bfc},2'); $p.Close()
            if ($devId -like "*$vidPid*") {
                $t += [pscustomobject]@{ Sub = "$epRoot\$g\Properties";   Ops = @('Format') }
                $t += [pscustomobject]@{ Sub = "$epRoot\$g\FxProperties"; Ops = @('Format', 'Hx2e') }
            }
        }
        $r.Close()
    }

    $d = Open-Key $dcRoot
    if ($d) {
        foreach ($n in $d.GetSubKeyNames()) {
            if ($n -like "*${vidPid}&MI_00*") {
                foreach ($leaf in @(@{ P = 'EP\0'; Ops = @('Format') }, @{ P = 'FX\0'; Ops = @('Hx2e') })) {
                    $sub = "$dcRoot\$n\#GLOBAL\Device Parameters\$($leaf.P)"
                    $k = Open-Key $sub
                    if ($k) { $k.Close(); $t += [pscustomobject]@{ Sub = $sub; Ops = $leaf.Ops } }
                }
            }
        }
        $d.Close()
    }

    $e = Open-Key $enRoot
    if ($e) {
        foreach ($inst in $e.GetSubKeyNames()) { $t += [pscustomobject]@{ Sub = "$enRoot\$inst"; Ops = @('Filter') } }
        $e.Close()
    }
    return $t
}

function Test-Pending($t) {
    $k = Open-Key $t.Sub
    if (-not $k) { return $false }
    try {
        foreach ($op in $t.Ops) {
            if ($op -eq 'Format') {
                foreach ($v in $k.GetValueNames()) {
                    $val = $k.GetValue($v)
                    if ($val -is [byte[]] -and (ConvertTo-Stereo $val)) { return $true }
                }
            }
            elseif ($op -eq 'Hx2e') {
                foreach ($v in $hx2eNames) { if ($k.GetValue($v) -eq $hx2eClsid) { return $true } }
            }
            elseif ($op -eq 'Filter') {
                $f = $k.GetValue('UpperFilters')
                if ($f -and ($f -contains $filterName)) { return $true }
            }
        }
    } finally { $k.Close() }
    return $false
}

function Backup-Once($sub) {
    $id = Get-Id $sub
    $file = "$bakDir\$id.reg"
    if (Test-Path $file) { return }
    reg export "HKLM\$sub" $file /y | Out-Null
    Add-Content -Path "$bakDir\index.txt" -Value "$id|$sub" -Encoding UTF8
    Log "Backed up HKLM\$sub"
}

function Invoke-Apply {
    $changed = 0
    foreach ($t in (Get-Targets)) {
        if (-not (Test-Pending $t)) { continue }
        if ($Check) { Log "WOULD CHANGE [$($t.Ops -join ',')] HKLM\$($t.Sub)"; $changed++; continue }
        Backup-Once $t.Sub
        $ops = $t.Ops
        Edit-ProtectedKey $t.Sub {
            param($k)
            if ($ops -contains 'Format') {
                foreach ($v in $k.GetValueNames()) {
                    $val = $k.GetValue($v)
                    if ($val -is [byte[]]) {
                        $new = ConvertTo-Stereo $val
                        if ($new) { $k.SetValue($v, $new, 'Binary'); Log "  format -> stereo: $v" }
                    }
                }
            }
            if ($ops -contains 'Hx2e') {
                foreach ($v in $hx2eNames) {
                    if ($k.GetValue($v) -eq $hx2eClsid) { $k.DeleteValue($v); Log "  removed HX2E APO: $v" }
                }
            }
            if ($ops -contains 'Filter') {
                $rest = @($k.GetValue('UpperFilters')) | Where-Object { $_ -and $_ -ne $filterName }
                if ($rest.Count -gt 0) { $k.SetValue('UpperFilters', [string[]]$rest, 'MultiString') } else { $k.DeleteValue('UpperFilters') }
                Log "  removed upper filter: $filterName"
            }
        }
        Log "Fixed HKLM\$($t.Sub)"
        $changed++
    }
    if ($changed -eq 0) { Log 'Nothing to change: the headset is already configured for stereo / Atmos.' }
    elseif ($Check) { Log "$changed key(s) need changes. Run without -Check as administrator to apply them." }
    else { Log "$changed key(s) changed. Reboot for the change to take effect." }
}

function Invoke-Restore {
    $index = "$bakDir\index.txt"
    if (-not (Test-Path $index)) { Log 'No backups found; nothing to restore.'; return }
    foreach ($line in Get-Content $index) {
        $id, $sub = $line -split '\|', 2
        $file = "$bakDir\$id.reg"
        if (-not (Test-Path $file)) { continue }
        Edit-ProtectedKey $sub { param($k) reg import $file 2>&1 | Out-Null }
        Log "Restored HKLM\$sub"
    }
    Log 'Restore finished. Reboot now. (Run -Uninstall as well if the scheduled task should stop re-applying the fix.)'
}

# ---- main ----
if (-not $Check -and -not (Test-Admin)) { Write-Error 'Run this script from an elevated PowerShell.' }
if (-not $Check) {
    foreach ($p in 'SeTakeOwnershipPrivilege', 'SeRestorePrivilege', 'SeBackupPrivilege') { [void][Priv]::Enable($p) }
    foreach ($d in $root, $bakDir, $aclDir) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
}

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Log "Scheduled task '$taskName' removed."
}
elseif ($Restore) { Invoke-Restore }
elseif ($Install) {
    $dest = "$root\atmos-fix.ps1"
    if ($PSCommandPath -ne $dest) { Copy-Item -Path $PSCommandPath -Destination $dest -Force }
    # The task runs as SYSTEM, so only SYSTEM and Administrators may modify the script.
    icacls $root /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$dest`" -Quiet"
    $triggers  = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogOn))
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Principal $principal -Force | Out-Null
    Log "Scheduled task '$taskName' registered (runs at startup and logon). Script copied to $dest"
    Invoke-Apply
}
else { Invoke-Apply }
