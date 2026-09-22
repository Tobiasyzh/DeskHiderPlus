#NoEnv
#SingleInstance, Off
#Persistent
SendMode, Input
SetWorkingDir, %A_ScriptDir%

; DeskHider Plus v1.1.0 (optional tray icon + English UI)
; Based on DeskHider by Ian Div (MIT License):
; https://github.com/iandiv/DeskHider
; Original desktop-icon hit-test logic credited by DeskHider to iPhilip.
;
; Added features:
; - Hide / restore Windows shortcut arrows from tray menu
; - Preserve the pre-existing Shell Icons\29 value and restore it safely
; - Optional Run at startup toggle
; - Optional tray icon with persistent preference
; - Launch the EXE again to restore a hidden tray icon
; - No polling for the arrow feature; idle work is the same desktop-click listener model

; -----------------------------------------------------------------------------
; Configuration / registry paths
; -----------------------------------------------------------------------------

global APP_NAME := "DeskHider Plus"
global SHELL_ICONS_KEY := "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons"
global APP_REG_KEY := "HKLM\SOFTWARE\DeskHiderPlus"
global USER_REG_KEY := "HKCU\SOFTWARE\DeskHiderPlus"
global RUN_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global BLANK_ICON_DIR := A_AppDataCommon "\DeskHiderPlus"
global BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v3.ico"
global LEGACY_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank.ico"
global OVERLAY_VALUE := BLANK_ICON_PATH
global LEGACY_OVERLAY_VALUE1 := LEGACY_BLANK_ICON_PATH ",0"
global LEGACY_OVERLAY_VALUE2 := LEGACY_BLANK_ICON_PATH
global DesktopIconsIsShow := 1
global TrayIconVisible := 1

; A classic 24x24 transparent ICO (BMP/DIB + AND mask), embedded as Base64.
; This avoids the black-square issue that PNG-compressed ICO overlays can cause on Windows 10.
global TRANSPARENT_ICO_B64 := "AAABAAEAGBgAAAEAIACICQAAFgAAACgAAAAYAAAAMAAAAAEAIAAAAAAAAAkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wA="

; -----------------------------------------------------------------------------
; Elevated helper mode. Normal daily use stays non-admin.
; -----------------------------------------------------------------------------

if (A_Args.Length() >= 1)
{
    action := A_Args[1]

    if (action = "/hidearrows")
    {
        if (!A_IsAdmin)
            ExitApp, 20
        result := HideShortcutArrowsAdmin()
        ExitApp, %result%
    }

    if (action = "/restorearrows")
    {
        if (!A_IsAdmin)
            ExitApp, 20
        result := RestoreShortcutArrowsAdmin()
        ExitApp, %result%
    }
}

; Keep only one normal resident instance, while still allowing the short-lived
; elevated helper process to run alongside it. If the tray icon is hidden,
; launching the EXE again restores it in the existing process.
global SHOW_TRAY_MESSAGE := DllCall("RegisterWindowMessage", "Str", "DeskHiderPlus_ShowTrayIcon", "UInt")
global MainMutexHandle := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Local\DeskHiderPlus_MainInstance", "Ptr")
if (A_LastError = 183) ; ERROR_ALREADY_EXISTS
{
    DllCall("User32.dll\\PostMessageW", "Ptr", 0xFFFF, "UInt", SHOW_TRAY_MESSAGE, "Ptr", 0, "Ptr", 0)
    ExitApp
}
OnMessage(SHOW_TRAY_MESSAGE, "ShowTrayFromMessage")

; One-time migration from v2. v2 used a PNG-compressed transparent ICO that some
; Windows 10 builds render as an opaque black square. Offer to repair it once.
if (IsLegacyOverlayActive())
{
    MsgBox, 36, DeskHider Plus, A legacy DeskHider Plus shortcut-arrow setting was detected.`n`nOlder transparent icons can appear as black squares on some Windows 10 systems. This version uses a classic BMP/DIB icon with an AND transparency mask and a new filename to avoid the old icon cache.`n`nRepair it now?
    IfMsgBox, Yes
    {
        code := RunElevatedHelper("/hidearrows")
        if (code = 0)
        {
            RestartExplorer()
            DesktopIconsIsShow := 1
        }
        else if (code != "ERROR")
            MsgBox, 16, DeskHider Plus, Automatic repair failed. Error code: %code%
    }
}

; -----------------------------------------------------------------------------
; Tray menu
; -----------------------------------------------------------------------------

