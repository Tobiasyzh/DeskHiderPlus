; One-shot cache recovery and native Shell overlay validation (AHK v1.1).
; Never runs from a timer. The resident process must remain non-elevated so the
; cache belongs to the user who requested the operation, not a UAC administrator.

NewIconRecoveryFolder()
{
    global RECOVERY_ROOT, LAST_RECOVERY_DIR
    LAST_RECOVERY_DIR := RECOVERY_ROOT "\" A_Now "-" DllCall("GetCurrentProcessId") "-" A_TickCount
    FileCreateDir, %LAST_RECOVERY_DIR%
    if (!InStr(FileExist(LAST_RECOVERY_DIR), "D"))
        return ""
    probe := LAST_RECOVERY_DIR "\repair.log"
    FileAppend, % "DeskHider Plus icon recovery - " A_Now "`r`n", %probe%, UTF-8
    if (ErrorLevel)
        return ""
    return LAST_RECOVERY_DIR
}

LogIconRecovery(message)
{
    global LAST_RECOVERY_DIR
    if (LAST_RECOVERY_DIR != "")
        FileAppend, % A_Now " " message "`r`n", % LAST_RECOVERY_DIR "\repair.log", UTF-8
}

SnapshotShortcutSettings()
{
    global SHELL_ICONS_KEY, APP_REG_KEY
    UseNativeRegistryView()
    for _, key in [SHELL_ICONS_KEY, APP_REG_KEY]
    {
        for _, name in ["29", "BackupState", "BackupValue"]
        {
            RegRead, value, %key%, %name%
            LogIconRecovery(key " / " name " = " (ErrorLevel ? "<missing>" : value))
        }
    }
    RestoreDefaultRegistryView()
}

GetIconCacheFiles(localRoot)
{
    files := []
    ; Exact allow-list. Never include thumbnail caches, directories or arbitrary
    ; files whose names merely start with 'iconcache'.
    legacy := localRoot "\IconCache.db"
    if (FileExist(legacy) && !InStr(FileExist(legacy), "D"))
        files.Push(legacy)
    pattern := localRoot "\Microsoft\Windows\Explorer\iconcache_*.db"
    Loop, Files, %pattern%, F
        files.Push(A_LoopFileFullPath)
    return files
}

StageIconCacheFiles(files, suffix, ByRef staged)
{
    staged := []
    failed := 0
    for _, path in files
    {
        if (!FileExist(path))
            continue
        ; Rename on the same volume while Explorer is stopped. Copying all
        ; databases to another drive here would race AutoRestartShell.
        stagePath := path suffix
        FileMove, %path%, %stagePath%, 0
        if (ErrorLevel)
        {
            failed++
            LogIconRecovery("Cache still locked: " path " (Win32 " A_LastError ")")
        }
        else
            staged.Push({source: path, path: stagePath})
    }
    return failed
}

ArchiveStagedIconCaches(staged, backupDir)
{
    failed := 0
    for index, item in staged
    {
        SplitPath, % item.path, name
        target := backupDir "\" index "-" name
        FileMove, % item.path, %target%, 0
        if (ErrorLevel)
        {
            failed++
            LogIconRecovery("Backup retained at " item.path)
        }
        else
            LogIconRecovery("Archived " item.source " -> " target)
    }
    return failed
}

EnsureDesktopShell()
{
    started := false
    deadline := A_TickCount + 20000
    while (A_TickCount < deadline)
    {
        ; A new taskbar can exist before the desktop shell is ready. Require
        ; both, rather than returning failure immediately after WinWait.
        if (DllCall("User32\GetShellWindow", "Ptr") && WinExist("ahk_class Shell_TrayWnd"))
            return true
        if (!started && deadline - A_TickCount < 17500)
        {
            Run, % A_WinDir "\explorer.exe",, UseErrorLevel
            started := true
        }
        Sleep, 100
    }
    return false
}

