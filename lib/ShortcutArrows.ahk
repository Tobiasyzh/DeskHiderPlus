; Shortcut overlay storage and registry operations (AutoHotkey v1.1).
; Configuration is supplied by the caller; tests use isolated HKCU keys.

HideShortcutArrowsAdmin()
{
    global SHELL_ICONS_KEY, APP_REG_KEY, BLANK_ICON_DIR, BLANK_ICON_PATH, OVERLAY_VALUE

    UseNativeRegistryView()

    ; Prepare a complete, loadable icon before changing the shell setting.
    FileCreateDir, %BLANK_ICON_DIR%
    if (!InStr(FileExist(BLANK_ICON_DIR), "D"))
    {
        RestoreDefaultRegistryView()
        return 24
    }
    if (!WriteTransparentIcon(BLANK_ICON_PATH))
    {
        RestoreDefaultRegistryView()
        return 25
    }

    ; Keep the original backup across repairs, including migration from v2/v3.
    RegRead, backupState, %APP_REG_KEY%, BackupState
    if (ErrorLevel)
    {
        RegRead, oldValue, %SHELL_ICONS_KEY%, 29
        if (ErrorLevel || IsOwnedOverlayValue(oldValue))
            backupState := "MISSING"
        else
        {
            ; Write the payload before the marker so a failed write is retryable.
            RegWrite, REG_SZ, %APP_REG_KEY%, BackupValue, %oldValue%
            if (ErrorLevel)
            {
                RestoreDefaultRegistryView()
                return 23
            }
            backupState := "VALUE"
        }
        RegWrite, REG_SZ, %APP_REG_KEY%, BackupState, %backupState%
        if (ErrorLevel)
        {
            RestoreDefaultRegistryView()
            return 21
        }
    }

    RegWrite, REG_SZ, %SHELL_ICONS_KEY%, 29, %OVERLAY_VALUE%
    if (ErrorLevel)
    {
        RestoreDefaultRegistryView()
        return 26
    }

    ; Changing the file is not enough: the caller must rebuild the user's
    ; icon cache and verify the restored system image list in a fresh process.
    RestoreDefaultRegistryView()
    return 0
}

RestoreShortcutArrowsAdmin()
{
    global SHELL_ICONS_KEY, APP_REG_KEY, BLANK_ICON_DIR, OWNED_ICON_PATHS

    UseNativeRegistryView()
    RegRead, currentValue, %SHELL_ICONS_KEY%, 29
    currentMissing := ErrorLevel

    if (!currentMissing && !IsOwnedOverlayValue(currentValue))
    {
        RestoreDefaultRegistryView()
        return 31
    }

    RegRead, backupState, %APP_REG_KEY%, BackupState
    if (ErrorLevel)
        backupState := "MISSING"

    if (backupState = "VALUE")
    {
        RegRead, backupValue, %APP_REG_KEY%, BackupValue
        if (ErrorLevel)
        {
            RestoreDefaultRegistryView()
            return 32
        }
        ; Older releases could accidentally back up their own broken overlay.
        if (IsOwnedOverlayValue(backupValue))
            backupState := "MISSING"
    }
    else if (backupState != "MISSING")
    {
        RestoreDefaultRegistryView()
        return 32
    }

    if (backupState = "VALUE")
    {
        RegWrite, REG_SZ, %SHELL_ICONS_KEY%, 29, %backupValue%
        if (ErrorLevel)
        {
            RestoreDefaultRegistryView()
            return 33
        }
    }
    else if (!currentMissing)
    {
        RegDelete, %SHELL_ICONS_KEY%, 29
        if (ErrorLevel)
        {
            RestoreDefaultRegistryView()
            return 34
        }
    }

    ; A running shell may still have these files open. Keep the small inactive
    ; resources: removing them before the cache transition creates a broken path.
    RegDelete, %APP_REG_KEY%

    RestoreDefaultRegistryView()
    return 0
}

IsOwnedOverlayValue(value)
{
    global OWNED_ICON_PATHS

    for _, iconPath in OWNED_ICON_PATHS
    {
        quotedPath := Chr(34) iconPath Chr(34)
        if (value = iconPath || value = iconPath ",0" || value = quotedPath || value = quotedPath ",0")
            return true
    }
    return false
}

IsLegacyOverlayActive()
{
    global SHELL_ICONS_KEY, OVERLAY_VALUE, BLANK_ICON_PATH

    UseNativeRegistryView()
    RegRead, currentValue, %SHELL_ICONS_KEY%, 29
    err := ErrorLevel
    RestoreDefaultRegistryView()

    return (!err && IsOwnedOverlayValue(currentValue)
        && (currentValue != OVERLAY_VALUE || !FileExist(BLANK_ICON_PATH)))
}

