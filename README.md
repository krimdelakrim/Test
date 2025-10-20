# .NET Framework Repair & Upgrade Utility

This repository provides a PowerShell script that checks the installed .NET Framework 4.x version, optionally repairs the installation, and installs or reinstalls .NET Framework 4.8. Use it when Windows cannot enable Developer Mode or install applications that require the latest 4.x runtime (e.g., Office 365) because of a damaged or missing .NET Framework.

## Script overview

`scripts/fix-dotnet.ps1` performs the following:

- Detects the current .NET Framework 4.x Full installation status from the registry.
- Maps release keys to friendly version numbers so you can confirm the installed build.
- Downloads the official .NET Framework 4.8 installer from Microsoft if an upgrade or reinstall is required.
- Installs or reinstalls .NET Framework 4.8 silently (optional) to repair corrupted setups.
- Runs optional repair steps (DISM, SFC, and re-registering the NetFx4 feature) to address OS corruption that blocks installation.

## Requirements

- Windows 10 or later with administrative privileges.
- Internet connectivity for the web installer (unless you provide the offline installer yourself).
- PowerShell 5.1 or newer.

## Usage

1. Open PowerShell **as Administrator**.
2. Allow script execution for the current session if needed:

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

3. Run the script (update the path if you saved the repository elsewhere):

   ```powershell
   cd <path-to-repo>
   .\scripts\fix-dotnet.ps1
   ```

### Useful parameters

- `-ForceReinstall` &mdash; reinstall .NET Framework 4.8 even if it is already present. Helpful when registry entries exist but the runtime is damaged.
- `-SilentInstall` &mdash; run the installer in quiet mode without UI prompts.
- `-DownloadDirectory <path>` &mdash; choose where the installer is downloaded. Defaults to `%TEMP%`.
- `-RepairSystemFiles` &mdash; after installation, run `sfc /scannow` and `DISM /RestoreHealth` followed by enabling the NetFx4 optional feature to repair deeper OS corruption.

### Example: force reinstall and run repairs

```powershell
.\scripts\fix-dotnet.ps1 -ForceReinstall -RepairSystemFiles -SilentInstall
```

The script logs each step and prompts Windows to run required tools with elevated permissions. After it finishes, restart the computer to finalize any pending changes before enabling Developer Mode or reinstalling Office 365.
