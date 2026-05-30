#requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ============================================================
# CONFIG
# ============================================================

$Models = @(
    @{
        Name = "HP EliteBook 840 G10"

        # HP Platform ID, NOT the marketing model name.
        # Obtain/verify using HP CMSL or on a live HP device with:
        #   Get-HPDeviceProductID
        Platform = "8B41"

        OS               = "Win11"
        OSVer            = "23H2"
        IncludeInBootWim = $true
        IncludeInOsWim   = $true
    },
    @{
        Name = "HP EliteBook 860 G10"

        # HP Platform ID, NOT the marketing model name.
        Platform = "8B42"

        OS               = "Win11"
        OSVer            = "23H2"
        IncludeInBootWim = $true
        IncludeInOsWim   = $true
    }
)

$WorkingRoot     = "D:\HP-Win11-USB-Build"
$IsoPath         = "D:\ISO\Windows11_Enterprise.iso"
$IsoExtractPath  = "$WorkingRoot\ISO"
$DriverRoot      = "$WorkingRoot\HPDrivers"
$BootDriverStage = "$WorkingRoot\Drivers-BootWim"
$OsDriverStage   = "$WorkingRoot\Drivers-OsWim"
$MountPath       = "$WorkingRoot\Mount"
$OutputIso       = "$WorkingRoot\Win11Ent-HP-Drivers.iso"

# boot.wim index 1 = WinPE
# boot.wim index 2 = Windows Setup
$BootWimIndexes = @(1, 2)

# Recommended: Enterprise only.
$InjectAllInstallWimIndexes = $false
$TargetInstallEditionName   = "Windows 11 Enterprise"

# Windows Update servicing for install.wim only.
$PatchInstallWim = $true

# Latest CU download from Microsoft Update Catalog.
$DownloadLatestCumulativeUpdate = $true
$LatestCuSearchQuery = "2026-05 cumulative update for Windows 11 Version 23H2 for x64-based Systems"

# Optional specific KBs.
$DownloadSpecificKBs = $false
$SpecificKBs = @(
    # "KB5063878"
)

$WindowsUpdateCache = "$WorkingRoot\WindowsUpdates"

$BootDriverKeywords = @(
    "network",
    "ethernet",
    "lan",
    "wlan",
    "wifi",
    "wireless",
    "storage",
    "rst",
    "raid",
    "vmd",
    "nvme",
    "sata",
    "scsi"
)

# ============================================================
# FUNCTIONS
# ============================================================