IsArrowsConfiguredByUs()
{
    global SHELL_ICONS_KEY, OVERLAY_VALUE, BLANK_ICON_PATH

    UseNativeRegistryView()
    RegRead, currentValue, %SHELL_ICONS_KEY%, 29
    err := ErrorLevel
    RestoreDefaultRegistryView()

    return (!err && currentValue = OVERLAY_VALUE && FileExist(BLANK_ICON_PATH))
}

GetOverlayIconSizes()
{
    ; Include common scaled desktop sizes (notably 60px at 125% DPI).
    return [16, 20, 24, 28, 32, 36, 40, 48, 56, 60, 64, 72, 80, 96
        , 112, 120, 128, 144, 160, 192, 224, 240, 256]
}

BuildTransparentIcon(ByRef data)
{
    ; A fully empty legacy mask can preserve RGB while clearing destination
    ; alpha, cutting a rectangle out of an icon during later composition.
    ; Use explicit ARGB with a tiny alpha=1 anchor patch and a matching AND
    ; mask. A patch survives DPI resampling which can discard a single pixel.
    ; This preserves destination alpha with RGB changes of at most one level.
    sizes := GetOverlayIconSizes()
    totalSize := 6 + sizes.Length() * 16
    for _, size in sizes
        totalSize += 40 + size * size * 4 + ((size + 31) // 32) * 4 * size

    VarSetCapacity(data, totalSize, 0)
    NumPut(1, data, 2, "UShort") ; ICONDIR.type = icon
    NumPut(sizes.Length(), data, 4, "UShort")
    imageOffset := 6 + sizes.Length() * 16

    for index, size in sizes
    {
        colorSize := size * size * 4
        maskSize := ((size + 31) // 32) * 4 * size
        imageSize := 40 + colorSize + maskSize
        entry := 6 + (index - 1) * 16
        NumPut(Mod(size, 256), data, entry, "UChar")
        NumPut(Mod(size, 256), data, entry + 1, "UChar")
        NumPut(1, data, entry + 4, "UShort")
        NumPut(32, data, entry + 6, "UShort")
        NumPut(imageSize, data, entry + 8, "UInt")
        NumPut(imageOffset, data, entry + 12, "UInt")

        NumPut(40, data, imageOffset, "UInt") ; BITMAPINFOHEADER
        NumPut(size, data, imageOffset + 4, "Int")
        NumPut(size * 2, data, imageOffset + 8, "Int") ; XOR + AND height
        NumPut(1, data, imageOffset + 12, "UShort")
        NumPut(32, data, imageOffset + 14, "UShort")
        NumPut(colorSize + maskSize, data, imageOffset + 20, "UInt")
        DllCall("RtlFillMemory", "Ptr", &data + imageOffset + 40 + colorSize
            , "UPtr", maskSize, "UChar", 255)
        anchor := Max(2, Ceil(size / 16))
        maskStride := ((size + 31) // 32) * 4
        Loop, %anchor%
        {
            y := A_Index - 1
            Loop, %anchor%
            {
                x := A_Index - 1
                NumPut(1, data, imageOffset + 40 + (y * size + x) * 4 + 3, "UChar")
                byteOffset := imageOffset + 40 + colorSize + y * maskStride + x // 8
                NumPut(NumGet(data, byteOffset, "UChar") & ~(0x80 >> Mod(x, 8)), data, byteOffset, "UChar")
            }
        }
        imageOffset += imageSize
    }
    return totalSize
}

WriteTransparentIcon(filePath)
{
    binarySize := BuildTransparentIcon(binaryData)
    tempPath := filePath "." DllCall("GetCurrentProcessId") ".tmp"
    file := FileOpen(tempPath, "w")
    if (!IsObject(file))
        return false
    written := file.RawWrite(binaryData, binarySize)
    file.Close()

    ; Validate through Windows before publishing the file or registry value.
    valid := (written = binarySize)
    if (valid)
    {
        for _, size in GetOverlayIconSizes()
        {
            icon := DllCall("LoadImageW", "Ptr", 0, "WStr", tempPath, "UInt", 1
                , "Int", size, "Int", size, "UInt", 0x10, "Ptr") ; LR_LOADFROMFILE
            if (!icon)
            {
                valid := false
                break
            }
            DllCall("DestroyIcon", "Ptr", icon)
        }
    }
    if (valid)
    {
        ; Replace atomically; never truncate a file Explorer may already use.
        FileMove, %tempPath%, %filePath%, 1
        valid := !ErrorLevel
    }
    FileDelete, %tempPath%
    return valid
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
