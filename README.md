# VolumeHotkeys.ps1

A lightweight PowerShell-based global hotkey daemon for Windows that controls the system master volume.

This script:

- registers global keyboard shortcuts;
- adjusts Windows master volume;
- runs silently in the background;
- auto-starts at user logon using Windows Task Scheduler;
- prevents duplicate instances;
- safely cleans up registered hotkeys on exit;
- uses only built-in Windows APIs (no external dependencies).

---

# Features

## Global Hotkeys

The script can:

- mute/unmute system volume;
- increase volume;
- decrease volume;
- terminate itself.

Example default hotkeys:

| Action        | Hotkey           |
|---------------|------------------|
| Mute / Unmute | Win + Alt + M    |
| Volume Up     | Win + Alt + Up   |
| Volume Down   | Win + Alt + Down |
| Quit Script   | Win + Alt + Q    |

---

# Requirements

- Windows 10 or newer;
- PowerShell 5.1+;
- User account with permission to create scheduled tasks.

No external libraries or executables are required.

---

# Installation

Open PowerShell in the directory containing the script.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\VolumeHotkeys.ps1 -Install
```

The installer will:

1. create a Windows Scheduled Task;
2. configure it to start automatically at user logon;
3. launch the script immediately in hidden mode.

---

# Uninstallation

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\VolumeHotkeys.ps1 -Uninstall
```

The uninstaller will:

1. stop the running instance;
2. unregister the scheduled task;
3. remove internal state files.

---

# Running Manually

To run the script manually for testing/debugging:

```powershell
powershell -ExecutionPolicy Bypass -File .\VolumeHotkeys.ps1
```

This launches the hotkey listener in the current terminal session.

---

# Hotkey Configuration

The configurable section is located near the top of the script.

Example:

```powershell
# ================== Hotkey Configuration ==================
$MuteHotkey       = 'Ctrl+Alt+M'
$VolumeUpHotkey   = 'Ctrl+Alt+Up'
$VolumeDownHotkey = 'Ctrl+Alt+Down'
$QuitHotkey       = 'Ctrl+Alt+Q'
$HotkeyNoRepeat   = $true
# ==========================================================
```

---

# Supported Modifier Keys

Supported modifiers:

* `Ctrl`
* `Alt`
* `Shift`
* `Win`

Examples:

```powershell
'Ctrl+Shift+M'
'Win+Alt+Up'
'Ctrl+Alt+F12'
```

---

# Supported Keys

Supported special keys include:

* Arrow keys (`Up`, `Down`, `Left`, `Right`)
* Function keys (`F1` >> `F24`)
* `Enter`
* `Escape`
* `Tab`
* `Delete`
* `Insert`
* `Home`
* `End`
* `PgUp`
* `PgDn`
* Single alphanumeric characters

Examples:

```powershell
'Ctrl+Alt+Up'
'Shift+F9'
'Win+M'
```

---

# Internal Architecture

The script is divided into several subsystems.

---

## 1. Scheduled Task Installer

The installer uses:

* `Register-ScheduledTask`
* `New-ScheduledTaskAction`
* `New-ScheduledTaskTrigger`
* `New-ScheduledTaskPrincipal`

The task:

* starts at user logon;
* runs hidden;
* runs in the interactive desktop session.

This is required because global hotkeys only work inside an interactive user session.

---

## 2. Single-Instance Protection

The script prevents duplicate instances using:

* a named Windows mutex;
* a PID state file.

Mutex name:

```text
Local\VolumeHotkeys_Instance
```

If another instance already exists, the new instance exits immediately.

---

## 3. Global Hotkey Registration

Global hotkeys are registered using the Win32 API:

```c
RegisterHotKey()
```

Hotkeys are registered to the current thread message queue.

The script listens for:

```text
WM_HOTKEY
```

messages in a native Windows message loop.

---

## 4. Volume Control

Volume actions are performed using:

```c
SendInput()
```

The script simulates multimedia key presses:

| Action      | Virtual Key      |
| ----------- | ---------------- |
| Volume Mute | `VK_VOLUME_MUTE` |
| Volume Down | `VK_VOLUME_DOWN` |
| Volume Up   | `VK_VOLUME_UP`   |

This is the Microsoft-recommended modern replacement for the deprecated:

```c
keybd_event()
```

API.

---

## 5. Message Loop

The script runs a native Win32 message loop:

```c
GetMessage()
TranslateMessage()
DispatchMessage()
```

This loop waits for incoming global hotkey events.

---

# Safety Features

## Strict PowerShell Mode

The script enables:

```powershell
Set-StrictMode -Version Latest
```

This helps catch:

* undefined variables;
* invalid references;
* malformed expressions.

---

## Safe Cleanup

Hotkeys are automatically unregistered in a `finally` block.

This ensures cleanup occurs even if:

* the script crashes;
* PowerShell exits unexpectedly;
* a registration failure occurs.

---

## Safer Uninstall Logic

The uninstaller does NOT kill every PowerShell process.

Instead, it:

1. reads the stored PID file;
2. terminates only the matching process.

---

## MOD_NOREPEAT Support

Optional support for:

```c
MOD_NOREPEAT
```

prevents key-repeat spam when holding a hotkey down.

Controlled via:

```powershell
$HotkeyNoRepeat = $true
```

---

# State Files

Runtime state is stored in:

```text
%LOCALAPPDATA%\VolumeHotkeys\
```

Files include:

| File                | Purpose                       |
| ------------------- | ----------------------------- |
| `VolumeHotkeys.pid` | Stores the running process ID |

---

# Troubleshooting

## Hotkey Does Not Work

Possible causes:

* another application already registered the same hotkey;
* the script is not running;
* the scheduled task failed to start.

Try:

```powershell
Get-ScheduledTask -TaskName VolumeHotkeys
```

---

## Registration Failure

Example error:

```text
Failed to register hotkey
```

This usually means another application already owns the same key combination.

Choose different hotkeys.

---

## Script Does Not Start Automatically

Verify the task exists:

```powershell
Get-ScheduledTask -TaskName VolumeHotkeys
```

You can also inspect Task Scheduler manually:

```text
Task Scheduler
>> Task Scheduler Library
>> VolumeHotkeys
```

---

# Recommended Installation Location

Recommended path:

```text
C:\Users\<USERNAME>\Scripts\VolumeHotkeys.ps1
```

Avoid:

* temporary folders;
* Downloads;
* removable drives.

---

# Security Notes

This script:

* does NOT require administrator privileges;
* does NOT modify registry autoruns;
* does NOT install services;
* does NOT communicate over the network.

It operates entirely inside the current user session.

---

# Example Workflow

## Install

```powershell
powershell -ExecutionPolicy Bypass -File .\VolumeHotkeys.ps1 -Install
```

## Use Hotkeys

Press:

```text
Ctrl + Alt + M
```

to mute/unmute system volume.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\VolumeHotkeys.ps1 -Uninstall
```

---

# Technical Notes

This script uses native Win32 interop through:

```powershell
Add-Type
```

with embedded C# definitions for:

* `RegisterHotKey`
* `SendInput`
* `GetMessage`
* `DispatchMessage`
* `TranslateMessage`

No compiled binaries are required.

---

# License

You may freely modify and adapt this script for personal use.

