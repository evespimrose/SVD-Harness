. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'repository files' {
    It 'saves every PowerShell file as UTF-8 with BOM so Windows PowerShell 5.1 reads Korean text correctly' {
        $missing = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File | Where-Object { @('.ps1', '.psm1') -contains $_.Extension } | Where-Object {
            $bytes = [IO.File]::ReadAllBytes($_.FullName)
            -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        } | ForEach-Object { $_.FullName })
        $missing -join ', ' | Should BeNullOrEmpty
    }

    It 'keeps the settings template valid with the root placeholder' {
        $text = [IO.File]::ReadAllText((Join-Path $RepoRoot 'settings.template.json'))
        $text | Should Match '__HARNESS_ROOT__'
        { $text | ConvertFrom-Json } | Should Not Throw
    }

    It 'gives every skill a SKILL.md with name and description' {
        foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'skills') -Directory) {
            $text = [IO.File]::ReadAllText((Join-Path $skill.FullName 'SKILL.md'))
            $text | Should Match ('(?m)^name: ' + [regex]::Escape($skill.Name) + '\s*$')
            $text | Should Match '(?m)^description: \S'
        }
    }
}
