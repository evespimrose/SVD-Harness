function Test-SlApiRoot([string]$Dir) {
    $apiDir = Join-Path $Dir 'fegate_api'
    if (-not (Test-Path -LiteralPath $apiDir -PathType Container)) { return $false }
    return @(Get-ChildItem -LiteralPath $apiDir -Filter '*.h' -File -ErrorAction SilentlyContinue).Count -gt 0
}

function Get-SlApiRootAbove([string]$Start) {
    if ([string]::IsNullOrWhiteSpace($Start)) { return $null }
    try { $dir = [IO.Path]::GetFullPath($Start) } catch { return $null }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { $dir = Split-Path -Parent $dir }

    while (-not [string]::IsNullOrEmpty($dir)) {
        if (Test-SlApiRoot $dir) { return $dir }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { return $null }
        $dir = $parent
    }
    return $null
}

function Find-SlApiRoot {
    param([string[]]$StartPath)

    foreach ($start in $StartPath) {
        $root = Get-SlApiRootAbove $start
        if ($root) { return $root }
    }
    return $null
}

function New-SlApiEntry([string]$Name, [string]$Kind, [string]$Declaration, [string]$File, [int]$Line) {
    [pscustomobject]@{
        Name        = $Name
        Kind        = $Kind
        Declaration = $Declaration
        File        = $File
        Line        = $Line
    }
}

function ConvertTo-SlApiEntry($Hit) {
    $lines = @($Hit.Context.PostContext | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($lines.Count -eq 0) { return }
    $text = $lines[0].Trim()

    if ($Hit.Matches[0].Groups[1].Value -eq 'name') {
        if ($text -match '^[A-Za-z_]\w*$') { New-SlApiEntry $text 'struct' $text $Hit.Path $Hit.LineNumber }
        return
    }
    $match = [regex]::Match($text, '([A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)\s*\(')
    if ($match.Success) { New-SlApiEntry $match.Groups[1].Value 'function' $text $Hit.Path $Hit.LineNumber }
}

function Get-SlApiIndex {
    param([Parameter(Mandatory = $true)][string]$ApiDir)

    $paths = @(Get-ChildItem -LiteralPath $ApiDir -Filter '*.h' -File | ForEach-Object { $_.FullName })
    if ($paths.Count -eq 0) { return @() }

    $declared = @(foreach ($hit in Select-String -LiteralPath $paths -Pattern '^\s*@(decl|name)\s*$' -Context 0, 3 -Encoding UTF8) {
        ConvertTo-SlApiEntry $hit
    })
    $defines = @(foreach ($hit in Select-String -LiteralPath $paths -Pattern '^\s*#define\s+([A-Za-z_]\w*)\b' -Encoding UTF8) {
        New-SlApiEntry $hit.Matches[0].Groups[1].Value 'define' $hit.Line.Trim() $hit.Path $hit.LineNumber
    })
    return $declared + $defines
}

function Get-SlShortName([string]$Name) {
    return ($Name -split '::')[-1]
}

function Select-SlApiEntry {
    param([object[]]$Index, [string]$Name)

    if ($Name -match '[*?]') {
        return @($Index | Where-Object { $_.Name -clike $Name -or (Get-SlShortName $_.Name) -clike $Name })
    }
    $exact = @($Index | Where-Object { $_.Name -ceq $Name })
    if ($exact.Count -gt 0) { return $exact }
    if ($Name -notmatch '::') {
        return @($Index | Where-Object { $_.Kind -eq 'function' -and (Get-SlShortName $_.Name) -ceq $Name })
    }
    return @()
}

function Get-SlNameScore([string]$EntryName, [string]$Name, [string]$Short, [string]$Namespace, [string[]]$Tokens) {
    $entryShort = Get-SlShortName $EntryName
    $score = 0
    if ($EntryName -ieq $Name) { $score += 100 }
    if ($entryShort -ieq $Short) { $score += 50 }
    $lower = $EntryName.ToLowerInvariant()
    foreach ($token in $Tokens) { if ($lower.Contains($token)) { $score += 2 } }

    if (-not $Namespace -or -not $EntryName.StartsWith($Namespace + '::')) { return $score }
    $score += 1
    if ($Short.Length -ge 3 -and $entryShort.StartsWith($Short.Substring(0, 3), [StringComparison]::OrdinalIgnoreCase)) { $score += 3 }
    return $score
}

function Get-SlApiSuggestion {
    param([object[]]$Index, [string]$Name, [int]$Max = 8)

    $short = Get-SlShortName $Name
    $namespace = $null
    if ($Name -match '^(\w+)::') { $namespace = $Matches[1] }
    $tokens = @([regex]::Matches($short, '[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+') |
        ForEach-Object { $_.Value.ToLowerInvariant() } |
        Where-Object { $_.Length -ge 3 } |
        Select-Object -Unique)

    $scored = foreach ($entry in $Index) {
        $score = Get-SlNameScore $entry.Name $Name $short $namespace $tokens
        # 접두사 토큰 하나만 맞는 이름(xut 계열 78개 등)은 후보에서 뺌
        if ($score -ge 3) { [pscustomobject]@{ Name = $entry.Name; Score = $score } }
    }

    return @($scored |
        Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = { $_.Name.Length } } |
        Select-Object -ExpandProperty Name -Unique |
        Select-Object -First $Max)
}

