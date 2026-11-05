. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'install.ps1' {
    BeforeEach {
        $script:work = New-TestRoot
        $script:globalHome = Join-Path $script:work 'home\.claude'
        $script:project = Join-Path $script:work 'project'
        New-Item -ItemType Directory -Path $script:project | Out-Null
    }
    AfterEach { Remove-TestRoot $script:work }

    function Get-Target([string]$Link) { return [string]@((Get-Item -LiteralPath $Link -Force).Target)[0] }
    function Read-Json([string]$File) { return [IO.File]::ReadAllText($File) | ConvertFrom-Json }
    function Get-HarnessCommands($Settings) {
        return @(@($Settings.hooks.PostToolUse) | ForEach-Object { @($_.hooks) } | Where-Object { $_.command -match 'sl-api-check\.ps1' })
    }
    function Install-Global([string[]]$Extra = @()) {
        $arguments = @{ Scope = 'Global'; ClaudeHome = $script:globalHome }
        if ($Extra -contains 'Uninstall') { $arguments.Uninstall = $true }
        & $Installer @arguments *> $null
    }

    It 'links the rules folder and every skill into the global folder' {
        Install-Global
        Get-Target (Join-Path $script:globalHome 'rules\svd-harness') | Should Be (Join-Path $RepoRoot 'rules')
        Get-Target (Join-Path $script:globalHome 'skills\sl-api-lookup') | Should Be (Join-Path $RepoRoot 'skills\sl-api-lookup')
        Get-Target (Join-Path $script:globalHome 'skills\sl-report-fail') | Should Be (Join-Path $RepoRoot 'skills\sl-report-fail')
        Test-Path (Join-Path $script:project 'CLAUDE.md') | Should Be $false
    }

    It 'installs locally into the .claude folder of the given path and seeds CLAUDE.md' {
        & $Installer -Scope Local -Path $script:project *> $null
        $local = Join-Path $script:project '.claude'
        Get-Target (Join-Path $local 'rules\svd-harness') | Should Be (Join-Path $RepoRoot 'rules')
        @(Get-HarnessCommands (Read-Json (Join-Path $local 'settings.local.json'))).Count | Should Be 1
        Test-Path (Join-Path $local 'settings.json') | Should Be $false
        [IO.File]::ReadAllText((Join-Path $script:project 'CLAUDE.md')) | Should Be ([IO.File]::ReadAllText((Join-Path $RepoRoot 'templates\CLAUDE.md')))
        Test-Path $script:globalHome | Should Be $false
    }

    It 'asks for the scope and the local path when they are not given' {
        $result = Invoke-PowerShellFile -File $Installer -Arguments @('-ClaudeHome', $script:globalHome) -StdIn "3`r`n2`r`n$($script:project)`r`n"
        $result.ExitCode | Should Be 0
        Get-Target (Join-Path $script:project '.claude\skills\sl-api-lookup') | Should Be (Join-Path $RepoRoot 'skills\sl-api-lookup')
        Test-Path $script:globalHome | Should Be $false
    }

    It 'registers the hook once, keeps other settings, and backs up settings.json' {
        $settingsPath = Write-TestFile (Join-Path $script:globalHome 'settings.json') '{"env":{"KEEP":"1"},"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo user"}]},{"matcher":"Odd"}]}}'
        Install-Global
        Install-Global

        $settings = Read-Json $settingsPath
        $settings.env.KEEP | Should Be '1'
        @($settings.hooks.PostToolUse).Count | Should Be 3
        @($settings.hooks.PostToolUse | Where-Object { $_.matcher -eq 'Odd' }).Count | Should Be 1
        @(Get-HarnessCommands $settings).Count | Should Be 1
        @(Get-HarnessCommands $settings)[0].command | Should Match ([regex]::Escape(($RepoRoot -replace '\\', '/') + '/hooks/sl-api-check.ps1'))
        @(Get-ChildItem -LiteralPath $script:globalHome -Filter 'settings.json.backup-*').Count | Should Be 1
    }

    It 'moves a folder in the way to a backup before linking' {
        Write-TestFile (Join-Path $script:globalHome 'skills\sl-api-lookup\old.txt') 'old' | Out-Null
        Install-Global

        Get-Target (Join-Path $script:globalHome 'skills\sl-api-lookup') | Should Be (Join-Path $RepoRoot 'skills\sl-api-lookup')
        $backups = @(Get-ChildItem -LiteralPath (Join-Path $script:globalHome 'skills') -Filter 'sl-api-lookup.backup-*')
        $backups.Count | Should Be 1
        [IO.File]::ReadAllText((Join-Path $backups[0].FullName 'old.txt')) | Should Be 'old'
    }

    It 'keeps an existing CLAUDE.md in local mode' {
        Write-TestFile (Join-Path $script:project 'CLAUDE.md') 'mine' | Out-Null
        & $Installer -Scope Local -Path $script:project *> $null
        [IO.File]::ReadAllText((Join-Path $script:project 'CLAUDE.md')) | Should Be 'mine'
    }

    It 'uninstalls only its own links and hooks and leaves the clone intact' {
        Write-TestFile (Join-Path $script:globalHome 'settings.json') '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo user"}]}]}}' | Out-Null
        Install-Global
        Install-Global @('Uninstall')

        Test-Path (Join-Path $script:globalHome 'rules\svd-harness') | Should Be $false
        Test-Path (Join-Path $script:globalHome 'skills\sl-api-lookup') | Should Be $false
        Test-Path (Join-Path $RepoRoot 'rules\sl-naming.md') | Should Be $true
        $settings = Read-Json (Join-Path $script:globalHome 'settings.json')
        @(Get-HarnessCommands $settings).Count | Should Be 0
        @($settings.hooks.PostToolUse)[0].hooks[0].command | Should Be 'echo user'
    }

    It 'rejects a local path that does not exist' {
        { & $Installer -Scope Local -Path (Join-Path $script:work 'missing') *> $null } | Should Throw
    }

    It 'changes nothing with -WhatIf' {
        & $Installer -Scope Global -ClaudeHome $script:globalHome -WhatIf *> $null
        Test-Path $script:globalHome | Should Be $false
    }
}
