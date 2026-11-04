#NoEnv
#NoTrayIcon
#SingleInstance, Off
SetBatchLines, -1

; Isolated filesystem and process-local registry tests. Never stops Explorer.
if (A_Args.Length() < 1)
    ExitApp, 2
global OUTPUT_DIR := A_Args[1]
global LAST_RECOVERY_DIR := OUTPUT_DIR "\backups"
global RECOVERY_ROOT := OUTPUT_DIR
global ASSERTIONS := 0
global TEST_KEY := "Software\DeskHiderPlus_CacheTest_" DllCall("GetCurrentProcessId")
global testRoot := 0
OnError("TestFailure")
FileCreateDir, %OUTPUT_DIR%
FileCreateDir, %LAST_RECOVERY_DIR%

if (A_Args.Length() = 2 && A_Args[2] = "exit-probe")
    ExitApp, 7
if (A_Args.Length() = 2 && A_Args[2] = "hang-probe")
{
    Sleep, 5000
    ExitApp, 0
}

if (A_Args.Length() = 2)
{
    ; Separate child for each icon: FileIconInit must not reuse a previous list.
    iconPath := OUTPUT_DIR "\" A_Args[2] ".ico"
    SetupRegistryOverride(iconPath)
    result := VerifyRestoredShortcutOverlay()
    Assert(result = (A_Args[2] = "blank" ? 0 : 41), "full Shell init accepts blank and rejects visible overlay (" result ")")
    RestoreRegistryOverride()
    FileAppend, % "PASS: restored Shell overlay " A_Args[2] " (" (A_PtrSize * 8) "-bit).`n", *
    ExitApp, 0
}

fakeLocal := OUTPUT_DIR "\fake-local"
FileCreateDir, % fakeLocal "\Microsoft\Windows\Explorer\iconcache_directory.db"
for _, name in ["IconCache.db", "Microsoft\Windows\Explorer\iconcache_16.db"
    , "Microsoft\Windows\Explorer\thumbcache_16.db", "Microsoft\Windows\Explorer\iconcache_note.txt"]
{
    path := fakeLocal "\" name
    FileAppend, % "original bytes: " name, %path%
}
files := GetIconCacheFiles(fakeLocal)
Assert(files.Length() = 2, "only exact icon cache database files are selected")
Assert(StageIconCacheFiles(files, ".stage-one", staged) = 0, "stage isolated caches")
Assert(staged.Length() = 2, "both cache files staged")
Assert(!FileExist(fakeLocal "\IconCache.db"), "old cache name is released")
Assert(FileExist(fakeLocal "\Microsoft\Windows\Explorer\thumbcache_16.db"), "thumbnail cache is preserved")
Assert(FileExist(fakeLocal "\Microsoft\Windows\Explorer\iconcache_note.txt"), "unrelated files are preserved")
Assert(ArchiveStagedIconCaches(staged, LAST_RECOVERY_DIR) = 0, "archive first rebuild")
for _, item in staged
    Assert(!FileExist(item.path), "staged cache is archived off the original volume")

path := fakeLocal "\IconCache.db"
FileAppend, second generation, %path%
files := GetIconCacheFiles(fakeLocal)
Assert(StageIconCacheFiles(files, ".stage-two", staged) = 0, "stage second rebuild")
Assert(ArchiveStagedIconCaches(staged, LAST_RECOVERY_DIR) = 0, "second rebuild does not overwrite first backup")
lockedPath := fakeLocal "\IconCache.db"
FileAppend, locked generation, %lockedPath%
lockedFile := FileOpen(lockedPath, "r-rwd")
Assert(IsObject(lockedFile), "lock fake cache")
Assert(StageIconCacheFiles([lockedPath], ".locked-stage", staged) = 1, "locked cache returns failure")
lockedFile.Close()
Assert(FileExist(lockedPath) && staged.Length() = 0, "failed staging leaves cache intact")

