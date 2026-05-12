param(
    # Triggers the installation process
    [switch]$Install,

    # Triggers the uninstall process
    [switch]$Uninstall,

    # Selects the logging level to use (0=FATAL | 1=ERROR | 2=WARNING | 3=INFO | 4=DEBUG)
    [int]$LOG = 2
)

$LOG_CONFIG = @(
    @{
        BACKGROUND = "DarkRed";
        FOREGROUND = "White";
        LABEL = "FATAL"
    };
    @{
        BACKGROUND = "Black";
        FOREGROUND = "Red";
        LABEL = "ERROR"
    };
    @{
        BACKGROUND = "Black";
        FOREGROUND = "Yellow";
        LABEL = "WARNING"
    };
    @{
        BACKGROUND = "Black";
        FOREGROUND = "Green";
        LABEL = "INFO"
    };
    @{
        BACKGROUND = "Black";
        FOREGROUND = "White";
        LABEL = "DEBUG"
    };
);

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ================== Hotkey Configuration ==================
$MuteHotkey       = 'Ctrl+Alt+M'
$VolumeUpHotkey   = 'Ctrl+Alt+Up'
$VolumeDownHotkey = 'Ctrl+Alt+Down'
$QuitHotkey       = 'Ctrl+Alt+Q'
$HotkeyNoRepeat   = $true
# ==========================================================

$TaskName  = 'VolumeHotkeys'
$StateDir  = Join-Path $env:LOCALAPPDATA 'VolumeHotkeys'
$PidFile   = Join-Path $StateDir 'VolumeHotkeys.pid'
$MutexName = 'Local\VolumeHotkeys_Instance'

function Is-Admin {
    # Checks if the current process is running with elevated privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    return $isAdmin
}

function Write-Log {
    param(
        [string]$Message,
        [int]$Level
    )
    if($Level -le $LOG) {
        $label = $LOG_CONFIG[$Level]["LABEL"];

        # Writes the message
        $now = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
        Write-Host "[$now] $label | $Message" -ForegroundColor $LOG_CONFIG[$Level]["FOREGROUND"] -BackgroundColor $LOG_CONFIG[$Level]["BACKGROUND"]
    }
}

function Write-Debug {
    param([string]$Message)
    Write-Log $Message 4
}

function Write-Info {
    param([string]$Message)
    Write-Log $Message 3
}

function Write-Warning {
    param([string]$Message)
    Write-Log $Message 2
}

function Write-Error {
    param([string]$Message)
    Write-Log $Message 1
}

function Write-Fatal {
    param([string]$Message)
    Write-Log $Message 0
}

function Ensure-StateDir {
    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
}

function Get-ScriptPath {
    if ($PSCommandPath) {
        return (Resolve-Path -LiteralPath $PSCommandPath).Path
    }

    if ($MyInvocation.MyCommand.Path) {
        return (Resolve-Path -LiteralPath $MyInvocation.MyCommand.Path).Path
    }

    throw "The script must be saved to disk before installation."
}

function Write-PidFile {
    Ensure-StateDir
    Set-Content -LiteralPath $PidFile -Value $PID -Encoding ASCII -Force
}

