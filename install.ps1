[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Global', 'Local')][string]$Scope,
    [string]$Path,
    [string]$ClaudeHome = (Join-Path $HOME '.claude'),
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Get-FullPath([string]$Target) {
    return [IO.Path]::GetFullPath($Target).TrimEnd('\', '/')
}

function Test-Junction([string]$Target) {
    $item = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    return ($null -ne $item) -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-JunctionTarget([string]$Link) {
    $target = [string]@((Get-Item -LiteralPath $Link -Force).Target)[0]
    if ([string]::IsNullOrWhiteSpace($target)) { return '' }
    return Get-FullPath $target
}

function Get-UniqueBackupPath([string]$Target) {
    $base = "$Target.backup-$stamp"
    $candidate = $base
    $counter = 0
    while (Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue) {
        $counter++
        $candidate = "$base-$counter"
    }
    return $candidate
}

function Read-InstallScope {
    Write-Host ''
    Write-Host 'SVD-Harness 를 어디에 설치할지 고르세요.'
    Write-Host "  1) 글로벌: $ClaudeHome (이 PC 의 모든 프로젝트에 적용)"
    Write-Host '  2) 로컬: 지정한 폴더의 .claude (그 폴더에서 연 Claude Code 에만 적용)'
    while ($true) {
        $answer = (Read-Host '번호 [1/2]').Trim()
        if ($answer -eq '1') { return 'Global' }
        if ($answer -eq '2') { return 'Local' }
        Write-Host '1 또는 2 를 입력하세요.'
    }
}

function Read-LocalPath {
    while ($true) {
        $answer = (Read-Host '설치할 폴더 경로 (그 폴더의 .claude 에 설치됨)').Trim().Trim('"')
        if ($answer -and (Test-Path -LiteralPath $answer -PathType Container)) { return $answer }
        Write-Host "폴더가 없습니다: $answer"
    }
}

function Get-HarnessLinks([string]$TargetRoot) {
    $links = New-Object 'Collections.Generic.List[object]'
    $links.Add([pscustomobject]@{ Link = Join-Path $TargetRoot 'rules\svd-harness'; Target = Join-Path $repoRoot 'rules' })
    foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'skills') -Directory) {
        $links.Add([pscustomobject]@{ Link = Join-Path $TargetRoot "skills\$($skill.Name)"; Target = $skill.FullName })
    }
    return $links.ToArray()
}

function Get-HookScriptNames {
    return @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'hooks') -Filter '*.ps1' -File | ForEach-Object { $_.Name })
}

function Test-HarnessHook($Hook, [string[]]$ScriptNames) {
    $command = [string]$Hook.command
    foreach ($name in $ScriptNames) {
        if ($command -match ('[\\/]hooks[\\/]' + [regex]::Escape($name))) { return $true }
    }
    return $false
}

function Read-Settings([string]$SettingsPath) {
    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { return New-Object psobject }
    $text = [IO.File]::ReadAllText($SettingsPath)
    if ([string]::IsNullOrWhiteSpace($text)) { return New-Object psobject }
    try { return $text | ConvertFrom-Json }
    catch { throw "설정 파일을 읽지 못함(JSON 형식 오류): $SettingsPath. $($_.Exception.Message)" }
}

function Select-UserHookGroups($Groups, [string[]]$ScriptNames) {
    foreach ($group in @($Groups)) {
        if ($null -eq $group.PSObject.Properties['hooks']) { $group; continue }
        $kept = @(@($group.hooks) | Where-Object { -not (Test-HarnessHook $_ $ScriptNames) })
        if ($kept.Count -eq 0) { continue }
        $group.hooks = $kept
        $group
    }
}

function Remove-HarnessHooks($Settings, [string[]]$ScriptNames) {
    $hooksProperty = $Settings.PSObject.Properties['hooks']
    if ($null -eq $hooksProperty -or $null -eq $hooksProperty.Value) { return }

    foreach ($eventProperty in @($hooksProperty.Value.PSObject.Properties)) {
        $groups = @(Select-UserHookGroups $eventProperty.Value $ScriptNames)
        if ($groups.Count -gt 0) { $eventProperty.Value = $groups }
        else { $hooksProperty.Value.PSObject.Properties.Remove($eventProperty.Name) }
    }
    if (@($hooksProperty.Value.PSObject.Properties).Count -eq 0) { $Settings.PSObject.Properties.Remove('hooks') }
}