prefix := A_IsCompiled ? Chr(34) A_ScriptFullPath Chr(34) : Chr(34) A_AhkPath Chr(34) " " Chr(34) A_ScriptFullPath Chr(34)
Assert(RunBoundedOverlayHelper(prefix " " Chr(34) OUTPUT_DIR Chr(34) " exit-probe") = 7, "bounded helper preserves exit code")
Assert(RunBoundedOverlayHelper(prefix " " Chr(34) OUTPUT_DIR Chr(34) " hang-probe", 200) = 43, "bounded helper terminates a stalled probe")

Assert(WriteTransparentIcon(OUTPUT_DIR "\blank.ico"), "write alpha-preserving control")
icon := DllCall("LoadImageW", "Ptr", 0, "WStr", OUTPUT_DIR "\blank.ico", "UInt", 1, "Int", 64, "Int", 64, "UInt", 0x10, "Ptr")
Assert(icon && IsNativeIconTransparent(icon) = 1, "native health check accepts transparency")
DllCall("DestroyIcon", "Ptr", icon)
BuildTransparentIcon(data)
offset := NumGet(data, 18, "UInt") ; first frame's DIB offset
colorSize := 16 * 16 * 4
; All pixels become opaque black: an intentional bad-overlay control.
DllCall("RtlZeroMemory", "Ptr", &data + offset + 40 + colorSize, "UPtr", 16 * 4)
Loop, 256
    NumPut(0xFF000000, data, offset + 40 + (A_Index - 1) * 4, "UInt")
file := FileOpen(OUTPUT_DIR "\visible.ico", "w")
file.RawWrite(data, VarSetCapacity(data))
file.Close()
icon := DllCall("LoadImageW", "Ptr", 0, "WStr", OUTPUT_DIR "\visible.ico", "UInt", 1, "Int", 16, "Int", 16, "UInt", 0x10, "Ptr")
Assert(icon && IsNativeIconTransparent(icon) = 0, "native health check rejects an opaque overlay")
DllCall("DestroyIcon", "Ptr", icon)