Menu, Tray, NoStandard
Menu, Tray, Add, Hide shortcut arrows, TrayHideArrows
Menu, Tray, Add, Restore shortcut arrows, TrayRestoreArrows
Menu, Tray, Add
Menu, Tray, Add, Run at startup, ToggleStartup
Menu, Tray, Add, Show tray icon, ToggleTrayIcon
Menu, Tray, Add
Menu, Tray, Add, Exit, QuitScript
Menu, Tray, Tip, DeskHider Plus
ApplyTrayPreference()
RefreshTrayState()
Return

; -----------------------------------------------------------------------------
; Desktop double-click handling (keeps the original DeskHider approach)
; -----------------------------------------------------------------------------

#If IsDesktopUnderMouse()
~LButton::
    LButton_presses++

    if (LButton_presses = 2)
    {
        if (!IsObject(GetDesktopIconUnderMouse()) or DesktopIconsIsShow = 0)
            DesktopIconsIsShow := HideOrShowDesktopIcons()
    }

    SetTimer, KeyLButton, -300
Return
#If

KeyLButton:
    LButton_presses := 0
Return

; -----------------------------------------------------------------------------
; Tray actions
; -----------------------------------------------------------------------------

TrayHideArrows:
    if (IsArrowsHiddenByUs())
    {
        MsgBox, 64, DeskHider Plus, Shortcut arrows are already hidden.
        Return
    }

    MsgBox, 36, DeskHider Plus, DeskHider Plus will hide Windows shortcut arrows.`n`nAdministrator permission is required only for this operation. Windows Explorer will restart so the change takes effect immediately, and open File Explorer windows may close.`n`nContinue?
    IfMsgBox, No
        Return

    code := RunElevatedHelper("/hidearrows")
    if (code = "ERROR")
    {
        MsgBox, 48, DeskHider Plus, The operation was not completed. The administrator permission request may have been cancelled.
        Return
    }

    if (code != 0)
    {
        MsgBox, 16, DeskHider Plus, Failed to hide shortcut arrows. Error code: %code%
        Return
    }

    RestartExplorer()
    DesktopIconsIsShow := 1
    RefreshTrayState()
Return

TrayRestoreArrows:
    MsgBox, 36, DeskHider Plus, DeskHider Plus will restore the shortcut-arrow setting that existed before it made changes.`n`nAdministrator permission is required only for this operation. Windows Explorer will restart so the change takes effect immediately, and open File Explorer windows may close.`n`nContinue?
    IfMsgBox, No
        Return

    code := RunElevatedHelper("/restorearrows")
    if (code = "ERROR")
    {
        MsgBox, 48, DeskHider Plus, The operation was not completed. The administrator permission request may have been cancelled.
        Return
    }

    if (code = 31)
    {
        MsgBox, 48, DeskHider Plus, The shortcut-arrow setting was changed by another program or manually after DeskHider Plus modified it. To avoid overwriting that newer setting, restore was cancelled.
        Return
    }

    if (code != 0)
    {
        MsgBox, 16, DeskHider Plus, Failed to restore shortcut arrows. Error code: %code%
        Return
    }

    RestartExplorer()
    DesktopIconsIsShow := 1
    RefreshTrayState()
Return

ToggleStartup:
    if (IsStartupEnabled())
    {
        RegDelete, %RUN_KEY%, DeskHiderPlus
        if (ErrorLevel)
        {
            MsgBox, 16, DeskHider Plus, Failed to disable Run at startup.
            Return
        }
    }
    else
    {
        startupCmd := GetStartupCommand()
        RegWrite, REG_SZ, %RUN_KEY%, DeskHiderPlus, %startupCmd%
        if (ErrorLevel)
        {
            MsgBox, 16, DeskHider Plus, Failed to enable Run at startup.
            Return
        }
    }
    RefreshTrayState()
Return

ToggleTrayIcon:
    if (TrayIconVisible)
    {
        MsgBox, 36, DeskHider Plus, Hide the tray icon?`n`nDeskHider Plus will continue running in the background and desktop double-click will keep working.`n`nTo show the tray icon again, simply run DeskHiderPlus.exe a second time.
        IfMsgBox, No
            Return

        RegWrite, REG_DWORD, %USER_REG_KEY%, ShowTrayIcon, 0
        if (ErrorLevel)
        {
            MsgBox, 16, DeskHider Plus, Failed to save the tray icon preference.
            Return
        }

        TrayIconVisible := 0
        Menu, Tray, NoIcon
    }
    else
    {
        RegWrite, REG_DWORD, %USER_REG_KEY%, ShowTrayIcon, 1
        if (ErrorLevel)
        {
            MsgBox, 16, DeskHider Plus, Failed to save the tray icon preference.
            Return
        }

        TrayIconVisible := 1
        Menu, Tray, Icon
        RefreshTrayState()
    }
