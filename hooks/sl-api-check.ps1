$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\skills\sl-api-lookup\scripts\SlApi.psm1') -Force

function Get-ChangedText($Payload) {
    $toolInput = $Payload.tool_input
    if ($null -eq $toolInput -or [IO.Path]::GetExtension([string]$toolInput.file_path) -ne '.sl') { return $null }
    switch ([string]$Payload.tool_name) {
        'Write' { return [string]$toolInput.content }
        'Edit' { return [string]$toolInput.new_string }
        'MultiEdit' { return (@($toolInput.edits) | ForEach-Object { [string]$_.new_string }) -join "`n" }
    }
    return $null
}

function Format-Report([string]$FilePath, [string]$FileText, [string[]]$Unknown, [object[]]$Index) {
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.Add("[sl-api-check] fegate_api 헤더에 없는 이름이 있음: $FilePath")
    foreach ($name in @($Unknown | Select-Object -First 15)) {
        $lineNumber = Get-SlLineNumber -Text $FileText -Name $name
        $where = if ($lineNumber) { " ($lineNumber 행)" } else { '' }
        $similar = @(Get-SlApiSuggestion -Index $Index -Name $name -Max 3)
        $hint = if ($similar.Count -gt 0) { ' 비슷한 이름: ' + ($similar -join ', ') } else { '' }
        $lines.Add("- $name$where$hint")
    }
    $lines.Add('sl-api-lookup 스킬로 헤더 선언을 확인하고 고칠 것. 다른 파일에 정의한 사용자 함수라면 정의 위치를 근거로 말할 것.')
    return ($lines -join "`n") + "`n"
}

# exit 0: 검사 대상 아님 또는 통과, exit 2: Claude 에게 알림, exit 1: 훅 오류(작업은 막지 않고 사용자에게 보임)
try {
    $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), (New-Object Text.UTF8Encoding($false)))
    $payload = $reader.ReadToEnd() | ConvertFrom-Json
    $changed = Get-ChangedText $payload
    if ([string]::IsNullOrWhiteSpace($changed)) { exit 0 }

    $filePath = [string]$payload.tool_input.file_path
    $root = Find-SlApiRoot -StartPath @($filePath, [string]$payload.cwd, $env:CLAUDE_PROJECT_DIR)
    if (-not $root) { exit 0 }
    $index = @(Get-SlApiIndex -ApiDir (Join-Path $root 'fegate_api'))
    if ($index.Count -eq 0) { exit 0 }

    $fileText = ''
    if (Test-Path -LiteralPath $filePath -PathType Leaf) { $fileText = [IO.File]::ReadAllText($filePath) }
    $contextText = $fileText + "`n" + (Get-SlIncludedText -Path $filePath -Text $fileText)

    # 이번 편집에서 새로 쓴 부분만 검사함. 파일에 원래 있던 이름을 매번 다시 알리지 않게 함
    $unknown = @(Find-SlUnknownCall -Index $index -ChangedText $changed -ContextText $contextText)
    if ($unknown.Count -eq 0) { exit 0 }

    Write-Utf8Stream -Stream Error -Text (Format-Report $filePath $fileText $unknown $index)
    exit 2
}
catch {
    Write-Utf8Stream -Stream Error -Text "[sl-api-check] 검사하지 못하고 넘어감: $($_.Exception.Message)`n"
    exit 1
}