function Get-SlApiBlock {
    param([Parameter(Mandatory = $true)]$Entry, [hashtable]$Cache = @{})

    if ($Entry.Kind -eq 'define') {
        return [pscustomobject]@{ StartLine = $Entry.Line; EndLine = $Entry.Line; Text = $Entry.Declaration }
    }
    if (-not $Cache.ContainsKey($Entry.File)) { $Cache[$Entry.File] = [IO.File]::ReadAllLines($Entry.File) }
    $lines = $Cache[$Entry.File]

    $start = $Entry.Line - 1
    while ($start -gt 0 -and $lines[$start] -notmatch '^\s*/\*\*HELP_') { $start-- }
    $end = $Entry.Line - 1
    while ($end -lt $lines.Count - 1 -and $lines[$end] -notmatch '\*/\s*$') { $end++ }

    return [pscustomobject]@{ StartLine = $start + 1; EndLine = $end + 1; Text = ($lines[$start..$end] -join "`n") }
}

function Remove-SlCommentAndString {
    param([string]$Text)

    if (-not $Text) { return '' }
    # 줄바꿈은 남겨서 줄 번호가 원문과 맞게 함
    $evaluator = [Text.RegularExpressions.MatchEvaluator] { param($m) [regex]::Replace($m.Value, '[^\r\n]', ' ') }
    return [regex]::Replace($Text, '"(?:\\.|[^"\\\r\n])*"|//[^\r\n]*|/\*[\s\S]*?\*/', $evaluator)
}

function Get-SlDefinedName {
    param([string]$Text)

    $names = New-Object 'Collections.Generic.HashSet[string]'
    $keywords = @('return', 'else', 'case', 'new', 'delete', 'if', 'while', 'for', 'switch', 'do', 'goto')
    foreach ($m in [regex]::Matches($Text, '(?<![\w:.])([A-Za-z_]\w*)(?:\s*\[\s*\])*\s+([A-Za-z_]\w*)\s*\(')) {
        if ($keywords -notcontains $m.Groups[1].Value) { [void]$names.Add($m.Groups[2].Value) }
    }
    return , $names
}