function Add-HarnessHooks($Settings) {
    $templateText = [IO.File]::ReadAllText((Join-Path $repoRoot 'settings.template.json'))
    $rendered = $templateText.Replace('__HARNESS_ROOT__', ($repoRoot -replace '\\', '/')) | ConvertFrom-Json

    if ($null -eq $Settings.PSObject.Properties['hooks']) {
        $Settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue (New-Object psobject)
    }
    foreach ($eventProperty in $rendered.hooks.PSObject.Properties) {
        $existing = $Settings.hooks.PSObject.Properties[$eventProperty.Name]
        if ($null -eq $existing) {
            $Settings.hooks | Add-Member -NotePropertyName $eventProperty.Name -NotePropertyValue @($eventProperty.Value)
        }
        else {
            $existing.Value = @(@($existing.Value) + @($eventProperty.Value))
        }
    }
}

function Save-Settings($Settings, [string]$SettingsPath) {
    $json = $Settings | ConvertTo-Json -Depth 32
    if (Test-Path -LiteralPath $SettingsPath -PathType Leaf) {
        if ([IO.File]::ReadAllText($SettingsPath).Trim() -eq $json.Trim()) { return }
        $backup = Get-UniqueBackupPath $SettingsPath
        if ($PSCmdlet.ShouldProcess($SettingsPath, "백업($backup) 후 훅 항목 갱신")) {
            Copy-Item -LiteralPath $SettingsPath -Destination $backup
            [IO.File]::WriteAllText($SettingsPath, $json + [Environment]::NewLine, $utf8NoBom)
            Write-Host "설정 갱신함: $SettingsPath. 백업: $backup"
        }
    }
    elseif ($PSCmdlet.ShouldProcess($SettingsPath, '훅 항목으로 새로 만들기')) {
        [IO.File]::WriteAllText($SettingsPath, $json + [Environment]::NewLine, $utf8NoBom)
        Write-Host "설정 만듦: $SettingsPath"
    }
}

function Initialize-LinkParents([string]$TargetRoot) {
    foreach ($parent in 'rules', 'skills') {
        $parentPath = Join-Path $TargetRoot $parent
        if (Test-Junction $parentPath) {
            Write-Warning "$parentPath 는 다른 폴더로 연결된 junction 임. 하네스 연결이 그 대상 폴더 안에 생김."
        }
        if (-not (Test-Path -LiteralPath $parentPath) -and $PSCmdlet.ShouldProcess($parentPath, '폴더 만들기')) {
            New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
        }
    }
}

function Move-ToBackup([string]$Target) {
    $backup = Get-UniqueBackupPath $Target
    if (-not $PSCmdlet.ShouldProcess($Target, "기존 경로를 $backup 로 백업")) { return }
    Move-Item -LiteralPath $Target -Destination $backup
    Write-Host "기존 경로 백업함: $backup"
}

function Install-Links([string]$TargetRoot, $Links) {
    Initialize-LinkParents $TargetRoot
    foreach ($entry in $Links) {
        $target = Get-FullPath $entry.Target
        $linked = (Test-Junction $entry.Link) -and ((Get-JunctionTarget $entry.Link) -ieq $target)
        if ($linked) {
            Write-Host "이미 연결됨: $($entry.Link)"
            continue
        }
        if (Get-Item -LiteralPath $entry.Link -Force -ErrorAction SilentlyContinue) { Move-ToBackup $entry.Link }
        if ($PSCmdlet.ShouldProcess($entry.Link, "junction 만들기 -> $target")) {
            New-Item -ItemType Junction -Path $entry.Link -Target $target | Out-Null
            Write-Host "연결함: $($entry.Link) -> $target"
        }
    }
}

function Uninstall-Links($Links) {
    foreach ($entry in $Links) {
        if (-not (Test-Junction $entry.Link)) { continue }
        if ((Get-JunctionTarget $entry.Link) -ine (Get-FullPath $entry.Target)) {
            Write-Warning "이 클론이 아닌 곳을 가리켜 그대로 둠: $($entry.Link)"
            continue
        }
        # Windows PowerShell 5.1 의 Remove-Item 은 junction 대상 내용까지 지울 수 있어 링크만 지우는 API 를 씀
        if ($PSCmdlet.ShouldProcess($entry.Link, 'junction 제거')) {
            [IO.Directory]::Delete($entry.Link, $false)
            Write-Host "연결 해제함: $($entry.Link)"
        }
    }
}

