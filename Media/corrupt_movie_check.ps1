param (
    [Parameter(Mandatory = $true)]
    [string]
    # The root directory containing movie folders to scan for corrupted video files.
    # WARNING: The script expect each folder to be in its own subfolder. As it will delete
    #          The full subfolder, video file and any accompanying subtitles or other files.
    $RootPath,

    [Parameter(Mandatory = $true)]
    [string]
    # The full path to the ffmpeg binary folder (e.g. D:\...\ffmpeg\bin)
    $ffmpegPath,

    [Parameter(Mandatory = $false)]
    [bool]
    # Optional: If set to $true, only scans the first 60 seconds of each video
    $quickScan = $true
)

# Relaunch as admin if needed
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "`nThis script needs to run as Admin. Relaunching with elevated privileges..."
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$videoExtensions = @("*.mp4", "*.mkv", "*.avi", "*.mov", "*.wmv")

$ffmpegExe = Join-Path $ffmpegPath 'ffmpeg.exe'
$extraffmpegArgs = ''
if ($quickScan) {
    $extraffmpegArgs = '-t 60'
}

$scanFile = Join-Path $RootPath 'corrupted_movies.txt'
$corruptedFolders = @()
$deletionFailures = @()

function IsVideoCorrupt($videoPath) {
    $cmd = "`"$ffmpegExe`" -v error $extraffmpegArgs -i `"$videoPath`" -f null -"
    $output = & cmd /c $cmd 2>&1
    if ($output -match "Invalid data" -or $output -match "error") {
        return $true
    }
    return $false
}

# Check for existing scan result
if (Test-Path $scanFile) {
    $reuse = Read-Host "`nPrevious scan results found. Use saved list instead of re-scanning? (Y/N)"
    if ($reuse -match "^[Yy]$") {
        $corruptedFolders = Get-Content $scanFile
    } else {
        Remove-Item $scanFile -Force
    }
}

# Scan folders if needed
if ($corruptedFolders.Count -eq 0) {
    $folders = Get-ChildItem -Path $RootPath -Directory | Sort-Object CreationTime
    $totalFolders = $folders.Count
    $folderIndex = 0

    foreach ($folder in $folders) {
        $folderIndex++
        $videoFiles = Get-ChildItem -Path $folder.FullName -Include $videoExtensions -File -Recurse
        $videoCount = $videoFiles.Count
        $videoIndex = 0

        foreach ($video in $videoFiles) {
            $videoIndex++
            $progressMessage = "Checking '$($video.Name)' [$videoIndex of $videoCount]"
            Write-Progress -Activity "Scanning Movies [$folderIndex of $totalFolders] [corrupted: $($corruptedFolders.Count)]" `
                           -Status $progressMessage `
                           -PercentComplete (($folderIndex / $totalFolders) * 100)

            if (IsVideoCorrupt($video.FullName)) {
                $corruptedFolders += $folder.FullName
                break
            }
        }
    }

    Write-Progress -Activity "Scan complete" -Completed

    # Save results to file
    $corruptedFolders | Set-Content $scanFile
}

# Report findings
if ($corruptedFolders.Count -gt 0) {
    Write-Host "`nCorrupted movies detected:"
    $corruptedFolders | ForEach-Object { Write-Host "- $_" }

    Write-Host "`nFound $($corruptedFolders.Count) corrupted movies."

    $confirmation = Read-Host "`nDo you want to delete movies? (Y/N)"
    if ($confirmation -match "^[Yy]$") {
        foreach ($folder in $corruptedFolders) {
            try {
                Remove-Item -Path "$folder" -Recurse -Force -ErrorAction Stop
                if (Test-Path "$folder") {
                    throw "Folder still exists after deletion."
                }
            } catch {
                $deletionFailures += @{
                    Path = $folder
                    Reason = $_.Exception.Message
                }
            }
        }

        if ($deletionFailures.Count -gt 0) {
        Write-Host "`nThe following movies could not be deleted:"
        foreach ($failure in $deletionFailures) {
            Write-Host "- $($failure.Path)"
            Write-Host "--- $($failure.Reason)" -ForegroundColor Red
        }
        } else {
            Write-Host "`nAll corrupted movies were successfully deleted."
            if (Test-Path $scanFile) {
                Remove-Item $scanFile -Force
            }
        }
    } else {
        Write-Host "`nNo movies were deleted."
    }
} else {
    Write-Host "`nNo corrupted movies found. Everything looks good."
}

Read-Host -Prompt "Press any key to continue..."