function Remove-PidFile {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

function Stop-RunningInstance {
    Write-Debug "Stopping running instance"

    if (-not (Test-Path -LiteralPath $PidFile)) {
        write-debug "No PID file detected"
        return
    }

    try {
        $runningPid = [int]((Get-Content -LiteralPath $PidFile -Raw).Trim())
    }
    catch {
        write-debug "Failed to retrieve the contents of PID file: $($_.Exception.Message)"
        return
    }

    if ($runningPid -gt 0 -and $runningPid -ne $PID) {
        try {
            Stop-Process -Id $runningPid -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Error "Failed to stop running process: $($_.Exception.Message)"
        }
    }
}

function Register-Task {
    if(Is-Admin) {
        return Admin-Register-Task
    } else {
        return User-Register-Task
    }
}

function Admin-Register-Task {
    Write-Info "Registering task as ADMIN"

    $scriptPath = Get-ScriptPath
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    $action = New-ScheduledTaskAction `
        -Execute $powershellExe `
        -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    write-debug "action created"

    $trigger = New-ScheduledTaskTrigger -AtLogOn
    write-debug "trigger created"

    $principal = New-ScheduledTaskPrincipal `
        -UserId $env:USERNAME `
        -LogonType Interactive `
        -RunLevel Limited
    write-debug "principal created"

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Force | Out-Null
    Write-Info "Task Registered."

    try {
        Write-Info "Starting registered task"
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
    catch {
        Write-Error "Could not start registered task: $($_.Exception.Message)"
    }
}

function User-Register-Task {
    Write-Info "Registering task as USER"
    
    $scriptPath = Get-ScriptPath
    $startupFolder = [System.Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder "$TaskName.lnk"
    
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

    write-debug "Creating shortcut in Startup folder"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershellExe
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = Split-Path $scriptPath
    $shortcut.WindowStyle = 7 # Minimized/Hidden
    $shortcut.Save()

    Start-Process $shortcutPath
    
    Write-Info "Task registered in Startup folder: $shortcutPath"
}

function Unregister-Task {
    if(Is-Admin) {
        return Admin-Unregister-Task
    } else {
        return User-Unregister-Task
    }
}

function Admin-Unregister-Task {
    Write-Info "Removing registered task as ADMIN"

    try {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
    catch {
        Write-Error "Unable to Stop scheduled task: $($_.Exception.Message)"
    }

    write-debug "unregistering scheduled task"
    Unregister-ScheduledTask `
        -TaskName $TaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue | Out-Null
}

function User-Unregister-Task {
    Write-Info "Removing registered task as USER"

    Stop-RunningInstance

    $startupFolder = [System.Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder "$TaskName.lnk"

    if (Test-Path -LiteralPath $shortcutPath) {
        try {
            Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction Stop
            Write-Info "Task unregistered: Removed $shortcutPath"
        }
        catch {
            Write-Warning "Could not remove shortcut: $($_.Exception.Message)"
        }
    } else {
        Write-Info "No startup task found to unregister."
    }

    if (Test-Path -LiteralPath $StateDir) {
        Remove-Item -LiteralPath $StateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-Modifiers {
    param([string[]]$Parts)

    $mods = 0
    $seen = @()

    foreach ($part in $Parts) {
        $token = $part.Trim().ToUpperInvariant()

        if ([string]::IsNullOrWhiteSpace($token)) {
            throw "Invalid hotkey: empty modifier token."
        }

        if ($seen -contains $token) {
            throw "Invalid hotkey: duplicate modifier '$token'."
        }

        $seen += $token

        switch ($token) {
            'CTRL'    { $mods = $mods -bor [Native]::MOD_CONTROL; continue }
            'CONTROL' { $mods = $mods -bor [Native]::MOD_CONTROL; continue }
            'ALT'     { $mods = $mods -bor [Native]::MOD_ALT; continue }
            'SHIFT'   { $mods = $mods -bor [Native]::MOD_SHIFT; continue }
            'WIN'     { $mods = $mods -bor [Native]::MOD_WIN; continue }
            default   { throw "Unknown modifier: $part" }
        }
    }

    return [uint32]$mods
}

function Get-KeyCode {
    param([string]$Key)

    $token = $Key.Trim().ToUpperInvariant()

    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "Invalid hotkey: missing key."
    }

    switch ($token) {
        'UP'       { return [System.UInt16]0x26 }
        'DOWN'     { return [System.UInt16]0x28 }
        'LEFT'     { return [System.UInt16]0x25 }
        'RIGHT'    { return [System.UInt16]0x27 }
        'SPACE'    { return [System.UInt16]0x20 }
        'TAB'      { return [System.UInt16]0x09 }
        'ENTER'    { return [System.UInt16]0x0D }
        'ESC'      { return [System.UInt16]0x1B }
        'ESCAPE'   { return [System.UInt16]0x1B }
        'BACKSPACE'{ return [System.UInt16]0x08 }
        'DELETE'   { return [System.UInt16]0x2E }
        'INSERT'   { return [System.UInt16]0x2D }
        'HOME'     { return [System.UInt16]0x24 }
        'END'      { return [System.UInt16]0x23 }
        'PGUP'     { return [System.UInt16]0x21 }
        'PGDN'     { return [System.UInt16]0x22 }
    }

    if ($token -match '^F([1-9]|1[0-9]|2[0-4])$') {
        return [System.UInt16](0x70 + [int]$Matches[1] - 1)
    }

    if ($token.Length -eq 1) {
        return [System.UInt16][char]$token
    }

    throw "Unsupported key: $Key"
}

function Parse-Hotkey {
    param([string]$Spec)

    if ([string]::IsNullOrWhiteSpace($Spec)) {
        throw "Hotkey specification cannot be empty."
    }

    $parts = $Spec -split '\+'

    if ($parts.Count -lt 1) {
        throw "Invalid hotkey: $Spec"
    }

    $key = $parts[-1].Trim()
    if ([string]::IsNullOrWhiteSpace($key)) {
        throw "Invalid hotkey: '$Spec' does not end with a key."
    }

    $mods = @()
    if ($parts.Count -gt 1) {
        $mods = $parts[0..($parts.Count - 2)]
    }

    return @{
        Modifiers = Get-Modifiers $mods
        KeyCode   = [uint32](Get-KeyCode $key)
    }
}

Add-Type @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class Native
{
    public const int WM_HOTKEY = 0x0312;

    public const uint MOD_ALT     = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT   = 0x0004;
    public const uint MOD_WIN     = 0x0008;
    public const uint MOD_NOREPEAT = 0x4000;

    public const uint INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_KEYUP = 0x0002;

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT
    {
        public uint type;
        public INPUTUNION U;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT
    {
        public System.UInt16 wVk;
        public System.UInt16 wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(
        IntPtr hWnd,
        int id,
        uint fsModifiers,
        uint vk
    );

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(
        IntPtr hWnd,
        int id
    );

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetMessage(
        out MSG lpMsg,
        IntPtr hWnd,
        uint wMsgFilterMin,
        uint wMsgFilterMax
    );

    [DllImport("user32.dll")]
    public static extern bool TranslateMessage(
        [In] ref MSG lpMsg
    );

    [DllImport("user32.dll")]
    public static extern IntPtr DispatchMessage(
        [In] ref MSG lpMsg
    );

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(
        uint nInputs,
        INPUT[] pInputs,
        int cbSize
    );
}
"@

if ($Install) {
    Register-Task
    Write-Info ""
    Write-Info "Installed successfully."
    Write-Info "Task name: $TaskName"
    Write-Info ""
    exit 0
}

if ($Uninstall) {
    Unregister-Task
    Stop-RunningInstance
    Remove-PidFile

    Write-Info ""
    Write-Info "Uninstalled successfully."
    Write-Info ""
    exit 0
}

Write-Info "Creating bindings"
$bindings = @(
    @{
        Id     = 1
        Spec   = $MuteHotkey
        Label  = "Mute/UnMute"
        Action = { (New-Object -ComObject WScript.Shell).SendKeys([char]173) }
    },
    @{
        Id     = 2
        Spec   = $VolumeUpHotkey
        Label  = "Volume Up"
        Action = { (New-Object -ComObject WScript.Shell).SendKeys([char]175); }
    },
    @{
        Id     = 3
        Spec   = $VolumeDownHotkey
        Label  = "Volume Down"
        Action = { (New-Object -ComObject WScript.Shell).SendKeys([char]174) }
    },
    @{
        Id     = 4
        Spec   = $QuitHotkey
        Label  = "Quit"
        Action = { $script:ExitRequested = $true }
    }
)

Write-Info "Mounting Bindings"
$bindingIds = @{}
foreach ($binding in $bindings) {
    if ($bindingIds.ContainsKey($binding.Id)) {
        throw "Duplicate binding ID: $($binding.Id)"
    }
    $bindingIds[$binding.Id] = $binding
}

Write-Info "Parsing Bindings"
$parsedBindings = @()
foreach ($binding in $bindings) {
    $parsed = Parse-Hotkey $binding.Spec
    $parsedBindings += [pscustomobject]@{
        Id        = $binding.Id
        Spec      = $binding.Spec
        Modifiers = $parsed.Modifiers
        KeyCode   = $parsed.KeyCode
        Action    = $binding.Action
    }
}

Write-Info "Creating thread mutex"
$mutexCreated = $false
$mutex = New-Object System.Threading.Mutex($false, $MutexName, [ref]$mutexCreated)

if (-not $mutexCreated) {
    Write-Fatal "Unable to create thread mutex"
    exit 0
}

$ExitRequested = $false

try {
    write-debug "starting procedure"
    $null = $mutex.WaitOne()

    write-debug "writing pid file"
    Write-PidFile

    write-debug "checking bindings"
    foreach ($binding in $parsedBindings) {
        $flags = $binding.Modifiers
        if ($HotkeyNoRepeat) {
            $flags = $flags -bor [Native]::MOD_NOREPEAT
        }

        $ok = [Native]::RegisterHotKey(
            [IntPtr]::Zero,
            $binding.Id,
            $flags,
            $binding.KeyCode
        )

        if (-not $ok) {
            $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Failed to register hotkey '$($binding.Spec)' (Win32 error $err)."
        }
    }

    write-debug "starting loop"
    while (-not $script:ExitRequested) {
        $msg = New-Object Native+MSG
        $result = [Native]::GetMessage([ref]$msg, [IntPtr]::Zero, 0, 0)

        if ($result -eq -1) {
            $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "GetMessage failed (Win32 error $err)."
        }

        if ($result -eq 0) {
            write-debug 'exiting loop. $result == 0'
            break
        }

        if ($msg.message -eq [Native]::WM_HOTKEY) {
            $id = [int]$msg.wParam.ToUInt64()
            if ($bindingIds.ContainsKey($id)) {
                $binding = $bindingIds[$id];
                write-debug "Called: $($binding.Label)"
                & $binding.Action
            }
        }

        [Native]::TranslateMessage([ref]$msg) | Out-Null
        [Native]::DispatchMessage([ref]$msg) | Out-Null
    }
    write-debug "Finished loop"
}
finally {
    write-debug "unregistering keys"
    foreach ($binding in $parsedBindings) {
        [Native]::UnregisterHotKey([IntPtr]::Zero, $binding.Id) | Out-Null
    }

    write-debug "removing pid file"
    Remove-PidFile

    write-debug "releasing mutex"
    if ($mutex) {
        try {
            $mutex.ReleaseMutex() | Out-Null
        }
        catch {
            Write-Error "Unable to release mutex: $($_.Exception.Message)"
        }
        $mutex.Dispose()
    }
}