Return

QuitScript:
    ExitApp
Return

; -----------------------------------------------------------------------------
; Original DeskHider desktop functions
; -----------------------------------------------------------------------------

IsDesktopUnderMouse()
{
    MouseGetPos, , , OutputVarWin
    WinGetClass, OutputVarClass, % "ahk_id" OutputVarWin

    if (OutputVarClass = "WorkerW" or OutputVarClass = "Progman")
        return 1
    else
        return 0
}

HideOrShowDesktopIcons()
{
    ControlGet, OutputVarHwnd, Hwnd,, SysListView321, ahk_class WorkerW

    if (OutputVarHwnd = "")
        ControlGet, OutputVarHwnd, Hwnd,, SysListView321, ahk_class Progman

    if (DllCall("IsWindowVisible", "UInt", OutputVarHwnd))
    {
        WinHide, ahk_id %OutputVarHwnd%
        return 0
    }
    else
    {
        WinShow, ahk_id %OutputVarHwnd%
        return 1
    }
}

GetDesktopIconUnderMouse()
{
    static MEM_COMMIT := 0x1000, MEM_RELEASE := 0x8000, PAGE_ReadWRITE := 0x04
    , PROCESS_VM_OPERATION := 0x0008, PROCESS_VM_READ := 0x0010
    , LVM_GETITEMCOUNT := 0x1004, LVM_GETITEMRECT := 0x100E

    Icon := ""
    MouseGetPos, x, y, hwnd

    if not (hwnd = WinExist("ahk_class Progman") || hwnd = WinExist("ahk_class WorkerW"))
        return

    ControlGet, hwnd, HWND, , SysListView321
    if not WinExist("ahk_id" hwnd)
        return

    WinGet, pid, PID
    if (hProcess := DllCall("OpenProcess", "UInt", PROCESS_VM_OPERATION|PROCESS_VM_READ, "Int", false, "UInt", pid))
    {
        VarSetCapacity(iCoord, 16)
        SendMessage, %LVM_GETITEMCOUNT%, 0, 0

        Loop, %ErrorLevel%
        {
            pItemCoord := DllCall("VirtualAllocEx", "Ptr", hProcess, "Ptr", 0, "UInt", 16, "UInt", MEM_COMMIT, "UInt", PAGE_ReadWRITE)
            SendMessage, %LVM_GETITEMRECT%, % A_Index-1, %pItemCoord%
            DllCall("ReadProcessMemory", "Ptr", hProcess, "Ptr", pItemCoord, "Ptr", &iCoord, "UInt", 16, "UInt", 0)
            DllCall("VirtualFreeEx", "Ptr", hProcess, "Ptr", pItemCoord, "UInt", 0, "UInt", MEM_RELEASE)

            left := NumGet(iCoord, 0, "Int")
            top := NumGet(iCoord, 4, "Int")
            Right := NumGet(iCoord, 8, "Int")
            bottom := NumGet(iCoord, 12, "Int")

            if (left < x and x < Right and top < y and y < bottom)
            {
                ControlGet, list, List
                RegExMatch(StrSplit(list, "`n")[A_Index], "O)(.*)\t(.*)\t(.*)\t(.*)", Match)
                Icon := {left:left, top:top, Right:Right, bottom:bottom
                    , name:Match[1], size:Match[2], type:Match[3]
                    , date:RegExReplace(Match[4], A_IsUnicode ? "[\x{200E}-\x{200F}]" : "\?")}
                break
            }
        }

        DllCall("CloseHandle", "Ptr", hProcess)
    }

    return Icon
}

; -----------------------------------------------------------------------------
; Shortcut-arrow functions
; -----------------------------------------------------------------------------

RunElevatedHelper(action)
{
    if (A_IsCompiled)
        RunWait, *RunAs "%A_ScriptFullPath%" %action%,, UseErrorLevel
    else
        RunWait, *RunAs "%A_AhkPath%" "%A_ScriptFullPath%" %action%,, UseErrorLevel

    return ErrorLevel
}