; A legacy all-zero-alpha image preserves RGB but destroys destination alpha.
BuildTransparentIcon(legacy)
Loop, % NumGet(legacy, 4, "UShort")
{
    entry := 6 + (A_Index - 1) * 16
    width := NumGet(legacy, entry, "UChar")
    if (!width)
        width := 256
    offset := NumGet(legacy, entry + 12, "UInt")
    DllCall("RtlZeroMemory", "Ptr", &legacy + offset + 40, "UPtr", width * width * 4)
    DllCall("RtlFillMemory", "Ptr", &legacy + offset + 40 + width * width * 4
        , "UPtr", ((width + 31) // 32) * 4 * width, "UChar", 255)
}
file := FileOpen(OUTPUT_DIR "\legacy.ico", "w")
file.RawWrite(legacy, VarSetCapacity(legacy))
file.Close()
icon := DllCall("LoadImageW", "Ptr", 0, "WStr", OUTPUT_DIR "\legacy.ico", "UInt", 1, "Int", 64, "Int", 64, "UInt", 0x10, "Ptr")
Assert(icon && IsNativeIconTransparent(icon) = 0, "health check rejects RGB-preserving alpha damage")
DllCall("DestroyIcon", "Ptr", icon)

WriteLegacyMaskControl(OUTPUT_DIR "\mono.ico")
icon := DllCall("LoadImageW", "Ptr", 0, "WStr", OUTPUT_DIR "\mono.ico", "UInt", 1, "Int", 64, "Int", 64, "UInt", 0x10, "Ptr")
Assert(icon && IsNativeIconTransparent(icon) = 0, "test1 monochrome mask fails the new alpha check")
DllCall("DestroyIcon", "Ptr", icon)

for _, mode in ["blank", "visible", "legacy", "mono"]
{
    ; Make EVERY frame opaque for the full-Shell negative control.
    if (mode = "visible")
    {
        Loop, % NumGet(data, 4, "UShort")
        {
            entry := 6 + (A_Index - 1) * 16
            width := NumGet(data, entry, "UChar")
            if (!width)
                width := 256
            offset := NumGet(data, entry + 12, "UInt")
            colorSize := width * width * 4
            maskSize := ((width + 31) // 32) * 4 * width
            DllCall("RtlZeroMemory", "Ptr", &data + offset + 40 + colorSize, "UPtr", maskSize)
            Loop, % width * width
                NumPut(0xFF000000, data, offset + 40 + (A_Index - 1) * 4, "UInt")
        }
        file := FileOpen(OUTPUT_DIR "\visible.ico", "w")
        file.RawWrite(data, VarSetCapacity(data))
        file.Close()
    }
    if (A_IsCompiled)
        RunWait, "%A_ScriptFullPath%" /ErrorStdOut "%OUTPUT_DIR%" %mode%,, Hide UseErrorLevel
    else
        RunWait, "%A_AhkPath%" /ErrorStdOut "%A_ScriptFullPath%" "%OUTPUT_DIR%" %mode%,, Hide UseErrorLevel
    Assert(ErrorLevel = 0, "full Shell child test: " mode)
}
FileAppend, % "PASS: " ASSERTIONS " cache/health assertions (" (A_PtrSize * 8) "-bit).`n", *
ExitApp, 0

WriteLegacyMaskControl(path)
{
    VarSetCapacity(data, 198, 0)
    NumPut(1, data, 2, "UShort")
    NumPut(1, data, 4, "UShort")
    NumPut(16, data, 6, "UChar")
    NumPut(16, data, 7, "UChar")
    NumPut(2, data, 8, "UChar")
    NumPut(1, data, 10, "UShort")
    NumPut(1, data, 12, "UShort")
    NumPut(176, data, 14, "UInt")
    NumPut(22, data, 18, "UInt")
    NumPut(40, data, 22, "UInt")
    NumPut(16, data, 26, "Int")
    NumPut(32, data, 30, "Int")
    NumPut(1, data, 34, "UShort")
    NumPut(1, data, 36, "UShort")
    NumPut(128, data, 42, "UInt")
    NumPut(2, data, 54, "UInt")
    NumPut(0x00FFFFFF, data, 66, "UInt")
    DllCall("RtlFillMemory", "Ptr", &data + 134, "UPtr", 64, "UChar", 255)
    file := FileOpen(path, "w")
    file.RawWrite(data, 198)
    file.Close()
}

SetupRegistryOverride(iconPath)
{
    global TEST_KEY, testRoot
    RegWrite, REG_SZ, HKCU\%TEST_KEY%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons, 29, %iconPath%`,0
    Assert(!ErrorLevel, "write isolated Shell registry value")
    result := DllCall("Advapi32\RegOpenKeyExW", "Ptr", -2147483647, "WStr", TEST_KEY, "UInt", 0, "UInt", 0xF003F, "PtrP", testRoot, "UInt")
    Assert(result = 0, "open isolated registry root")
    Assert(DllCall("Advapi32\RegOverridePredefKey", "Ptr", -2147483646, "Ptr", testRoot, "UInt") = 0, "redirect HKLM in this child only")
    Assert(DllCall("Advapi32\RegOverridePredefKey", "Ptr", -2147483647, "Ptr", testRoot, "UInt") = 0, "redirect HKCU in this child only")
}

RestoreRegistryOverride()
{
    global testRoot, TEST_KEY
    DllCall("Advapi32\RegOverridePredefKey", "Ptr", -2147483646, "Ptr", 0)
    DllCall("Advapi32\RegOverridePredefKey", "Ptr", -2147483647, "Ptr", 0)
    if (testRoot)
        DllCall("Advapi32\RegCloseKey", "Ptr", testRoot)
    testRoot := 0
    RegDelete, HKCU\%TEST_KEY%
}

Assert(condition, message)
{
    global ASSERTIONS
    ASSERTIONS++
    if (!condition)
        throw Exception(message)
}

TestFailure(e)
{
    global lockedFile
    if (IsObject(lockedFile))
        lockedFile.Close()
    RestoreRegistryOverride()
    FileAppend, % "FAIL: " e.Message " (line " e.Line ")`n", *
    ExitApp, 1
}

#Include %A_ScriptDir%\..\lib\ShortcutArrows.ahk
#Include %A_ScriptDir%\..\lib\ShellIconCache.ahk