function Get-SlIncludedText {
    param([string]$Path, [string]$Text, [int]$Depth = 0, $Visited = $null)

    if ($null -eq $Visited) { $Visited = New-Object 'Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase) }
    if ($Depth -gt 5 -or -not $Text -or -not $Path) { return '' }

    $parts = New-Object 'Collections.Generic.List[string]'
    $baseDir = Split-Path -Parent $Path
    foreach ($m in [regex]::Matches($Text, '(?m)^\s*#include\s+[<"]([^>"]+)[>"]')) {
        # 경로로 쓸 수 없는 include 는 건너뜀. 정의를 못 보면 훅이 알림을 더 내는 쪽으로 틀림
        try { $target = [IO.Path]::GetFullPath((Join-Path $baseDir $m.Groups[1].Value)) } catch { continue }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
        if (-not $Visited.Add($target)) { continue }
        $content = [IO.File]::ReadAllText($target)
        $parts.Add($content)
        $parts.Add((Get-SlIncludedText -Path $target -Text $content -Depth ($Depth + 1) -Visited $Visited))
    }
    return ($parts -join "`n")
}

function Get-SlApiFamily {
    param([object[]]$Index)

    $counts = @{}
    foreach ($entry in $Index) {
        if ($entry.Kind -ne 'function' -or $entry.Name.Contains('::')) { continue }
        if ($entry.Name -cmatch '^([a-z]{2,})[A-Z0-9]') { $counts[$Matches[1]] = 1 + [int]$counts[$Matches[1]] }
    }
    $families = New-Object 'Collections.Generic.HashSet[string]'
    # 선언이 3개 이상인 접두사만 API 계열로 봄. int2dbl 같은 단발 이름이 계열이 되지 않게 함
    foreach ($key in $counts.Keys) { if ($counts[$key] -ge 3) { [void]$families.Add($key) } }
    return , $families
}

function Get-SlKnownNames([object[]]$Index, [string]$SourceText) {
    $known = [pscustomobject]@{
        Functions      = New-Object 'Collections.Generic.HashSet[string]'
        ApiNamespaces  = New-Object 'Collections.Generic.HashSet[string]'
        UserNamespaces = New-Object 'Collections.Generic.HashSet[string]'
        Families       = Get-SlApiFamily -Index $Index
        Defined        = $null
    }
    foreach ($entry in $Index) {
        if ($entry.Kind -ne 'function') { continue }
        [void]$known.Functions.Add($entry.Name)
        if ($entry.Name.Contains('::')) { [void]$known.ApiNamespaces.Add(($entry.Name -split '::')[0]) }
    }
    $clean = Remove-SlCommentAndString $SourceText
    $known.Defined = Get-SlDefinedName -Text $clean
    foreach ($m in [regex]::Matches($clean, '\bnamespace\s+([A-Za-z_]\w*)')) { [void]$known.UserNamespaces.Add($m.Groups[1].Value) }
    return $known
}

function Test-SlUnknownName([string]$Name, $Known) {
    if ($Known.Functions.Contains($Name)) { return $false }
    if ($Name.Contains('::')) {
        $namespace = ($Name -split '::')[0]
        return $Known.ApiNamespaces.Contains($namespace) -or -not $Known.UserNamespaces.Contains($namespace)
    }
    if ($Known.Defined.Contains($Name)) { return $false }
    # 사용자 함수는 대개 snake_case 라서 API 계열 접두사 + 대문자 형태만 검사함
    return ($Name -cmatch '^([a-z]+)[A-Z0-9]') -and $Known.Families.Contains($Matches[1])
}

function Find-SlUnknownCall {
    param([object[]]$Index, [string]$ChangedText, [string]$ContextText)

    $known = Get-SlKnownNames -Index $Index -SourceText ($ContextText + "`n" + $ChangedText)
    $unknown = New-Object 'Collections.Generic.List[string]'
    foreach ($m in [regex]::Matches((Remove-SlCommentAndString $ChangedText), '(?<![\w:.])([A-Za-z_]\w*::[A-Za-z_]\w*|[A-Za-z_]\w*)\s*\(')) {
        $name = $m.Groups[1].Value
        if (-not $unknown.Contains($name) -and (Test-SlUnknownName $name $known)) { $unknown.Add($name) }
    }
    return $unknown.ToArray()
}

function Get-SlLineNumber {
    param([string]$Text, [string]$Name)

    if (-not $Text) { return $null }
    $clean = Remove-SlCommentAndString $Text
    $m = [regex]::Match($clean, '(?<![\w:.])' + [regex]::Escape($Name) + '\s*\(')
    if (-not $m.Success) { return $null }
    return [regex]::Matches($clean.Substring(0, $m.Index), "`n").Count + 1
}

function Get-SlRelativePath([string]$Root, [string]$Path) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($rootFull.Length + 1).Replace('\', '/')
    }
    return $full
}

function Write-Utf8Stream {
    param([ValidateSet('Output', 'Error')][string]$Stream, [string]$Text)

    # Windows PowerShell 5.1 콘솔 인코딩(CP949 등)을 거치면 한글이 깨져서 바이트로 직접 씀
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
    $target = if ($Stream -eq 'Error') { [Console]::OpenStandardError() } else { [Console]::OpenStandardOutput() }
    $target.Write($bytes, 0, $bytes.Length)
    $target.Flush()
}

Export-ModuleMember -Function Find-SlApiRoot, Get-SlApiIndex, Select-SlApiEntry, Get-SlApiSuggestion, Get-SlApiBlock,
    Get-SlIncludedText, Find-SlUnknownCall, Get-SlLineNumber, Get-SlRelativePath, Write-Utf8Stream
