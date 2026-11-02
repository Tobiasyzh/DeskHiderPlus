# DeskHider Plus

A lightweight Windows 10 desktop utility based on [DeskHider](https://github.com/iandiv/DeskHider).

It combines two small desktop-cleanup features in one resident utility:

- Double-click an empty area of the desktop to hide/show desktop icons.
- Hide or restore Windows shortcut arrows from the tray menu.

The shortcut-arrow feature does **not** poll in the background. It only updates the Windows shell setting when you explicitly choose the tray command. Normal resident work is limited to the desktop double-click listener.

## Features

- Windows 10 focused.
- Double-click empty desktop space to hide/show all desktop icons.
- Double-clicking an icon itself is not treated as an empty-desktop double click.
- Hide shortcut arrows using `Shell Icons\\29`.
- Restore the previous `Shell Icons\\29` value safely.
- Uses a multi-size **1bpp mask-only ICO**, without an alpha channel, to avoid black squares or missing lower-left corners caused by 32bpp transparent overlays on affected systems.
- Requests administrator privileges only for hide/restore shortcut-arrow actions.
- Optional startup toggle from the tray menu.
- Optional tray icon. Hide it after setup for a cleaner notification area.
- If the tray icon is hidden, launch `DeskHiderPlus.exe` again to bring it back.
- English-only user interface.
- No installer required.

## Download

### v1.1.1 beta 1 — shortcut overlay repair

[Download v1.1.1 beta 1](https://github.com/Tobiasyzh/DeskHiderPlus/releases/tag/v1.1.1-beta.1)

This candidate replaces the single-size, all-zero-alpha `blank_v3.ico` with a monochrome AND/XOR-mask icon in ten sizes (16–256 px). It also detects v3 settings during upgrade, allows reapplying the repair from the tray, and invalidates composed icon caches once after the requested Explorer restart.

The icon format, native Windows rendering, image-list cache round-trip, and isolated registry migration/restore tests pass. **Cold-boot behavior on the affected Windows 10 machine still needs user verification**, so v1.1.0 remains the stable release.

SHA-256 (`DeskHiderPlus.exe`, 1,241,600 bytes):

```text
1dcec7349fc2337bfbd1d4e96e0177e0b3367b743bc968dc24ad62ac9fc73478
```

#### Upgrading from v1.0.0 / v1.1.0

1. If the tray icon is hidden, run the old EXE again to show it, then choose **Exit**.
2. Replace the old `DeskHiderPlus.exe` with the new download in the same folder. Keeping the path preserves the existing startup entry.
3. Launch the new EXE and accept **Repair it now?**, then approve the administrator prompt. Alternatively choose **Tray → Hide / repair shortcut arrows**.
4. Explorer restarts once; open File Explorer windows may close. The original arrow setting remains available through **Restore shortcut arrows**.
5. Restart Windows and check the desktop immediately after sign-in, including small/medium/large icon sizes. Simply downloading the EXE does not replace the existing system overlay; step 3 is required.

### v1.1.0

The stable v1.1.0 release adds the optional tray icon, switches the user interface to English, and includes reliable hidden-tray recovery on Windows 10 by signaling the already-running instance directly. It uses the older 32bpp shortcut overlay.

[Download v1.1.0](https://github.com/Tobiasyzh/DeskHiderPlus/releases/tag/v1.1.0)

Direct asset: `DeskHiderPlus.exe` (1,243,136 bytes)

SHA-256:

```text
d73183c51264c117917feec1dc334c0a629177712d2923cc5a393fed6723e70d
```

This stable binary is byte-for-byte identical to the user-tested v1.1.0 beta 2 build.

### v1.0.0

The original tested Windows 10 release remains available here:

[Download v1.0.0](https://github.com/Tobiasyzh/DeskHiderPlus/releases/tag/v1.0.0)

SHA-256:

```text
2d914c038f6f28905dcce5a8b82783f8a9bd51137088a9738f1fcacc824fbf5d
```

## Build

1. Download or clone this repository.
2. Double-click `Build.cmd`.
3. The script downloads the official AutoHotkey **v1.1.37.02** portable package, verifies its SHA-256, and compiles `DeskHiderPlus.ahk`.
4. The resulting `DeskHiderPlus.exe` is created in the repository folder and launched automatically.

AutoHotkey does not need to be installed system-wide.

Keep the `lib` folder alongside `DeskHiderPlus.ahk` when building or running the source. The compiled EXE remains standalone.

The build script verifies the AutoHotkey archive against:

```text
6F3663F7CDD25063C8C8728F5D9B07813CED8780522FD1F124BA539E2854215F
```

## Usage

Run `DeskHiderPlus.exe`.

- **Desktop:** double-click an empty area to hide/show desktop icons.
- **Tray → Hide / repair shortcut arrows:** hide shortcut arrows or recreate the current transparent overlay. Windows will request administrator approval and Explorer will restart.
- **Tray → Restore shortcut arrows:** restore the shortcut-arrow setting that existed before DeskHider Plus changed it.
- **Tray → Run at startup:** enable/disable startup with Windows.
- **Tray → Show tray icon:** uncheck this to hide the tray icon while keeping DeskHider Plus running.
- **Tray → Exit:** exit the resident utility.

### Hidden tray icon recovery

When `Show tray icon` is unchecked, DeskHider Plus keeps running normally and desktop double-click still works. To restore the tray icon, simply run `DeskHiderPlus.exe` again. The already-running instance receives the request, shows its tray icon again, and keeps a single resident process.

When shortcut arrows are hidden, the transparent overlay file is stored at:

```text
%ProgramData%\DeskHiderPlus\blank_v4_mask.ico
```

Do not delete that file while the shortcut-arrow setting is active. Use the tray restore command first if you want to return to the Windows default.

The setting is applied before Explorer restarts and persists across logons; the resident app does not generate the overlay during startup. Old `blank.ico` / `blank_v3.ico` files may remain until Restore, because a running shell can still hold references to them.

## Verification

With the official AutoHotkey v1.1.37.02 portable package available, run the following from the repository in PowerShell (replace the interpreter path):

```powershell
$output = Join-Path $PWD '项目辅助文件\overlay-tests'
New-Item -ItemType Directory -Force $output | Out-Null
& 'path\to\AutoHotkeyU64.exe' /ErrorStdOut .\tests\ShortcutArrows.test.ahk $output
python .\tests\verify_overlay.py (Join-Path $output 'blank_v4_mask.ico')
.\DeskHiderPlus.exe /validate
```

Repeat the AHK suite with `AutoHotkeyU32.exe` to exercise the 32-bit registry-view path. Tests use temporary `HKCU\Software\DeskHiderPlus_Test_<PID>` keys and files under the chosen output directory, then clean up. They do not change the real Explorer settings or restart the desktop. The Python test verifies every ICO frame and checks that drawing, overlay composition, scaling, and image-list serialization preserve the underlying icon's RGB pixels at 16 sizes.

## Resource usage

DeskHider Plus is designed to stay small:

- No background polling for shortcut-arrow removal.
- No Windows service.
- No scheduled task.
- No second permanent process.
- Hiding the tray icon does not create another process or polling loop.
- The elevated helper process exists only during an arrow hide/restore operation and exits immediately afterward.

## Compatibility

The current version is intended for **Windows 10** and uses **AutoHotkey v1** syntax.

The shortcut-arrow modification relies on Windows Explorer's `Shell Icons\\29` behavior. Windows updates may change shell behavior, so the program includes a restore path and avoids overwriting a `29` value that another program changed after DeskHider Plus.

## Credits and licensing

DeskHider Plus is derived from **DeskHider** by **Ian Div**, which is distributed under the MIT License. The upstream copyright and MIT license text are retained in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

This repository currently uses the repository-level license in [`LICENSE`](LICENSE) for the project's own modifications, while portions derived from DeskHider remain subject to the upstream MIT notice.
