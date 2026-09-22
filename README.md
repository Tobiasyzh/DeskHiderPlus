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
- Uses a classic transparent BMP/DIB ICO to avoid the black-square overlay issue seen on some Windows 10 builds.
- Requests administrator privileges only for hide/restore shortcut-arrow actions.
- Optional startup toggle from the tray menu.
- No installer required.

## Build

1. Download or clone this repository.
2. Double-click `Build.cmd`.
3. The script downloads the official AutoHotkey **v1.1.37.02** portable package, verifies its SHA-256, and compiles `DeskHiderPlus.ahk`.
4. The resulting `DeskHiderPlus.exe` is created in the repository folder and launched automatically.

AutoHotkey does not need to be installed system-wide.

The build script verifies the AutoHotkey archive against:

```text
6F3663F7CDD25063C8C8728F5D9B07813CED8780522FD1F124BA539E2854215F
```

## Usage

Run `DeskHiderPlus.exe`.

- **Desktop:** double-click an empty area to hide/show desktop icons.
- **Tray → 隐藏快捷方式箭头:** hide shortcut arrows. Windows will request administrator approval and Explorer will restart.
- **Tray → 恢复快捷方式箭头:** restore the shortcut-arrow setting that existed before DeskHider Plus changed it.
- **Tray → 开机启动:** enable/disable startup with Windows.
- **Tray → 退出:** exit the resident utility.

When shortcut arrows are hidden, the transparent overlay file is stored at:

```text
C:\ProgramData\DeskHiderPlus\blank_v3.ico
```

Do not delete that file while the shortcut-arrow setting is active. Use the tray restore command first if you want to return to the Windows default.

## Resource usage

DeskHider Plus is designed to stay small:

- No background polling for shortcut-arrow removal.
- No Windows service.
- No scheduled task.
- No second permanent process.
- The elevated helper process exists only during an arrow hide/restore operation and exits immediately afterward.

## Compatibility

The current version is intended for **Windows 10** and uses **AutoHotkey v1** syntax.

The shortcut-arrow modification relies on Windows Explorer's `Shell Icons\\29` behavior. Windows updates may change shell behavior, so the program includes a restore path and avoids overwriting a `29` value that another program changed after DeskHider Plus.

## 中文说明

DeskHider Plus 是一个针对 Windows 10 的轻量桌面工具，主要提供两个功能：

1. 双击桌面空白处隐藏/显示桌面图标。
2. 在托盘菜单中隐藏/恢复快捷方式左下角的小箭头。

快捷方式箭头功能不是后台轮询实现的，只在你点击对应菜单时修改一次系统设置，因此不会额外增加持续的 CPU 占用。隐藏/恢复箭头时需要一次管理员权限，并会重启 Windows 资源管理器以立即生效。

直接双击 `Build.cmd` 即可编译，不需要提前安装 AutoHotkey。

## Credits and licensing

DeskHider Plus is derived from **DeskHider** by **Ian Div**, which is distributed under the MIT License. The upstream copyright and MIT license text are retained in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

This repository currently uses the repository-level license in [`LICENSE`](LICENSE) for the project's own modifications, while portions derived from DeskHider remain subject to the upstream MIT notice.
