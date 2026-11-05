. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'Find-SlApi.ps1' {
    function Find([string[]]$Arguments) {
        return Invoke-PowerShellFile -File $FindScript -Arguments (@('-Root', $FixtureProject) + $Arguments)
    }

    It 'prints the HELP_FUN block and an example path for a qualified name' {
        $result = Find @('-Name', 'dbNode::First')
        $result.ExitCode | Should Be 0
        $result.StdOut | Should Match '== dbNode::First \[function\] fegate_api/api_fixture.h:\d+-\d+'
        $result.StdOut | Should Match 'int dbNode::First\(\)'
        $result.StdOut | Should Match 'fegate_api_exam/db/node_first.sl'
    }

    It 'finds a namespaced function by its method name' {
        (Find @('-Name', 'Next')).StdOut | Should Match '== dbNode::Next \[function\]'
    }

    It 'reports a missing name with real suggestions' {
        $result = Find @('-Name', 'xutFileOpen')
        $result.StdOut | Should Match '없음: xutFileOpen'
        $result.StdOut | Should Match 'xuFileOpenWindow'
    }

    It 'is case sensitive' {
        (Find @('-Name', 'dbnode::first')).StdOut | Should Match '없음'
    }

    It 'finds structs and defines' {
        (Find @('-Name', 'stPair')).StdOut | Should Match '== stPair \[struct\]'
        (Find @('-Name', 'DB_NODE')).StdOut | Should Match '#define DB_NODE 2'
    }

    It 'expands wildcards and respects -Max' {
        $result = Find @('-Name', 'xut*', '-Max', '2', '-NoExample')
        ([regex]::Matches($result.StdOut, '(?m)^== ')).Count | Should Be 2
        $result.StdOut | Should Match '외 1개가 더 있음'
    }

    It 'fails when no fegate_api folder exists' {
        $work = New-TestRoot
        try { (Invoke-PowerShellFile -File $FindScript -Arguments @('-Root', $work, '-Name', 'x')).ExitCode | Should Be 1 }
        finally { Remove-TestRoot $work }
    }
}
