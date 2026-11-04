#NoEnv
#NoTrayIcon
#SingleInstance, Off
#Persistent
SendMode, Input
SetWorkingDir, %A_ScriptDir%

; DeskHider Plus v2.0 (based on the user-verified test2 implementation)
;@Ahk2Exe-SetVersion 2.0.0.0
;@Ahk2Exe-SetDescription DeskHider Plus - desktop icons and shortcut arrows
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
global BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v6_argb.ico"
global V5_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v5_mask.ico"
global V4_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v4_mask.ico"
global V3_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v3.ico"
global LEGACY_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank.ico"
global OWNED_ICON_PATHS := [BLANK_ICON_PATH, V5_BLANK_ICON_PATH, V4_BLANK_ICON_PATH, V3_BLANK_ICON_PATH, LEGACY_BLANK_ICON_PATH]
global OVERLAY_VALUE := BLANK_ICON_PATH ",0"
global RECOVERY_ROOT := A_ScriptDir "\项目辅助文件\图标修复备份"
global LAST_RECOVERY_DIR := ""
global OverlayHealthVerified := false
global APP_PROTOCOL_VERSION := 20000
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

    if (action = "/verifyoverlay")
    {
        if (A_Args.Length() >= 2 && InStr(FileExist(A_Args[2]), "D"))
            LAST_RECOVERY_DIR := A_Args[2]
        result := VerifyRestoredShortcutOverlay()
        ExitApp, %result%
    }

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

; Keep cache work in the interactive user's ordinary process, including when
; UAC uses a different administrator account for the short-lived registry helper.
if (A_IsAdmin)
{
    MsgBox, 48, DeskHider Plus, Please run DeskHider Plus normally, without Run as administrator.`n`nAdministrator permission will be requested only when changing the shortcut-arrow registry setting.
    ExitApp
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

    if (!targetHwnd)
        ExitApp
    version := 0
    DllCall("User32\SendMessageTimeoutW", "Ptr", targetHwnd, "UInt", 0x8003
        , "Ptr", 0, "Ptr", 0, "UInt", 2, "UInt", 1000, "PtrP", version, "Ptr")
    if (version = APP_PROTOCOL_VERSION)
    {
        DllCall("User32\PostMessageW", "Ptr", targetHwnd, "UInt", SHOW_TRAY_MESSAGE, "Ptr", 0, "Ptr", 0)
        ExitApp
    }
    MsgBox, 36, DeskHider Plus, An older DeskHider Plus instance is running.`n`nClose that instance and open this version? Desktop icons will not be changed until you confirm the repair prompt.
    IfMsgBox, No
        ExitApp
    WinGet, oldPid, PID, ahk_id %targetHwnd%
    if (oldPid)
    {
        Process, Close, %oldPid%
        Process, WaitClose, %oldPid%, 5
        if (ErrorLevel)
        {
            MsgBox, 16, DeskHider Plus, Could not close the older instance. Exit it from its tray menu and run this version again.
            ExitApp
        }
    }
}

; Give the resident instance a stable hidden window name for future launches.
DetectHiddenWindows, On
WinSetTitle, ahk_id %A_ScriptHwnd%,, DeskHiderPlus_IPC_Window
OnMessage(SHOW_TRAY_MESSAGE, "ShowTrayFromMessage")
OnMessage(0x8003, "GetAppProtocolVersion")

; -----------------------------------------------------------------------------
; Tray menu
; -----------------------------------------------------------------------------

Menu, Tray, NoStandard
Menu, Tray, Add, Hide / repair shortcut arrows, TrayHideArrows
Menu, Tray, Add, Restore shortcut arrows, TrayRestoreArrows
Menu, Tray, Add, Rebuild icon cache, TrayRebuildIcons
Menu, Tray, Add
Menu, Tray, Add, Run at startup, ToggleStartup
Menu, Tray, Add, Show tray icon, ToggleTrayIcon
Menu, Tray, Add
Menu, Tray, Add, Exit, QuitScript
Menu, Tray, Tip, DeskHider Plus v2.0
ApplyTrayPreference()

; Check once per launch in a separate process. No timers or background polling.
configured := IsArrowsConfiguredByUs()
if (configured)
    OverlayHealthVerified := (RunOverlayVerification() = 0)
RefreshTrayState()
if (IsLegacyOverlayActive() || (configured && !OverlayHealthVerified))
{
    MsgBox, 36, DeskHider Plus, An older or unhealthy shortcut overlay was detected.`n`nRepair will update the overlay, archive and rebuild this user's icon cache, and check Windows' restored system image list. If hiding fails, the program will attempt to restore the original arrows.`n`nExplorer will restart and open File Explorer windows may close. Repair now?
    IfMsgBox, Yes
        PerformOverlayAction("hide", true)
}
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
    PerformOverlayAction("hide")
Return

TrayRestoreArrows:
    PerformOverlayAction("restore")
Return