HideShortcutArrowsAdmin()
{
    global SHELL_ICONS_KEY, APP_REG_KEY, BLANK_ICON_DIR, BLANK_ICON_PATH, LEGACY_BLANK_ICON_PATH, OVERLAY_VALUE, LEGACY_OVERLAY_VALUE1, LEGACY_OVERLAY_VALUE2, TRANSPARENT_ICO_B64

    UseNativeRegistryView()

    ; Save the pre-existing value only once, so Restore can put it back.
    RegRead, backupState, %APP_REG_KEY%, BackupState
    if (ErrorLevel)
    {
        RegRead, oldValue, %SHELL_ICONS_KEY%, 29
        if (ErrorLevel || oldValue = LEGACY_OVERLAY_VALUE1 || oldValue = LEGACY_OVERLAY_VALUE2)
        {
            ; If v2 is present but its backup metadata is gone, do not preserve the broken overlay as the user's original setting.
            RegWrite, REG_SZ, %APP_REG_KEY%, BackupState, MISSING
            if (ErrorLevel)
            {
                RestoreDefaultRegistryView()
                return 21
            }
        }
        else
        {
            RegWrite, REG_SZ, %APP_REG_KEY%, BackupState, VALUE
            if (ErrorLevel)
            {
                RestoreDefaultRegistryView()
                return 22
            }
            RegWrite, REG_SZ, %APP_REG_KEY%, BackupValue, %oldValue%
            if (ErrorLevel)
            {
                RestoreDefaultRegistryView()
                return 23
            }
        }
    }

    ; Recreate the icon when applying the setting so legacy PNG-based blank.ico files are repaired.
    FileCreateDir, %BLANK_ICON_DIR%
    if (!FileExist(BLANK_ICON_DIR))
    {
        RestoreDefaultRegistryView()
        return 24
    }

    if (!WriteBase64File(TRANSPARENT_ICO_B64, BLANK_ICON_PATH))
    {
        RestoreDefaultRegistryView()
        return 25
    }

    RegWrite, REG_SZ, %SHELL_ICONS_KEY%, 29, %OVERLAY_VALUE%
    if (ErrorLevel)
    {
        RestoreDefaultRegistryView()
        return 26
    }

    ; This version uses a dedicated filename so Explorer cannot reuse the cached malformed v2 overlay.
    FileDelete, %LEGACY_BLANK_ICON_PATH%

    RestoreDefaultRegistryView()
    return 0
}

RestoreShortcutArrowsAdmin()
{
    global SHELL_ICONS_KEY, APP_REG_KEY, BLANK_ICON_DIR, BLANK_ICON_PATH, LEGACY_BLANK_ICON_PATH, OVERLAY_VALUE, LEGACY_OVERLAY_VALUE1, LEGACY_OVERLAY_VALUE2

    UseNativeRegistryView()

    RegRead, currentValue, %SHELL_ICONS_KEY%, 29
    currentMissing := ErrorLevel

    ; If another program changed Shell Icons\29 after we did, don't overwrite it.
    if (!currentMissing && currentValue != OVERLAY_VALUE && currentValue != LEGACY_OVERLAY_VALUE1 && currentValue != LEGACY_OVERLAY_VALUE2)
    {
        RestoreDefaultRegistryView()
        return 31
    }

    RegRead, backupState, %APP_REG_KEY%, BackupState
    if (ErrorLevel)
    {
        ; No backup means we can only safely remove our own value.
        if (!currentMissing && (currentValue = OVERLAY_VALUE || currentValue = LEGACY_OVERLAY_VALUE1 || currentValue = LEGACY_OVERLAY_VALUE2))
            RegDelete, %SHELL_ICONS_KEY%, 29
    }
    else if (backupState = "VALUE")
    {
        RegRead, backupValue, %APP_REG_KEY%, BackupValue
        if (ErrorLevel)
        {
            RestoreDefaultRegistryView()
            return 32
        }
        RegWrite, REG_SZ, %SHELL_ICONS_KEY%, 29, %backupValue%
        if (ErrorLevel)
        {
            RestoreDefaultRegistryView()
            return 33
        }
    }
    else
    {
        RegDelete, %SHELL_ICONS_KEY%, 29
        ; RegDelete reports an error when already absent; that is harmless here.
    }

    RegDelete, %APP_REG_KEY%
    FileDelete, %BLANK_ICON_PATH%
    FileDelete, %LEGACY_BLANK_ICON_PATH%
    FileRemoveDir, %BLANK_ICON_DIR%

    RestoreDefaultRegistryView()
    return 0
}