RunBoundedOverlayHelper(command, timeoutMs := 15000)
{
    ; Keep an actual process handle so a hung Shell API cannot block repair
    ; forever and an early child exit cannot lose its exit status.
    VarSetCapacity(commandLine, (StrLen(command) + 1) * 2, 0)
    StrPut(command, &commandLine, "UTF-16")
    VarSetCapacity(startup, A_PtrSize = 8 ? 104 : 68, 0)
    NumPut(VarSetCapacity(startup), startup, 0, "UInt")
    NumPut(1, startup, A_PtrSize = 8 ? 60 : 44, "UInt") ; STARTF_USESHOWWINDOW
    VarSetCapacity(process, A_PtrSize * 2 + 8, 0)
    ok := DllCall("CreateProcessW", "Ptr", 0, "Ptr", &commandLine, "Ptr", 0, "Ptr", 0
        , "Int", 0, "UInt", 0x08000000, "Ptr", 0, "WStr", A_ScriptDir
        , "Ptr", &startup, "Ptr", &process, "Int")
    if (!ok)
        return 42
    handle := NumGet(process, 0, "Ptr")
    DllCall("CloseHandle", "Ptr", NumGet(process, A_PtrSize, "Ptr"))
    waitResult := DllCall("WaitForSingleObject", "Ptr", handle, "UInt", timeoutMs, "UInt")
    if (waitResult != 0)
    {
        DllCall("TerminateProcess", "Ptr", handle, "UInt", 43)
        DllCall("CloseHandle", "Ptr", handle)
        return 43
    }
    result := 42
    DllCall("GetExitCodeProcess", "Ptr", handle, "UIntP", result)
    DllCall("CloseHandle", "Ptr", handle)
    return result
}

RebuildShortcutIconCache()
{
    global LAST_RECOVERY_DIR
    if (LAST_RECOVERY_DIR = "" || !InStr(FileExist(LAST_RECOVERY_DIR), "D"))
        return 51
    EnvGet, localRoot, LOCALAPPDATA
    if (localRoot = "" || !InStr(FileExist(localRoot), "D"))
        return 52
    files := GetIconCacheFiles(localRoot)
    shell := DllCall("User32\GetShellWindow", "Ptr")
    pid := 0
    if (shell)
        DllCall("User32\GetWindowThreadProcessId", "Ptr", shell, "UIntP", pid)
    if (pid)
    {
        ; Only the current desktop's Explorer, never every user's explorer.exe.
        Process, Close, %pid%
        Process, WaitClose, %pid%, 5
        if (ErrorLevel)
        {
            LogIconRecovery("Could not stop desktop Explorer " pid)
            return 53
        }
    }
    suffix := ".DeskHiderPlus-" DllCall("GetCurrentProcessId") "-" A_TickCount ".bak"
    failures := StageIconCacheFiles(files, suffix, staged)
    shellReady := EnsureDesktopShell()
    archiveFailures := ArchiveStagedIconCaches(staged, LAST_RECOVERY_DIR)
    LogIconRecovery("Cache rebuild: " staged.Length() " staged, " failures " locked, " archiveFailures " archive errors; shell=" shellReady)
    if (!shellReady)
        return 55
    if (failures)
        return 54
    if (archiveFailures)
        return 56
    return 0
}

