[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Root,
    [int]$Max = 5,
    [switch]$NoExample
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SlApi.psm1') -Force

function Format-ExampleLine($Entry, [string[]]$ExamFiles, [string]$ProjectRoot) {
    $pattern = if ($Entry.Kind -eq 'function') { '(?<![\w:])' + [regex]::Escape($Entry.Name) + '\s*\(' }
               else { '\b' + [regex]::Escape($Entry.Name) + '\b' }
    $hits = @(Select-String -LiteralPath $ExamFiles -Pattern $pattern -List -CaseSensitive -Encoding UTF8)
    if ($hits.Count -eq 0) { return '예제: 없음' }

    $paths = @($hits | Select-Object -First 3 | ForEach-Object { Get-SlRelativePath -Root $ProjectRoot -Path $_.Path })
    $more = if ($hits.Count -gt 3) { " 외 $($hits.Count - 3)개" } else { '' }
    return "예제: $($paths -join ', ')$more"
}

$searchFrom = if ($Root) { @($Root) } else { @((Get-Location).Path) }
$projectRoot = Find-SlApiRoot -StartPath $searchFrom
if (-not $projectRoot) {
    Write-Utf8Stream -Stream Output -Text "fegate_api 폴더를 찾지 못함. -Root 로 SL 프로젝트 루트를 지정할 것.`n"
    exit 1
}

$index = @(Get-SlApiIndex -ApiDir (Join-Path $projectRoot 'fegate_api'))
$found = @(Select-SlApiEntry -Index $index -Name $Name)
$out = New-Object 'Collections.Generic.List[string]'

if ($found.Count -eq 0) {
    $out.Add("없음: $Name 은(는) fegate_api 헤더에 없음.")
    $similar = @(Get-SlApiSuggestion -Index $index -Name $Name)
    if ($similar.Count -gt 0) { $out.Add('비슷한 실제 이름: ' + ($similar -join ', ')) }
    else { $out.Add('비슷한 이름도 없음.') }
    Write-Utf8Stream -Stream Output -Text (($out -join "`n") + "`n")
    exit 0
}

$examDir = Join-Path $projectRoot 'fegate_api_exam'
$examFiles = @()
if (-not $NoExample -and (Test-Path -LiteralPath $examDir -PathType Container)) {
    $examFiles = @(Get-ChildItem -LiteralPath $examDir -Filter '*.sl' -File -Recurse | ForEach-Object { $_.FullName })
}

$cache = @{}
foreach ($entry in @($found | Select-Object -First $Max)) {
    $block = Get-SlApiBlock -Entry $entry -Cache $cache
    $relative = Get-SlRelativePath -Root $projectRoot -Path $entry.File
    $out.Add("== $($entry.Name) [$($entry.Kind)] ${relative}:$($block.StartLine)-$($block.EndLine)")
    $out.Add($block.Text)
    if ($examFiles.Count -gt 0) { $out.Add((Format-ExampleLine $entry $examFiles $projectRoot)) }
    $out.Add('')
}

if ($found.Count -gt $Max) {
    $out.Add("외 $($found.Count - $Max)개가 더 있음. -Max 를 늘리거나 이름을 좁힐 것.")
}
Write-Utf8Stream -Stream Output -Text (($out -join "`n") + "`n")
