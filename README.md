# HP Windows 11 Enterprise Media Builder

## Overview

The HP Windows 11 Enterprise Media Builder automates the creation of fully serviced Windows 11 installation media for supported HP platforms.

The solution leverages:

- HP Client Management Script Library (HPCMSL)
- HP SoftPaq repositories
- Microsoft Update Catalog
- DISM
- Windows ADK

The resulting media contains:

- Latest HP platform drivers
- Optional Windows cumulative updates
- Storage and network drivers in WinPE
- Full platform driver support in the operating system image
- Rebuilt bootable installation media

---

## Features

### HP Driver Automation

- Downloads latest HP driver packs directly from HP
- Supports multiple HP hardware platforms
- Uses HP Platform IDs for accurate driver targeting
- Automatically extracts SoftPaq packages
- Automatically stages drivers for servicing

### Windows Image Servicing

- Supports Windows 11 Enterprise media
- Supports install.wim and install.esd
- Automatically converts install.esd when required
- Injects drivers into boot.wim
- Injects drivers into install.wim
- Applies Windows updates to install.wim

### Windows Update Integration

- Downloads latest cumulative updates from Microsoft Update Catalog
- Optional support for specific KB packages
- Offline servicing using DISM
- Component cleanup after patching

### Media Generation

- Rebuilds bootable ISO
- Automatically installs ADK Deployment Tools if required
- Optional USB creation support

---

## Architecture

```text
Windows 11 ISO
      │
      ▼
Extract Installation Media
      │
      ▼
Download HP Driver Packs (HPCMSL)
      │
      ▼
Extract SoftPaq Packages
      │
      ├──► Boot Driver Stage
      │         │
      │         ▼
      │      boot.wim
      │
      └──► OS Driver Stage
                │
                ▼
            install.wim
                │
                ▼
      Download Latest CU
                │
                ▼
Inject Drivers and Updates (DISM)
                │
                ▼
Rebuild Bootable ISO
                │
                ▼
Optional USB Media
```

---

## Typical Workflow

```text
1. Download HP driver packs
2. Extract SoftPaq packages
3. Stage boot drivers
4. Stage OS drivers
5. Download latest Windows updates
6. Extract Windows ISO
7. Convert install.esd if required
8. Inject boot drivers
9. Inject OS drivers
10. Inject Windows updates
11. Perform component cleanup
12. Commit WIM changes
13. Rebuild bootable ISO
14. Optionally create USB media
```

---

## Platform Configuration

```powershell
$Models = @(
    @{
        Name = "HP EliteBook 840 G10"

        # HP Platform ID
        # NOT the marketing model name
        Platform = "8B41"

        IncludeInBootWim = $true
        IncludeInOsWim   = $true
    }
)
```

### Important

Platform IDs are not marketing model names.

Obtain Platform IDs using:

```powershell
Get-HPDeviceProductID
```

---

## Windows Update Servicing

Enable latest cumulative update servicing:

```powershell
$PatchInstallWim = $true
$DownloadLatestCumulativeUpdate = $true
```

Enable specific KB servicing:

```powershell
$DownloadSpecificKBs = $true

$SpecificKBs = @(
    "KB5063878"
)
```

---

## Install Image Selection

Default configuration:

```powershell
$InjectAllInstallWimIndexes = $false
$TargetInstallEditionName = "Windows 11 Enterprise"
```

To service all editions:

```powershell
$InjectAllInstallWimIndexes = $true
```

---

## Folder Structure

```text
HP-Win11-USB-Build
│
├── ISO
├── HPDrivers
├── Drivers-BootWim
├── Drivers-OsWim
├── WindowsUpdates
├── Mount
└── Win11Ent-HP-Drivers.iso
```

---

## Pipeline Integration

Suitable for:

- GitLab CI/CD
- Azure DevOps
- Jenkins
- Build Servers
- SOE Maintenance Pipelines

---

## Disclaimer

This solution modifies Windows installation media and should be tested thoroughly before production deployment.

All platform identifiers, driver packs, Windows versions, and update packages should be validated against supported hardware and organisational standards prior to release.
