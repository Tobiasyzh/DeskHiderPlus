#NoEnv
#SingleInstance, Off
SetBatchLines, -1

; Usage: AutoHotkeyU64.exe /ErrorStdOut ShortcutArrows.test.ahk <output-directory>
; Never touches the real Explorer settings or restarts the user's desktop.
if (A_Args.Length() != 1)
    ExitApp, 2
global OUTPUT_DIR := A_Args[1]
global TEST_KEY := "HKCU\Software\DeskHiderPlus_Test_" DllCall("GetCurrentProcessId")
global SHELL_ICONS_KEY := TEST_KEY "\Shell Icons"
global APP_REG_KEY := TEST_KEY "\Backup"
global BLANK_ICON_DIR := OUTPUT_DIR "\test-icons"
global BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v4_mask.ico"
global V3_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank_v3.ico"
global LEGACY_BLANK_ICON_PATH := BLANK_ICON_DIR "\blank.ico"
global OWNED_ICON_PATHS := [BLANK_ICON_PATH, V3_BLANK_ICON_PATH, LEGACY_BLANK_ICON_PATH]
global OVERLAY_VALUE := BLANK_ICON_PATH ",0"
global ASSERTIONS := 0

exitCode := 0
OnError("TestFailure")
    FileCreateDir, %OUTPUT_DIR%
    Assert(WriteTransparentIcon(OUTPUT_DIR "\blank_v4_mask.ico"), "export generated ICO")

    ResetState()
    result := HideShortcutArrowsAdmin()
    Assert(result = 0, "first hide succeeds (code " result ")")
    Assert(IsArrowsHiddenByUs(), "new overlay is active")
    Assert(!IsLegacyOverlayActive(), "new overlay needs no migration")
    Assert(ReadValue(APP_REG_KEY, "BackupState") = "MISSING", "missing original is recorded")
    Assert(RestoreShortcutArrowsAdmin() = 0, "restore default succeeds")
    Assert(ValueMissing(SHELL_ICONS_KEY, "29"), "restore removes only our overlay value")
    Assert(!FileExist(BLANK_ICON_PATH), "restore removes new icon")

    ResetState()
    original := "C:\Example\custom overlay.dll,7"
    WriteValue(SHELL_ICONS_KEY, "29", original)
    Assert(HideShortcutArrowsAdmin() = 0, "hide over custom overlay")
    Assert(HideShortcutArrowsAdmin() = 0, "reapply repairs the current overlay")
    Assert(ReadValue(APP_REG_KEY, "BackupValue") = original, "repair preserves original backup")
    Assert(RestoreShortcutArrowsAdmin() = 0, "restore custom overlay")
    Assert(ReadValue(SHELL_ICONS_KEY, "29") = original, "custom overlay survives hide/repair/restore")

    ; Both legacy filenames, indexed/unindexed and quoted paths, are recognized.
    for _, legacyPath in [LEGACY_BLANK_ICON_PATH, V3_BLANK_ICON_PATH]
    {
        for _, legacyValue in [legacyPath, legacyPath ",0", Chr(34) legacyPath Chr(34) ",0"]
        {
            ResetState()
            WriteValue(SHELL_ICONS_KEY, "29", legacyValue)
            Assert(IsLegacyOverlayActive(), "detect legacy overlay: " legacyValue)
            Assert(HideShortcutArrowsAdmin() = 0, "migrate legacy without a backup")
            Assert(ReadValue(APP_REG_KEY, "BackupState") = "MISSING", "do not back up our broken icon")
            Assert(RestoreShortcutArrowsAdmin() = 0, "restore migrated legacy")
            Assert(ValueMissing(SHELL_ICONS_KEY, "29"), "legacy is not resurrected on restore")
        }
    }

    ResetState()
    WriteValue(SHELL_ICONS_KEY, "29", V3_BLANK_ICON_PATH)
    WriteValue(APP_REG_KEY, "BackupValue", original)
    WriteValue(APP_REG_KEY, "BackupState", "VALUE")
    Assert(HideShortcutArrowsAdmin() = 0, "migrate v3 with existing backup")
    Assert(RestoreShortcutArrowsAdmin() = 0, "restore after v3 migration")
    Assert(ReadValue(SHELL_ICONS_KEY, "29") = original, "v3 original backup is preserved")

    ResetState()
    Assert(HideShortcutArrowsAdmin() = 0, "prepare conflict test")
    replacement := "C:\AnotherApp\replacement.ico,0"
    WriteValue(SHELL_ICONS_KEY, "29", replacement)
    Assert(!IsLegacyOverlayActive(), "do not offer migration for another app")
    Assert(RestoreShortcutArrowsAdmin() = 31, "refuse to overwrite another app")
    Assert(ReadValue(SHELL_ICONS_KEY, "29") = replacement, "another app's setting remains")
    Assert(FileExist(BLANK_ICON_PATH), "conflict retains files and backup")
    Assert(!IsOwnedOverlayValue(BLANK_ICON_PATH ".other,0"), "ownership requires exact path")

    ResetState()
    Assert(HideShortcutArrowsAdmin() = 0, "prepare missing-file repair")
    FileDelete, %BLANK_ICON_PATH%
    Assert(IsLegacyOverlayActive(), "missing new icon offers repair")
    Assert(!IsArrowsHiddenByUs(), "missing new icon is not shown as healthy")
    Assert(HideShortcutArrowsAdmin() = 0, "missing new icon can be recreated")
    Assert(IsArrowsHiddenByUs(), "repaired icon is healthy")

    ResetState()
    Assert(HideShortcutArrowsAdmin() = 0, "prepare stale-backup test")
    WriteValue(APP_REG_KEY, "BackupValue", V3_BLANK_ICON_PATH)
    WriteValue(APP_REG_KEY, "BackupState", "VALUE")
    Assert(RestoreShortcutArrowsAdmin() = 0, "discard an old self-backup")
    Assert(ValueMissing(SHELL_ICONS_KEY, "29"), "never restore a deleted v3 icon")

    ResetState()
    Assert(HideShortcutArrowsAdmin() = 0, "prepare damaged-backup test")
    WriteValue(APP_REG_KEY, "BackupState", "VALUE")
    Assert(RestoreShortcutArrowsAdmin() = 32, "incomplete backup aborts restore")
    Assert(ReadValue(SHELL_ICONS_KEY, "29") = OVERLAY_VALUE, "failed restore retains active setting")
    Assert(FileExist(BLANK_ICON_PATH), "failed restore retains active icon")

    ; A failed atomic replacement must not truncate the existing icon.
    FileGetSize, oldSize, %BLANK_ICON_PATH%
    lockedFile := FileOpen(BLANK_ICON_PATH, "r-rwd")
    Assert(IsObject(lockedFile), "lock icon for failure test")
    Assert(!WriteTransparentIcon(BLANK_ICON_PATH), "locked icon replacement fails cleanly")
    lockedFile.Close()
    FileGetSize, newSize, %BLANK_ICON_PATH%
    Assert(oldSize = newSize, "failed replacement preserves existing icon")

    FileAppend, % "PASS: " ASSERTIONS " overlay assertions (" (A_PtrSize * 8) "-bit).`n", *