VerifyRestoredShortcutOverlay()
{
    ; This entry point must execute in a NEW process. A resident process can
    ; retain an obsolete system image list even after Explorer has restarted.
    DllCall("Ole32\CoInitialize", "Ptr", 0)
    shellModule := DllCall("LoadLibraryW", "WStr", "shell32.dll", "Ptr")
    init := DllCall("GetProcAddress", "Ptr", shellModule, "Ptr", 660, "Ptr")
    if (!init || !DllCall(init, "Int", 1, "Int")) ; FileIconInit(TRUE)
        return 42
    slot := DllCall("Shell32\SHGetIconOverlayIndexW", "Ptr", 0, "Int", 0x0FFFFFFE, "Int")
    if (slot < 1 || slot > 15)
        return 42
    VarSetCapacity(iid, 16, 0)
    DllCall("Ole32\CLSIDFromString", "WStr", "{46EB5926-582E-4017-9FDF-E8998DAA0950}", "Ptr", &iid)
    for _, listType in [0, 1, 2, 4]
    {
        images := 0
        hr := DllCall("Shell32\SHGetImageList", "Int", listType, "Ptr", &iid, "PtrP", images, "Int")
        if (hr != 0 || !images)
            return 42
        vtable := NumGet(images + 0, 0, "Ptr")
        imageIndex := -1
        hr := DllCall(NumGet(vtable + 0, 31 * A_PtrSize, "Ptr"), "Ptr", images
            , "Int", slot, "IntP", imageIndex, "Int")
        width := 0, height := 0, flags := 0
        DllCall(NumGet(vtable + 0, 16 * A_PtrSize, "Ptr"), "Ptr", images, "IntP", width, "IntP", height)
        if (imageIndex >= 0)
            DllCall(NumGet(vtable + 0, 30 * A_PtrSize, "Ptr"), "Ptr", images, "Int", imageIndex, "UIntP", flags)
        LogIconRecovery("Shell dimensions " width "x" height ", item flags=" flags)
        icon := 0
        if (hr = 0 && imageIndex >= 0)
            hr := DllCall(NumGet(vtable + 0, 10 * A_PtrSize, "Ptr"), "Ptr", images
                , "Int", imageIndex, "UInt", 1, "PtrP", icon, "Int")
        transparent := (hr = 0 && icon) ? IsNativeIconTransparent(icon) : -1
        LogIconRecovery("Shell list " listType ", slot " slot ", image " imageIndex ", transparent=" transparent ", hr=" hr)
        if (icon)
            DllCall("DestroyIcon", "Ptr", icon)
        DllCall(NumGet(vtable + 0, 2 * A_PtrSize, "Ptr"), "Ptr", images, "UInt")
        if (transparent < 0)
            return 42
        if (!transparent)
            return 41
    }
    return 0
}

IsNativeIconTransparent(icon)
{
    size := 64
    dc := DllCall("Gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
    VarSetCapacity(header, 40, 0)
    NumPut(40, header, 0, "UInt")
    NumPut(size, header, 4, "Int")
    NumPut(-size, header, 8, "Int")
    NumPut(1, header, 12, "UShort")
    NumPut(32, header, 14, "UShort")
    bits := 0
    bitmap := DllCall("Gdi32\CreateDIBSection", "Ptr", dc, "Ptr", &header, "UInt", 0
        , "PtrP", bits, "Ptr", 0, "UInt", 0, "Ptr")
    if (!dc || !bitmap || !bits)
    {
        if (bitmap)
            DllCall("Gdi32\DeleteObject", "Ptr", bitmap)
        if (dc)
            DllCall("Gdi32\DeleteDC", "Ptr", dc)
        return -1
    }
    old := DllCall("Gdi32\SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
    ; RGB-only checks miss legacy GDI masks zeroing the destination alpha.
    ; A tiny alpha=1 anchor may alter a few scaled RGB pixels by one level;
    ; opacity must remain intact and the rest must remain unchanged.
    result := 1
    for _, color in [0xFF376B9D, 0xFFC78F43]
    {
        Loop, % size * size
            NumPut(color, bits + 0, (A_Index - 1) * 4, "UInt")
        if (!DllCall("User32\DrawIconEx", "Ptr", dc, "Int", 0, "Int", 0, "Ptr", icon
            , "Int", size, "Int", size, "UInt", 0, "Ptr", 0, "UInt", 3))
        {
            result := -1
            break
        }
        DllCall("Gdi32\GdiFlush")
        changed := 0
        Loop, % size * size
        {
            pixel := NumGet(bits + 0, (A_Index - 1) * 4, "UInt")
            if ((pixel >> 24) != 255)
            {
                result := 0
                break
            }
            if ((pixel & 0xFFFFFF) != (color & 0xFFFFFF))
            {
                changed++
                if (changed > 64 || Abs((pixel & 255) - (color & 255)) > 1
                    || Abs(((pixel >> 8) & 255) - ((color >> 8) & 255)) > 1
                    || Abs(((pixel >> 16) & 255) - ((color >> 16) & 255)) > 1)
                {
                    result := 0
                    break
                }
            }
        }
        if (result != 1)
            break
    }
    DllCall("Gdi32\SelectObject", "Ptr", dc, "Ptr", old)
    DllCall("Gdi32\DeleteObject", "Ptr", bitmap)
    DllCall("Gdi32\DeleteDC", "Ptr", dc)
    return result
}
