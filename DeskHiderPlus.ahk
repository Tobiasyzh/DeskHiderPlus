#NoEnv
#SingleInstance, Off
#Persistent
SendMode, Input
SetWorkingDir, %A_ScriptDir%

; DeskHider Plus v1.1.1 beta 1 (mask-only shortcut overlays + v3 migration)
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
global BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v4_mask.ico"
global V3_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v3.ico"
global LEGACY_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank.ico"
global OWNED_ICON_PATHS := [BLANK_ICON_PATH, V3_BLANK_ICON_PATH, LEGACY_BLANK_ICON_PATH]
global OVERLAY_VALUE := BLANK_ICON_PATH ",0"
global DesktopIconsIsShow := 1
global TrayIconVisible := 1

; -----------------------------------------------------------------------------
; Elevated helper mode. Normal daily use stays non-admin.
; -----------------------------------------------------------------------------

if (A_Args.Length() >= 1)
{
    action := A_Args[1]

    ; Parse/build smoke check: exits before touching settings or the resident app.
    if (action = "/validate")
        ExitApp, 0

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
; elevated helper process to run alongside it.
;
; Hidden-tray recovery uses a direct message to the existing script's uniquely
; named hidden main window. This is more reliable on Windows 10 than broadcasting
; a registered message to every top-level window.
global SHOW_TRAY_MESSAGE := 0x8001 ; WM_APP + 1
global IPC_WINDOW_TITLE := "DeskHiderPlus_IPC_Window"
global MainMutexHandle := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Local\DeskHiderPlus_MainInstance", "Ptr")
if (A_LastError = 183) ; ERROR_ALREADY_EXISTS
{
    DetectHiddenWindows, On
    targetHwnd := 0
    Loop, 20
    {
        WinGet, targetHwnd, ID, DeskHiderPlus_IPC_Window ahk_class AutoHotkey
        if (targetHwnd)
            break
        Sleep, 50
    }

    if (targetHwnd)
        DllCall("User32.dll\PostMessageW", "Ptr", targetHwnd, "UInt", SHOW_TRAY_MESSAGE, "Ptr", 0, "Ptr", 0)
    ExitApp
}

; Give the resident instance a stable hidden window name for future launches.
DetectHiddenWindows, On
WinSetTitle, ahk_id %A_ScriptHwnd%,, DeskHiderPlus_IPC_Window
OnMessage(SHOW_TRAY_MESSAGE, "ShowTrayFromMessage")

; One-time migration from both PNG-based blank.ico and 32bpp blank_v3.ico.
; The replacement is persisted before Explorer restarts, so it is ready at logon.
if (IsLegacyOverlayActive())
{
    MsgBox, 36, DeskHider Plus, An older or missing DeskHider Plus shortcut overlay was detected.`n`nOlder transparent icons can cover or cut out the lower-left corner of shortcuts after sign-in. This version uses a multi-size monochrome icon with an AND transparency mask and no alpha channel.`n`nRepair it now? Administrator permission is required and Windows Explorer will restart. Open File Explorer windows may close.
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
Menu, Tray, Add, Hide / repair shortcut arrows, TrayHideArrows
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
    MsgBox, 36, DeskHider Plus, DeskHider Plus will hide or repair Windows shortcut arrows using a mask-only transparent icon.`n`nAdministrator permission is required only for this operation. Windows Explorer will restart so the change takes effect immediately, and open File Explorer windows may close.`n`nContinue?
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
        MsgBox, 36, DeskHider Plus, Hide the tray icon?`n`nDeskHider Plus will continue running in the background and desktop double-click will keep working.`n`nTo show the tray icon again, run the same DeskHiderPlus.exe file again. The existing background instance will restore its tray icon.
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

RestartExplorer()
{
    ; Close Explorer, then wait for Windows' normal AutoRestartShell behavior.
    ; Only start explorer.exe ourselves if the shell does not return.
    RunWait, %ComSpec% /c taskkill /f /im explorer.exe,, Hide
    WinWait, ahk_class Shell_TrayWnd,, 5
    if (ErrorLevel)
    {
        Run, explorer.exe
        WinWait, ahk_class Shell_TrayWnd,, 5
    }

    ; Invalidate previously composed shortcut icons once, after the new shell
    ; has loaded the replacement overlay. No cache-file deletion or logon timer.
    ; SHCNE_ASSOCCHANGED | SHCNF_IDLIST | SHCNF_FLUSH
    DllCall("Shell32.dll\SHChangeNotify", "Int", 0x08000000, "UInt", 0x1000
        , "Ptr", 0, "Ptr", 0)
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

    Menu, Tray, Uncheck, Hide / repair shortcut arrows
    Menu, Tray, Uncheck, Run at startup
    Menu, Tray, Uncheck, Show tray icon

    if (IsArrowsHiddenByUs())
        Menu, Tray, Check, Hide / repair shortcut arrows

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

; Shared overlay implementation is also exercised by the isolated regression tests.
#Include %A_ScriptDir%\lib\ShortcutArrows.ahk
