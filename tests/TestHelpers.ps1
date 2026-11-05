$RepoRoot = Split-Path -Parent $PSScriptRoot
$FixtureProject = Join-Path $PSScriptRoot 'fixtures\sl-project'
$HookScript = Join-Path $RepoRoot 'hooks\sl-api-check.ps1'
$FindScript = Join-Path $RepoRoot 'skills\sl-api-lookup\scripts\Find-SlApi.ps1'
$Installer = Join-Path $RepoRoot 'install.ps1'

function New-TestRoot {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('svd-harness-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    return $path
}

function Remove-TestRoot([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    foreach ($item in Get-ChildItem -LiteralPath $Path -Force) {
        # junction 은 링크만 지움. 따라 들어가면 하네스 저장소 파일이 지워짐
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { [IO.Directory]::Delete($item.FullName, $false) }
        elseif ($item.PSIsContainer) { Remove-TestRoot $item.FullName }
        else { Remove-Item -LiteralPath $item.FullName -Force }
    }
    [IO.Directory]::Delete($Path, $false)
}

function New-FixtureProject([string]$Root) {
    $project = Join-Path $Root 'project'
    Copy-Item -LiteralPath $FixtureProject -Destination $project -Recurse
    return $project
}

function Write-TestFile([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
    return $Path
}

function Invoke-PowerShellFile([string]$File, [string[]]$Arguments = @(), [string]$StdIn = '') {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $quoted = @($Arguments | ForEach-Object { '"' + $_ + '"' })
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $File, ($quoted -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8

    $process = [Diagnostics.Process]::Start($psi)
    if ($StdIn) {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($StdIn)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    }
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $result = [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout.Result; StdErr = $stderr.Result }
    $process.Dispose()
    return $result
}

function Invoke-Hook([hashtable]$Payload) {
    return Invoke-PowerShellFile -File $HookScript -StdIn ($Payload | ConvertTo-Json -Depth 8)
}