TrayRebuildIcons:
    MsgBox, 36, DeskHider Plus, Archive and rebuild this user's icon cache?`n`nExplorer will restart and open File Explorer windows may close. The shortcut-arrow registry setting will be preserved.
    IfMsgBox, No
        Return
    if (NewIconRecoveryFolder() = "")
    {
        MsgBox, 16, DeskHider Plus, Cannot create the recovery folder beside this EXE. Move the program to a writable permanent folder and try again.
        Return
    }
    SnapshotShortcutSettings()
    code := RebuildShortcutIconCache()
    OverlayHealthVerified := (code = 0 && IsArrowsConfiguredByUs() && RunOverlayVerification() = 0)
    DesktopIconsIsShow := 1
    RefreshTrayState()
    if (IsArrowsConfiguredByUs() && !OverlayHealthVerified)
        RollBackFailedOverlay()
    else if (code != 0)
        MsgBox, 48, DeskHider Plus, The cache rebuild was incomplete (code %code%). Save your work and sign out and back in if icons remain incorrect.`n`nDetails: %LAST_RECOVERY_DIR%
    else
        MsgBox, 64, DeskHider Plus, The icon cache was rebuilt.`n`nRecovery files: %LAST_RECOVERY_DIR%
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

RunOverlayVerification()
{
    global LAST_RECOVERY_DIR
    LogIconRecovery("Starting verification helper")
    if (A_IsCompiled)
        command := Chr(34) A_ScriptFullPath Chr(34) " /verifyoverlay " Chr(34) LAST_RECOVERY_DIR Chr(34)
    else
        command := Chr(34) A_AhkPath Chr(34) " " Chr(34) A_ScriptFullPath Chr(34) " /verifyoverlay " Chr(34) LAST_RECOVERY_DIR Chr(34)
    result := RunBoundedOverlayHelper(command)
    LogIconRecovery("Verification helper completed with " result)
    return result
}

PerformOverlayAction(action, confirmed := false)
{
    global OverlayHealthVerified, DesktopIconsIsShow, LAST_RECOVERY_DIR
    if (!confirmed)
    {
        description := action = "hide" ? "Hide or repair shortcut arrows" : "Restore the original shortcut arrows"
        MsgBox, 36, DeskHider Plus, %description%?`n`nAdministrator permission is needed for the registry change. The program will archive and rebuild this user's icon cache. Explorer will restart and open File Explorer windows may close.
        IfMsgBox, No
            return false
    }
    if (NewIconRecoveryFolder() = "")
    {
        MsgBox, 16, DeskHider Plus, Cannot create the recovery folder beside this EXE. Move the program to a writable permanent folder and try again.
        return false
    }
    SnapshotShortcutSettings()
    code := RunElevatedHelper(action = "hide" ? "/hidearrows" : "/restorearrows")
    LogIconRecovery("Registry action " action " returned " code)
    if (code != 0)
    {
        message := code = 31 ? "Another program changed the overlay setting. It has been preserved." : "The registry operation was not completed. Administrator permission may have been cancelled."
        MsgBox, 48, DeskHider Plus, %message%`n`nCode: %code%`nDetails: %LAST_RECOVERY_DIR%
        return false
    }
    OverlayHealthVerified := false
    code := RebuildShortcutIconCache()
    DesktopIconsIsShow := 1
    if (action = "hide")
    {
        check := RunOverlayVerification()
        LogIconRecovery("Restored Shell overlay verification returned " check)
        if (code != 0 || check != 0)
            return RollBackFailedOverlay()
        OverlayHealthVerified := true
    }
    RefreshTrayState()
    if (code != 0)
    {
        MsgBox, 48, DeskHider Plus, The original arrow setting was restored, but the icon cache rebuild was incomplete (code %code%). Save your work and sign out and back in if icons remain incorrect.`n`nDetails: %LAST_RECOVERY_DIR%
        return false
    }
    MsgBox, 64, DeskHider Plus, The operation completed. Please check your desktop icons and check again after restarting Windows.`n`nRecovery files: %LAST_RECOVERY_DIR%
    return true
}

RollBackFailedOverlay()
{
    global OverlayHealthVerified, LAST_RECOVERY_DIR
    OverlayHealthVerified := false
    code := RunElevatedHelper("/restorearrows")
    LogIconRecovery("Safety restore returned " code)
    cacheCode := code = 0 ? RebuildShortcutIconCache() : -1
    RefreshTrayState()
    if (code = 0 && cacheCode = 0)
        MsgBox, 48, DeskHider Plus, Windows did not load the hidden-arrow overlay correctly. The original arrow setting has been restored and the icon cache rebuilt.`n`nHiding has been left off. Please report this result before using Hide again.`n`nDetails: %LAST_RECOVERY_DIR%
    else
        MsgBox, 16, DeskHider Plus, The overlay check failed and recovery is incomplete (registry %code%; cache %cacheCode%). Use Restore shortcut arrows and save your work before signing out and back in.`n`nDetails: %LAST_RECOVERY_DIR%
    return false
}

GetAppProtocolVersion(wParam, lParam, msg, hwnd)
{
    global APP_PROTOCOL_VERSION
    return APP_PROTOCOL_VERSION
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
    global TrayIconVisible, OverlayHealthVerified

    Menu, Tray, Uncheck, Hide / repair shortcut arrows
    Menu, Tray, Uncheck, Run at startup
    Menu, Tray, Uncheck, Show tray icon

    if (OverlayHealthVerified && IsArrowsConfiguredByUs())
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
#Include %A_ScriptDir%\lib\ShellIconCache.ahk