ResetState()
ExitApp, %exitCode%

TestFailure(e)
{
    global lockedFile
    if (IsObject(lockedFile))
        lockedFile.Close()
    FileAppend, % "FAIL: " e.Message " (line " e.Line ")`n", *
    ResetState()
    ExitApp, 1
}

Assert(condition, message)
{
    global ASSERTIONS
    ASSERTIONS++
    if (!condition)
        throw Exception(message)
}

WriteValue(key, name, value)
{
    UseNativeRegistryView()
    RegWrite, REG_SZ, %key%, %name%, %value%
    Assert(!ErrorLevel, "test registry write")
    RestoreDefaultRegistryView()
}

ReadValue(key, name)
{
    UseNativeRegistryView()
    RegRead, value, %key%, %name%
    err := ErrorLevel
    RestoreDefaultRegistryView()
    Assert(!err, "expected registry value: " name)
    return value
}

ValueMissing(key, name)
{
    UseNativeRegistryView()
    RegRead, value, %key%, %name%
    err := ErrorLevel
    RestoreDefaultRegistryView()
    return err
}

ResetState()
{
    global TEST_KEY, OWNED_ICON_PATHS, BLANK_ICON_DIR
    UseNativeRegistryView()
    RegDelete, %TEST_KEY%
    RestoreDefaultRegistryView()
    for _, iconPath in OWNED_ICON_PATHS
        FileDelete, %iconPath%
    FileRemoveDir, %BLANK_ICON_DIR%
}

#Include %A_ScriptDir%\..\lib\ShortcutArrows.ahk
