# DeskHider Plus v2.0

Fixes shortcut icons whose lower-left corners were cut out or replaced by incorrect shield or folder overlays after restarting Windows. The affected Windows 10 user has confirmed the test2 implementation works; v2.0 preserves that implementation and updates the release version identifiers.

Download **DeskHiderPlus.exe**. It is the complete standalone application, including desktop double-click, shortcut-arrow controls, startup settings, tray preferences and recovery. No earlier version, AutoHotkey installation or extra resource file is required.

Changes:

- Uses an ARGB overlay with a minimal nonzero-alpha anchor, matching masks and 23 sizes, including 60px for 125% desktop scaling.
- Checks destination alpha as well as RGB through restored Windows system image lists; rejects the older masks that could erase part of an icon.
- Archives and rebuilds the current user's icon caches, waits for both the desktop and taskbar, and bounds the verification helper's runtime.
- Attempts to restore the original shortcut-arrow setting if hiding fails validation, preserving settings changed by another application.
- Migrates previous DeskHider Plus overlays and detects older running instances.
- Retains desktop double-click hiding, optional startup, hidden-tray recovery and normal application UAC shields. No background polling, service or second permanent process.

Update: exit the running instance and replace its EXE at the same permanent path to preserve the startup entry. Run normally. If an overlay repair is offered, confirm it and approve the administrator request; Explorer restarts and open File Explorer windows may close. Recovery files are stored beside the EXE under `项目辅助文件\图标修复备份`.

Validation: 32/64-bit isolated migration and cache tests, RGBA extraction/composition/cache-round-trip tests at 32 sizes, standalone build validation, and user confirmation on the affected Windows 10 desktop. The functional code matches the user-verified test2 build.

SHA-256 (`DeskHiderPlus.exe`, 1,253,376 bytes):

```text
2c5171ea2d9b2425d82a92ed5e483a9d99521cc4ad6b5dd0d33cbf6db7040139
```
