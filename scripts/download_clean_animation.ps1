param(
    [Parameter(Mandatory = $true)]
    [string]$CharacterId,

    [string]$CharacterName = ""
)

$ErrorActionPreference = "Stop"

$TargetRoot = "assets\clean_animations"
$RawRoot = "assets\pixellab_characters"
$ApiBaseUrl = "https://api.pixellab.ai/characters"

function Get-SafeFolderName {
    param([string]$Name)

    $cleanName = $Name.Trim()
    if ($cleanName.Length -gt 80 -and $cleanName -match "known as the ([^.]+)") {
        $cleanName = $Matches[1].Trim()
    }
    if ($cleanName.Length -gt 80) {
        $cleanName = $cleanName.Substring(0, 80).Trim()
    }

    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $cleanName = $cleanName.Replace($char, "_")
    }
    return $cleanName
}

function Get-AnimationDirection {
    param($Animation)

    $directions = @($Animation.Value.PSObject.Properties.Name)
    foreach ($preferred in @("east", "south-east", "south")) {
        if ($directions -contains $preferred) {
            return $preferred
        }
    }
    if ($directions.Count -gt 0) {
        return $directions[0]
    }
    return ""
}

function Get-AnimationSourceFolder {
    param(
        $Animation,
        [string]$Direction
    )

    $frames = @($Animation.Value.$Direction)
    if ($frames.Count -eq 0) {
        throw "Animation $($Animation.Name) does not contain frames for $Direction."
    }
    return Split-Path -Path ([string]$frames[0]) -Parent
}

function Get-AnimationFramePaths {
    param(
        $Animation,
        [string]$Direction
    )

    $frames = @($Animation.Value.$Direction) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    if ($frames.Count -eq 0) {
        throw "Animation $($Animation.Name) does not contain frames for $Direction."
    }
    return $frames
}

function Sync-StateExportFolders {
    param(
        [string]$RawCharacterFolder,
        $Export
    )

    $stateFolder = [string]$Export.folder
    if ([string]::IsNullOrWhiteSpace($stateFolder)) {
        return
    }

    $stateRoot = Join-Path $RawCharacterFolder $stateFolder
    foreach ($folderName in @("animations", "rotations")) {
        $source = Join-Path $stateRoot $folderName
        if (-not (Test-Path -LiteralPath $source)) {
            continue
        }
        $destination = Join-Path $RawCharacterFolder $folderName
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }
        Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
    }
}

function Select-AnimationName {
    param(
        [array]$Animations,
        [string]$Kind,
        [hashtable]$Used
    )

    $patterns = @{
        Idle = @("idle", "breath", "stance", "animating")
        Walk = @("walk", "run", "dash", "animation")
        Fight = @("fight", "attack", "punch", "kick", "uppercut", "roundhouse", "cross", "hurricane", "high", "slash", "strike")
    }

    foreach ($pattern in $patterns[$Kind]) {
        foreach ($animation in $Animations) {
            if ($Used.ContainsKey($animation.Name)) {
                continue
            }
            $directions = @($animation.Value.PSObject.Properties.Name)
            if ($animation.Name.ToLowerInvariant() -match $pattern -and $directions -contains "east") {
                $Used[$animation.Name] = $true
                return $animation.Name
            }
        }
    }

    foreach ($pattern in $patterns[$Kind]) {
        foreach ($animation in $Animations) {
            if ($Used.ContainsKey($animation.Name)) {
                continue
            }
            if ($animation.Name.ToLowerInvariant() -match $pattern) {
                $Used[$animation.Name] = $true
                return $animation.Name
            }
        }
    }

    foreach ($animation in $Animations) {
        if (-not $Used.ContainsKey($animation.Name)) {
            $Used[$animation.Name] = $true
            return $animation.Name
        }
    }

    throw "Could not find an animation for $Kind."
}

function Copy-AnimationFrames {
    param(
        [string]$RawCharacterFolder,
        [string]$TargetCharacterFolder,
        [string]$TargetAction,
        [array]$SourceRelativeFrames
    )

    $destination = Join-Path $TargetCharacterFolder $TargetAction
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null

    foreach ($relativeFrame in $SourceRelativeFrames) {
        $source = Join-Path $RawCharacterFolder ([string]$relativeFrame)
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Missing source animation frame: $source"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $destination (Split-Path -Path ([string]$relativeFrame) -Leaf)) -Force
    }
}

if ([string]::IsNullOrWhiteSpace($env:PIXELLAB_API_KEY)) {
    throw "PIXELLAB_API_KEY is not set."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$zipPath = Join-Path $repoRoot "pixellab_$CharacterId.zip"
$rawCharacterFolder = Join-Path $repoRoot (Join-Path $RawRoot $CharacterId)

if (Test-Path -LiteralPath $rawCharacterFolder) {
    Remove-Item -LiteralPath $rawCharacterFolder -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $rawCharacterFolder | Out-Null
curl.exe -s -S -f -L -o $zipPath -H "Authorization: Bearer $env:PIXELLAB_API_KEY" "$ApiBaseUrl/$CharacterId/zip"
Expand-Archive -LiteralPath $zipPath -DestinationPath $rawCharacterFolder -Force
Remove-Item -LiteralPath $zipPath

$metadataPath = Join-Path $rawCharacterFolder "metadata.json"
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$export = if ($metadata.PSObject.Properties.Name -contains "states" -and @($metadata.states).Count -gt 0) {
    $metadata.states[0]
} else {
    $metadata
}
Sync-StateExportFolders -RawCharacterFolder $rawCharacterFolder -Export $export
$folderName = if ([string]::IsNullOrWhiteSpace($CharacterName)) {
    Get-SafeFolderName -Name ([string]$export.character.name)
} else {
    Get-SafeFolderName -Name $CharacterName
}

$targetCharacterFolder = Join-Path $repoRoot (Join-Path $TargetRoot $folderName)
New-Item -ItemType Directory -Force -Path $targetCharacterFolder | Out-Null

$animations = @($export.frames.animations.PSObject.Properties) | Where-Object { $_ -ne $null -and -not [string]::IsNullOrWhiteSpace($_.Name) }
$used = @{}
$mapping = @{
    Idle = (Select-AnimationName -Animations $animations -Kind "Idle" -Used $used)
    Walk = (Select-AnimationName -Animations $animations -Kind "Walk" -Used $used)
    Fight = (Select-AnimationName -Animations $animations -Kind "Fight" -Used $used)
}

foreach ($targetAction in @("Idle", "Walk", "Fight")) {
    $animationName = $mapping[$targetAction]
    $animation = $animations | Where-Object { $_.Name -eq $animationName } | Select-Object -First 1
    $direction = Get-AnimationDirection -Animation $animation
    if ([string]::IsNullOrWhiteSpace($direction)) {
        throw "Animation $animationName does not contain any direction folders."
    }
    $sourceRelativeFrames = @(Get-AnimationFramePaths -Animation $animation -Direction $direction)
    Copy-AnimationFrames -RawCharacterFolder $rawCharacterFolder -TargetCharacterFolder $targetCharacterFolder -TargetAction $targetAction -SourceRelativeFrames $sourceRelativeFrames
}

Write-Host "Downloaded $CharacterId as $folderName"
foreach ($targetAction in @("Idle", "Walk", "Fight")) {
    $count = @(Get-ChildItem -Path (Join-Path $targetCharacterFolder $targetAction) -Filter "*.png" -File).Count
    Write-Host "${targetAction}: $count frames"
}
