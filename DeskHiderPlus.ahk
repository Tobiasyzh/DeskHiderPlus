#NoEnv
#SingleInstance, Off
#Persistent
SendMode, Input
SetWorkingDir, %A_ScriptDir%

; DeskHider Plus v3 (Windows 10 transparency fix)
; Based on DeskHider by Ian Div (MIT License):
; https://github.com/iandiv/DeskHider
; Original desktop-icon hit-test logic credited by DeskHider to iPhilip.
;
; Added features:
; - Hide / restore Windows shortcut arrows from tray menu
; - Preserve the pre-existing Shell Icons\29 value and restore it safely
; - Optional Run at startup toggle
; - No polling for the arrow feature; idle work is the same desktop-click listener model

; -----------------------------------------------------------------------------
; Configuration / registry paths
; -----------------------------------------------------------------------------

global APP_NAME := "DeskHider Plus"
global SHELL_ICONS_KEY := "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons"
global APP_REG_KEY := "HKLM\SOFTWARE\DeskHiderPlus"
global RUN_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global BLANK_ICON_DIR := A_AppDataCommon "\DeskHiderPlus"
global BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v3.ico"
global LEGACY_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank.ico"
global OVERLAY_VALUE := BLANK_ICON_PATH
global LEGACY_OVERLAY_VALUE1 := LEGACY_BLANK_ICON_PATH ",0"
global LEGACY_OVERLAY_VALUE2 := LEGACY_BLANK_ICON_PATH
global DesktopIconsIsShow := 1

; A classic 24x24 transparent ICO (BMP/DIB + AND mask), embedded as Base64.
; This avoids the black-square issue that PNG-compressed ICO overlays can cause on Windows 10.
global TRANSPARENT_ICO_B64 := "AAABAAEAGBgAAAEAIACICQAAFgAAACgAAAAYAAAAMAAAAAEAIAAAAAAAAAkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wA="

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
; elevated helper process to run alongside it.
global MainMutexHandle := DllCall("CreateMutex", "Ptr", 0, "Int", 0, "Str", "Local\DeskHiderPlus_MainInstance", "Ptr")
if (A_LastError = 183) ; ERROR_ALREADY_EXISTS
    ExitApp

; One-time migration from v2. v2 used a PNG-compressed transparent ICO that some
; Windows 10 builds render as an opaque black square. Offer to repair it once.
if (IsLegacyOverlayActive())
{
    MsgBox, 36, DeskHider Plus v3, 检测到 DeskHider Plus v2 的旧版快捷方式箭头设置。`n`n该旧版透明图标在部分 Windows 10 上会显示成你截图里的黑色方块。v3 已改为传统 BMP/DIB + AND Mask 透明 ICO，并使用新的文件名避免旧图标缓存。`n`n是否现在自动修复？
    IfMsgBox, Yes
    {
        code := RunElevatedHelper("/hidearrows")
        if (code = 0)
        {
            RestartExplorer()
            DesktopIconsIsShow := 1
        }
        else if (code != "ERROR")
            MsgBox, 16, DeskHider Plus v3, 自动修复失败。错误代码：%code%
    }
}

; -----------------------------------------------------------------------------
; Tray menu
; -----------------------------------------------------------------------------

Menu, Tray, NoStandard
Menu, Tray, Add, 隐藏快捷方式箭头, TrayHideArrows
Menu, Tray, Add, 恢复快捷方式箭头, TrayRestoreArrows
Menu, Tray, Add
Menu, Tray, Add, 开机启动, ToggleStartup
Menu, Tray, Add
Menu, Tray, Add, 退出, QuitScript
Menu, Tray, Tip, DeskHider Plus
Gosub, RefreshTrayState
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
        MsgBox, 64, DeskHider Plus, 快捷方式箭头已经处于隐藏状态。
        Return
    }

    MsgBox, 36, DeskHider Plus, 将隐藏 Windows 快捷方式箭头。`n`n只在这一次操作时需要管理员权限。为了立即生效，完成后会重启 Windows 资源管理器，已打开的文件夹窗口可能会关闭。`n`n是否继续？
    IfMsgBox, No
        Return

    code := RunElevatedHelper("/hidearrows")
    if (code = "ERROR")
    {
        MsgBox, 48, DeskHider Plus, 操作未执行。可能是管理员权限请求被取消。
        Return
    }

    if (code != 0)
    {
        MsgBox, 16, DeskHider Plus, 隐藏快捷方式箭头失败。错误代码：%code%
        Return
    }

    RestartExplorer()
    DesktopIconsIsShow := 1
    Gosub, RefreshTrayState
Return

TrayRestoreArrows:
    MsgBox, 36, DeskHider Plus, 将恢复 DeskHider Plus 修改前的快捷方式箭头设置。`n`n只在这一次操作时需要管理员权限。为了立即生效，完成后会重启 Windows 资源管理器，已打开的文件夹窗口可能会关闭。`n`n是否继续？
    IfMsgBox, No
        Return

    code := RunElevatedHelper("/restorearrows")
    if (code = "ERROR")
    {
        MsgBox, 48, DeskHider Plus, 操作未执行。可能是管理员权限请求被取消。
        Return
    }

    if (code = 31)
    {
        MsgBox, 48, DeskHider Plus, 当前快捷方式箭头设置已经被其他程序或手动操作修改。为避免覆盖你的其他设置，本程序没有继续恢复。
        Return
    }

    if (code != 0)
    {
        MsgBox, 16, DeskHider Plus, 恢复快捷方式箭头失败。错误代码：%code%
        Return
    }

    RestartExplorer()
    DesktopIconsIsShow := 1
    Gosub, RefreshTrayState
Return

ToggleStartup:
    if (IsStartupEnabled())
    {
        RegDelete, %RUN_KEY%, DeskHiderPlus
        if (ErrorLevel)
        {
            MsgBox, 16, DeskHider Plus, 关闭开机启动失败。
            Return
        }
    }
    else
    {
        startupCmd := GetStartupCommand()
        RegWrite, REG_SZ, %RUN_KEY%, DeskHiderPlus, %startupCmd%
        if (ErrorLevel)
        {
            MsgBox, 16, DeskHider Plus, 设置开机启动失败。
            Return
        }
    }
    Gosub, RefreshTrayState
Return

RefreshTrayState:
    Menu, Tray, Uncheck, 隐藏快捷方式箭头
    Menu, Tray, Uncheck, 开机启动

    if (IsArrowsHiddenByUs())
        Menu, Tray, Check, 隐藏快捷方式箭头

    if (IsStartupEnabled())
        Menu, Tray, Check, 开机启动
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

    ; Recreate the icon every time so v2 PNG-based blank.ico is automatically repaired.
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

    ; v3 uses a new filename so Explorer cannot reuse the cached malformed v2 overlay.
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