IsLegacyOverlayActive()
{
    global SHELL_ICONS_KEY, LEGACY_OVERLAY_VALUE1, LEGACY_OVERLAY_VALUE2

    UseNativeRegistryView()
    RegRead, currentValue, %SHELL_ICONS_KEY%, 29
    err := ErrorLevel
    RestoreDefaultRegistryView()

    return (!err && (currentValue = LEGACY_OVERLAY_VALUE1 || currentValue = LEGACY_OVERLAY_VALUE2))
}

IsArrowsHiddenByUs()
{
    global SHELL_ICONS_KEY, OVERLAY_VALUE

    UseNativeRegistryView()
    RegRead, currentValue, %SHELL_ICONS_KEY%, 29
    err := ErrorLevel
    RestoreDefaultRegistryView()

    return (!err && currentValue = OVERLAY_VALUE)
}

WriteBase64File(base64Text, filePath)
{
    ; CRYPT_STRING_BASE64 = 0x1
    flags := 0x1
    binarySize := 0

    ok := DllCall("Crypt32.dll\CryptStringToBinaryW"
        , "WStr", base64Text
        , "UInt", 0
        , "UInt", flags
        , "Ptr", 0
        , "UIntP", binarySize
        , "Ptr", 0
        , "Ptr", 0)

    if (!ok || binarySize <= 0)
        return false

    VarSetCapacity(binaryData, binarySize, 0)

    ok := DllCall("Crypt32.dll\CryptStringToBinaryW"
        , "WStr", base64Text
        , "UInt", 0
        , "UInt", flags
        , "Ptr", &binaryData
        , "UIntP", binarySize
        , "Ptr", 0
        , "Ptr", 0)

    if (!ok)
        return false

    file := FileOpen(filePath, "w")
    if (!IsObject(file))
        return false

    written := file.RawWrite(binaryData, binarySize)
    file.Close()

    return (written = binarySize)
}

UseNativeRegistryView()
{
    if (A_Is64bitOS)
        SetRegView, 64
}

RestoreDefaultRegistryView()
{
    if (A_Is64bitOS)
        SetRegView, Default
}

RestartExplorer()
{
    ; Close Explorer, then wait for Windows' normal AutoRestartShell behavior.
    ; Only start explorer.exe ourselves if the shell does not return.
    RunWait, %ComSpec% /c taskkill /f /im explorer.exe,, Hide
    WinWait, ahk_class Shell_TrayWnd,, 5
    if (ErrorLevel)
        Run, explorer.exe
}

; -----------------------------------------------------------------------------
; Tray icon preference / recovery
; -----------------------------------------------------------------------------

ApplyTrayPreference()
{
    global USER_REG_KEY, TrayIconVisible

    RegRead, showTray, %USER_REG_KEY%, ShowTrayIcon
    if (ErrorLevel)
        showTray := 1

    TrayIconVisible := showTray ? 1 : 0

    if (TrayIconVisible)
        Menu, Tray, Icon
    else
        Menu, Tray, NoIcon
}

RefreshTrayState()
{
    global TrayIconVisible

    Menu, Tray, Uncheck, Hide shortcut arrows
    Menu, Tray, Uncheck, Run at startup
    Menu, Tray, Uncheck, Show tray icon

    if (IsArrowsHiddenByUs())
        Menu, Tray, Check, Hide shortcut arrows

    if (IsStartupEnabled())
        Menu, Tray, Check, Run at startup

    if (TrayIconVisible)
        Menu, Tray, Check, Show tray icon
}

ShowTrayFromMessage(wParam, lParam, msg, hwnd)
{
    global USER_REG_KEY, TrayIconVisible

    RegWrite, REG_DWORD, %USER_REG_KEY%, ShowTrayIcon, 1
    TrayIconVisible := 1
    Menu, Tray, Icon
    RefreshTrayState()
    return 0
}

; -----------------------------------------------------------------------------
; Startup helper
; -----------------------------------------------------------------------------

GetStartupCommand()
{
    if (A_IsCompiled)
        return Chr(34) . A_ScriptFullPath . Chr(34)
    else
        return Chr(34) . A_AhkPath . Chr(34) . " " . Chr(34) . A_ScriptFullPath . Chr(34)
}

IsStartupEnabled()
{
    global RUN_KEY

    RegRead, currentValue, %RUN_KEY%, DeskHiderPlus
    if (ErrorLevel)
        return false

    return (currentValue = GetStartupCommand())
}