function Get-Oscdimg {
    $paths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Install-WindowsAdkDeploymentTools {
    $downloadPath = "$env:TEMP\adksetup.exe"
    $adkUrl = "https://go.microsoft.com/fwlink/?linkid=2196127"

    Write-Host "Downloading Windows ADK installer..."
    Invoke-WebRequest -Uri $adkUrl -OutFile $downloadPath

    Write-Host "Installing Windows ADK Deployment Tools silently..."

    $arguments = @(
        "/quiet",
        "/norestart",
        "/features",
        "OptionId.DeploymentTools"
    )

    $process = Start-Process `
        -FilePath $downloadPath `
        -ArgumentList $arguments `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Windows ADK install failed. Exit code: $($process.ExitCode)"
    }
}

function Install-HpCmsl {
    if (-not (Get-Module -ListAvailable -Name HPCMSL)) {
        Write-Host "Installing HP Client Management Script Library..."

        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12

        Install-PackageProvider `
            -Name NuGet `
            -MinimumVersion 2.8.5.201 `
            -Force

        Set-PSRepository `
            -Name PSGallery `
            -InstallationPolicy Trusted

        Install-Module `
            -Name HPCMSL `
            -Scope AllUsers `
            -Force
    }

    Import-Module HPCMSL -Force
}

function Install-UpdateDownloadTools {
    Write-Host "Preparing Microsoft Update Catalog tooling..."

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12

    Install-PackageProvider `
        -Name NuGet `
        -MinimumVersion 2.8.5.201 `
        -Force

    Set-PSRepository `
        -Name PSGallery `
        -InstallationPolicy Trusted

    if (-not (Get-Module -ListAvailable -Name MSCatalogLTS)) {
        Install-Module MSCatalogLTS -Scope AllUsers -Force
    }

    Import-Module MSCatalogLTS -Force
}

function Download-WindowsUpdatePackages {
    param(
        [string]$CachePath,
        [bool]$LatestCU,
        [string]$LatestCuSearchQuery,
        [bool]$SpecificKBsEnabled,
        [string[]]$SpecificKBs
    )

    New-Item -ItemType Directory -Force -Path $CachePath | Out-Null

    Install-UpdateDownloadTools

    if ($LatestCU) {
        Write-Host "Searching Microsoft Update Catalog for latest CU..." -ForegroundColor Cyan

        $updates = Get-MSCatalogUpdate -Search $LatestCuSearchQuery

        $latest = $updates |
            Where-Object {
                $_.Title -match "Cumulative Update" -and
                $_.Title -match "Windows 11" -and
                $_.Title -match "x64" -and
                $_.Title -notmatch "Dynamic|Preview|ARM64|Server"
            } |
            Sort-Object LastUpdated -Descending |
            Select-Object -First 1

        if (-not $latest) {
            throw "Could not find latest CU using query: $LatestCuSearchQuery"
        }

        Write-Host "Downloading latest CU: $($latest.Title)" -ForegroundColor Cyan

        Save-MSCatalogUpdate `
            -Update $latest `
            -Destination $CachePath
    }

    if ($SpecificKBsEnabled) {
        foreach ($kb in $SpecificKBs) {
            Write-Host "Searching Microsoft Update Catalog for $kb..." -ForegroundColor Cyan

            $update = Get-MSCatalogUpdate -Search $kb |
                Where-Object {
                    $_.Title -match "Windows 11" -and
                    $_.Title -match "x64" -and
                    $_.Title -notmatch "ARM64|Server"
                } |
                Sort-Object LastUpdated -Descending |
                Select-Object -First 1

            if (-not $update) {
                Write-Warning "Could not find $kb"
                continue
            }

            Write-Host "Downloading $($update.Title)" -ForegroundColor Cyan

            Save-MSCatalogUpdate `
                -Update $update `
                -Destination $CachePath
        }
    }
}

function Add-WindowsUpdatesToImage {
    param(
        [string]$MountPath,
        [string]$UpdatePath
    )

    if (-not (Test-Path $UpdatePath)) {
        throw "Windows update package path not found: $UpdatePath"
    }

    $updates = Get-ChildItem $UpdatePath -Recurse -Include *.msu, *.cab

    if (-not $updates) {
        Write-Warning "No .msu or .cab update packages found in $UpdatePath"
        return
    }

    foreach ($update in $updates) {
        Write-Host "Adding update package: $($update.Name)" -ForegroundColor Yellow
        dism /Image:$MountPath /Add-Package /PackagePath:$($update.FullName)
    }

    Write-Host "Running component cleanup..." -ForegroundColor Yellow
    dism /Image:$MountPath /Cleanup-Image /StartComponentCleanup
}

function Copy-DriverFolder {
    param(
        [string]$InfPath,
        [string]$SourceRoot,
        [string]$DestinationRoot
    )

    $sourceDir = Split-Path $InfPath -Parent
    $relative  = $sourceDir.Substring($SourceRoot.Length).TrimStart('\')
    $dest      = Join-Path $DestinationRoot $relative

    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item "$sourceDir\*" $dest -Recurse -Force
}

function Test-IsBootDriver {
    param(
        [string]$InfPath,
        [string[]]$Keywords
    )

    $pathLower = $InfPath.ToLowerInvariant()
    $content = Get-Content $InfPath -Raw -ErrorAction SilentlyContinue

    foreach ($keyword in $Keywords) {
        if ($pathLower -like "*$keyword*" -or $content -match $keyword) {
            return $true
        }
    }

    return $false
}

function Mount-And-InjectDrivers {
    param(
        [string]$WimFile,
        [int[]]$Indexes,
        [string]$DriverPath,
        [string]$MountPath,
        [string]$Label,
        [bool]$PatchImage = $false,
        [string]$UpdatePackagePath = $null
    )

    foreach ($index in $Indexes) {
        Write-Host "Mounting $Label index $index..." -ForegroundColor Cyan

        dism /Mount-Wim /WimFile:$WimFile /Index:$index /MountDir:$MountPath

        try {
            if (
                (Test-Path $DriverPath) -and
                ((Get-ChildItem $DriverPath -Recurse -Filter *.inf -ErrorAction SilentlyContinue).Count -gt 0)
            ) {
                Write-Host "Injecting drivers into $Label index $index..."
                dism /Image:$MountPath /Add-Driver /Driver:$DriverPath /Recurse
            }

            if ($PatchImage) {
                Write-Host "Applying Windows updates to $Label index $index..." -ForegroundColor Cyan

                Add-WindowsUpdatesToImage `
                    -MountPath $MountPath `
                    -UpdatePath $UpdatePackagePath
            }

            Write-Host "Committing $Label index $index..."
            dism /Unmount-Wim /MountDir:$MountPath /Commit
        }
        catch {
            Write-Warning "Error occurred. Discarding mounted image..."
            dism /Unmount-Wim /MountDir:$MountPath /Discard
            throw
        }
    }
}

function Get-InstallWimIndexes {
    param(
        [string]$InstallWim,
        [bool]$InjectAllIndexes,
        [string]$TargetEditionName
    )

    $dismInfo = dism /Get-WimInfo /WimFile:$InstallWim

    if ($InjectAllIndexes) {
        return @(
            $dismInfo |
                Select-String "Index :" |
                ForEach-Object {
                    [int]($_.Line.Split(":")[1].Trim())
                }
        )
    }

    $matchedIndex = $null
    $currentIndex = $null

    foreach ($line in $dismInfo) {
        if ($line -match "Index : (\d+)") {
            $currentIndex = [int]$matches[1]
        }

        if ($line -match "Name : $TargetEditionName") {
            $matchedIndex = $currentIndex
            break
        }
    }

    if (-not $matchedIndex) {
        throw "Could not find install.wim edition: $TargetEditionName"
    }

    return @($matchedIndex)
}

# ============================================================
# PREP
# ============================================================

New-Item -ItemType Directory -Force -Path `
    $WorkingRoot,
    $IsoExtractPath,
    $DriverRoot,
    $BootDriverStage,
    $OsDriverStage,
    $MountPath,
    $WindowsUpdateCache | Out-Null

Install-HpCmsl

# ============================================================
# DOWNLOAD, EXTRACT, AND STAGE HP DRIVERS
# ============================================================

foreach ($Model in $Models) {
    $modelNameSafe = ($Model.Name -replace '[^\w\- ]', '') -replace '\s+', '_'

    $modelDownloadPath = Join-Path $DriverRoot $modelNameSafe
    $modelExtractPath  = Join-Path $modelDownloadPath "Extracted"

    New-Item -ItemType Directory -Force -Path $modelDownloadPath, $modelExtractPath | Out-Null

    Write-Host "Processing $($Model.Name) / Platform $($Model.Platform)" -ForegroundColor Cyan

    $softpaqs = Get-SoftpaqList `
        -Platform $Model.Platform `
        -OS $Model.OS `
        -OSVer $Model.OSVer `
        -Category DriverPack

    if (-not $softpaqs) {
        Write-Warning "No driver pack found for $($Model.Name)"
        continue
    }

    foreach ($sp in $softpaqs) {
        Write-Host "Downloading $($sp.Id) - $($sp.Name)"

        Save-Softpaq `
            -Number $sp.Id `
            -SaveAs $modelDownloadPath `
            -Quiet

        $softpaqExe = Get-ChildItem $modelDownloadPath -Filter "$($sp.Id)*.exe" -File |
            Select-Object -First 1

        if (-not $softpaqExe) {
            Write-Warning "Could not locate SoftPaq EXE for $($sp.Id)"
            continue
        }

        $spExtractPath = Join-Path $modelExtractPath $sp.Id
        New-Item -ItemType Directory -Force -Path $spExtractPath | Out-Null

        Write-Host "Extracting $($softpaqExe.Name)"

        $arguments = "/s /e /f `"$spExtractPath`""

        $process = Start-Process `
            -FilePath $softpaqExe.FullName `
            -ArgumentList $arguments `
            -Wait `
            -PassThru

        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 1168) {
            Write-Warning "Extraction returned exit code $($process.ExitCode)"
        }
    }

    if ($Model.IncludeInOsWim) {
        $osModelStage = Join-Path $OsDriverStage $modelNameSafe
        New-Item -ItemType Directory -Force -Path $osModelStage | Out-Null

        Write-Host "Staging full OS drivers for $($Model.Name)" -ForegroundColor Yellow

        Get-ChildItem $modelExtractPath -Recurse -Filter *.inf | ForEach-Object {
            Copy-DriverFolder `
                -InfPath $_.FullName `
                -SourceRoot $modelExtractPath `
                -DestinationRoot $osModelStage
        }
    }

    if ($Model.IncludeInBootWim) {
        $bootModelStage = Join-Path $BootDriverStage $modelNameSafe
        New-Item -ItemType Directory -Force -Path $bootModelStage | Out-Null

        Write-Host "Staging boot drivers for $($Model.Name)" -ForegroundColor Yellow

        Get-ChildItem $modelExtractPath -Recurse -Filter *.inf | ForEach-Object {
            if (Test-IsBootDriver -InfPath $_.FullName -Keywords $BootDriverKeywords) {
                Copy-DriverFolder `
                    -InfPath $_.FullName `
                    -SourceRoot $modelExtractPath `
                    -DestinationRoot $bootModelStage
            }
        }
    }
}

# ============================================================
# DOWNLOAD WINDOWS UPDATES
# ============================================================

if ($PatchInstallWim) {
    Download-WindowsUpdatePackages `
        -CachePath $WindowsUpdateCache `
        -LatestCU $DownloadLatestCumulativeUpdate `
        -LatestCuSearchQuery $LatestCuSearchQuery `
        -SpecificKBsEnabled $DownloadSpecificKBs `
        -SpecificKBs $SpecificKBs
}

# ============================================================
# EXTRACT WINDOWS ISO
# ============================================================

Write-Host "Mounting Windows ISO..." -ForegroundColor Cyan

$diskImage = Mount-DiskImage -ImagePath $IsoPath -PassThru
$volume = $diskImage | Get-Volume
$isoDrive = "$($volume.DriveLetter):"

Write-Host "Copying ISO contents..."
robocopy "$isoDrive\" $IsoExtractPath /E | Out-Null

Dismount-DiskImage -ImagePath $IsoPath

$BootWim    = Join-Path $IsoExtractPath "sources\boot.wim"
$InstallWim = Join-Path $IsoExtractPath "sources\install.wim"
$InstallEsd = Join-Path $IsoExtractPath "sources\install.esd"

if (-not (Test-Path $BootWim)) {
    throw "boot.wim not found at $BootWim"
}

if (-not (Test-Path $InstallWim)) {
    if (Test-Path $InstallEsd) {
        Write-Host "Converting install.esd to install.wim..." -ForegroundColor Cyan

        dism `
            /Export-Image `
            /SourceImageFile:$InstallEsd `
            /SourceIndex:1 `
            /DestinationImageFile:$InstallWim `
            /Compress:max `
            /CheckIntegrity

        Remove-Item $InstallEsd -Force
    }
    else {
        throw "Neither install.wim nor install.esd found."
    }
}

$InstallWimIndexes = Get-InstallWimIndexes `
    -InstallWim $InstallWim `
    -InjectAllIndexes $InjectAllInstallWimIndexes `
    -TargetEditionName $TargetInstallEditionName

Write-Host "Install.wim target indexes: $($InstallWimIndexes -join ', ')" -ForegroundColor Green

# ============================================================
# INJECT BOOT.WIM DRIVERS
# ============================================================

if ((Get-ChildItem $BootDriverStage -Recurse -Filter *.inf -ErrorAction SilentlyContinue).Count -gt 0) {
    Mount-And-InjectDrivers `
        -WimFile $BootWim `
        -Indexes $BootWimIndexes `
        -DriverPath $BootDriverStage `
        -MountPath $MountPath `
        -Label "boot.wim"
}
else {
    Write-Warning "No boot drivers found to inject."
}

# ============================================================
# INJECT INSTALL.WIM DRIVERS + WINDOWS UPDATES
# ============================================================

if (
    ((Get-ChildItem $OsDriverStage -Recurse -Filter *.inf -ErrorAction SilentlyContinue).Count -gt 0) -or
    $PatchInstallWim
) {
    Mount-And-InjectDrivers `
        -WimFile $InstallWim `
        -Indexes $InstallWimIndexes `
        -DriverPath $OsDriverStage `
        -MountPath $MountPath `
        -Label "install.wim" `
        -PatchImage $PatchInstallWim `
        -UpdatePackagePath $WindowsUpdateCache
}
else {
    Write-Warning "No OS drivers or Windows updates selected for install.wim."
}

# ============================================================
# REBUILD ISO
# ============================================================

$oscdimg = Get-Oscdimg

if (-not $oscdimg) {
    Write-Warning "oscdimg.exe not found. Installing Windows ADK Deployment Tools..."
    Install-WindowsAdkDeploymentTools
    $oscdimg = Get-Oscdimg
}

if (-not $oscdimg) {
    throw "oscdimg.exe still not found after ADK installation."
}

Write-Host "Using oscdimg: $oscdimg" -ForegroundColor Cyan

$bootData = "2#p0,e,b$IsoExtractPath\boot\etfsboot.com#pEF,e,b$IsoExtractPath\efi\microsoft\boot\efisys.bin"

& $oscdimg `
    -m `
    -o `
    -u2 `
    -udfver102 `
    -bootdata:$bootData `
    $IsoExtractPath `
    $OutputIso

Write-Host "Complete: $OutputIso" -ForegroundColor Green

# ============================================================
# OPTIONAL: CREATE BOOTABLE USB
# ============================================================
# WARNING:
# This section is commented out intentionally.
# It will wipe the selected USB disk if enabled.
#
# FAT32 has a 4 GB file size limit.
# If install.wim is larger than 4 GB, split it before copying:
#
# dism /Split-Image `
#   /ImageFile:$InstallWim `
#   /SWMFile:"$IsoExtractPath\sources\install.swm" `
#   /FileSize:3800
#
# Remove-Item $InstallWim -Force
#
# $CreateBootableUsb = $true
# $UsbDiskNumber = 2
#
# if ($CreateBootableUsb) {
#
#     Write-Host "Preparing USB disk $UsbDiskNumber..." -ForegroundColor Yellow
#
#     $diskpartScript = @"
# select disk $UsbDiskNumber
# clean
# convert gpt
# create partition primary
# format fs=fat32 quick label=WIN11HP
# assign letter=U
# exit
# "@
#
#     $diskpartPath = "$env:TEMP\Create-Win11USB.txt"
#     $diskpartScript | Out-File $diskpartPath -Encoding ASCII
#
#     diskpart /s $diskpartPath
#
#     Write-Host "Copying Windows media to USB..."
#
#     robocopy `
#         $IsoExtractPath `
#         "U:\" `
#         /E
#
#     Write-Host "Bootable USB created successfully." -ForegroundColor Green
# }