function Write-BackupList($Links) {
    $backups = @(foreach ($entry in $Links) {
        $parent = Split-Path -Parent $entry.Link
        if (Test-Path -LiteralPath $parent) {
            Get-ChildItem -LiteralPath $parent -Force -Filter ((Split-Path -Leaf $entry.Link) + '.backup-*') | ForEach-Object { $_.FullName }
        }
    })
    if ($backups.Count -eq 0) { return }
    Write-Host '백업 폴더가 남아 있음. rules 와 skills 안의 백업은 Claude Code 가 함께 읽으므로, 내용을 확인한 뒤 옮기거나 지울 것:'
    foreach ($backup in $backups) { Write-Host "  $backup" }
}

function Initialize-ProjectInstructions([string]$ProjectRoot) {
    foreach ($folder in 'fegate_api', 'fegate_api_exam') {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $folder) -PathType Container)) {
            Write-Warning "$folder 폴더가 없음: $ProjectRoot. SL 규칙과 훅은 이 폴더를 기준으로 동작함."
        }
    }
    $destination = Join-Path $ProjectRoot 'CLAUDE.md'
    if (Test-Path -LiteralPath $destination) {
        Write-Host "CLAUDE.md 가 이미 있어 그대로 둠: $destination. templates\CLAUDE.md 를 보고 필요한 절만 합칠 것."
        return
    }
    if ($PSCmdlet.ShouldProcess($destination, 'CLAUDE.md 템플릿 복사')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot 'templates\CLAUDE.md') -Destination $destination
        Write-Host "CLAUDE.md 만듦: $destination. '이 프로젝트' 절을 채울 것."
    }
}

foreach ($name in 'rules', 'skills', 'hooks', 'templates\CLAUDE.md', 'settings.template.json') {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $name))) {
        throw "하네스 저장소 구성이 빠짐: $name. install.ps1 은 SVD-Harness 클론 폴더 안에서 실행해야 함."
    }
}
if (-not $Scope) { $Scope = Read-InstallScope }
if ($Scope -eq 'Local') {
    if (-not $Path) { $Path = Read-LocalPath }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "폴더가 없음: $Path" }
    $projectRoot = Get-FullPath $Path
    $targetRoot = Join-Path $projectRoot '.claude'
}
else {
    $projectRoot = $null
    $targetRoot = Get-FullPath $ClaudeHome
}

$links = Get-HarnessLinks $targetRoot
$scriptNames = Get-HookScriptNames
# 훅 명령에 이 PC 의 클론 경로가 들어가서 로컬 설치는 팀이 커밋하지 않는 settings.local.json 에 씀
$settingsName = if ($projectRoot) { 'settings.local.json' } else { 'settings.json' }
$settingsPath = Join-Path $targetRoot $settingsName
Write-Host "설치 대상: $targetRoot"

if ($Uninstall) {
    Uninstall-Links $links
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $settings = Read-Settings $settingsPath
        Remove-HarnessHooks $settings $scriptNames
        Save-Settings $settings $settingsPath
    }
    if ($projectRoot) { Write-Host "CLAUDE.md 는 프로젝트 소유라 지우지 않음: $(Join-Path $projectRoot 'CLAUDE.md')" }
    Write-BackupList $links
    Write-Host 'SVD-Harness 제거 완료.'
    return
}

if (-not (Test-Path -LiteralPath $targetRoot) -and $PSCmdlet.ShouldProcess($targetRoot, '폴더 만들기')) {
    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
}
Install-Links $targetRoot $links

$settings = Read-Settings $settingsPath
Remove-HarnessHooks $settings $scriptNames
Add-HarnessHooks $settings
Save-Settings $settings $settingsPath

if ($projectRoot) { Initialize-ProjectInstructions $projectRoot }
else { Write-Host 'SL 프로젝트의 CLAUDE.md 는 로컬 설치로 넣거나 templates\CLAUDE.md 를 프로젝트 루트에 복사할 것.' }
Write-BackupList $links
Write-Host 'SVD-Harness 설치 완료. Claude Code 를 다시 시작하면 적용됨.'
