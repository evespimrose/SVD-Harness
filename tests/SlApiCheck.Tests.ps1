. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'sl-api-check hook' {
    BeforeAll {
        $script:work = New-TestRoot
        $script:project = New-FixtureProject $script:work
    }
    AfterAll { Remove-TestRoot $script:work }

    function Invoke-WriteHook([string]$RelativePath, [string]$Content) {
        $file = Write-TestFile (Join-Path $script:project $RelativePath) $Content
        return Invoke-Hook @{ tool_name = 'Write'; cwd = $script:project; tool_input = @{ file_path = $file; content = $Content } }
    }

    It 'reports a free function that is missing from the headers and suggests the real one' {
        $result = Invoke-WriteHook 'src\open.sl' "void main()`n{`n`tstring path;`n`txutFileOpen(path);`n}`n"
        $result.ExitCode | Should Be 2
        $result.StdErr | Should Match 'xutFileOpen \(4 행\)'
        $result.StdErr | Should Match 'xuFileOpenWindow'
    }

    It 'reports a wrong method name in an API namespace' {
        $result = Invoke-WriteHook 'src\first.sl' "void main() { int i = dbNode::Firstt(); }"
        $result.ExitCode | Should Be 2
        $result.StdErr | Should Match 'dbNode::Firstt'
        $result.StdErr | Should Match 'dbNode::First\b'
    }

    It 'passes declared API calls, snake_case user functions, and message()' {
        $code = "void bt_apply(int opt) { count_nodes(); }`nint count_nodes() { int i = dbNode::First(); return dbNode::Next(i); }`nvoid main() { xutPanel(""p""); xutButton(""Apply"", 1, bt_apply); message(""done""); }"
        (Invoke-WriteHook 'src\ok.sl' $code).ExitCode | Should Be 0
    }

    It 'passes an API-like user function defined in the same file' {
        $code = "int xutHelper(int a) { return a; }`nvoid main() { xutHelper(1); }"
        (Invoke-WriteHook 'src\helper.sl' $code).ExitCode | Should Be 0
    }

    It 'passes functions and user namespaces defined in an included file' {
        Write-TestFile (Join-Path $script:project 'src\lib\tools.sl') "namespace tools {`nvoid run() { }`n}`nint aryHelper() { return 0; }" | Out-Null
        $code = "#include ""lib/tools.sl""`nvoid main() { tools::run(); aryHelper(); }"
        (Invoke-WriteHook 'src\use_lib.sl' $code).ExitCode | Should Be 0
    }

    It 'ignores names inside comments and strings' {
        $code = "// xutFileOpen(path)`n/* dbNode::Firstt() */`nvoid main() { message(""xutFileOpen()""); }"
        (Invoke-WriteHook 'src\comment.sl' $code).ExitCode | Should Be 0
    }

    It 'checks only the new text of an Edit' {
        $file = Write-TestFile (Join-Path $script:project 'src\legacy.sl') "void main() { xutFileOpen(p); }"
        $clean = Invoke-Hook @{ tool_name = 'Edit'; tool_input = @{ file_path = $file; old_string = 'a'; new_string = 'int n = arySize(list);' } }
        $clean.ExitCode | Should Be 0
        $bad = Invoke-Hook @{ tool_name = 'Edit'; tool_input = @{ file_path = $file; old_string = 'a'; new_string = 'aryLength(list);' } }
        $bad.ExitCode | Should Be 2
        $bad.StdErr | Should Match 'aryLength'
    }

    It 'checks every edit of a MultiEdit' {
        $file = Write-TestFile (Join-Path $script:project 'src\multi.sl') "void main() { }"
        $edits = @(@{ old_string = 'a'; new_string = 'aryClear(list);' }, @{ old_string = 'b'; new_string = 'aryErase(list, 0);' })
        $result = Invoke-Hook @{ tool_name = 'MultiEdit'; tool_input = @{ file_path = $file; edits = $edits } }
        $result.ExitCode | Should Be 2
        $result.StdErr | Should Match 'aryErase'
        $result.StdErr | Should Not Match 'aryClear'
    }

    It 'ignores files that are not .sl' {
        $file = Write-TestFile (Join-Path $script:project 'src\note.txt') 'xutFileOpen()'
        (Invoke-Hook @{ tool_name = 'Write'; tool_input = @{ file_path = $file; content = 'xutFileOpen()' } }).ExitCode | Should Be 0
    }

    It 'passes when no fegate_api folder can be found' {
        $outside = Write-TestFile (Join-Path $script:work 'outside\a.sl') 'xutFileOpen();'
        (Invoke-Hook @{ tool_name = 'Write'; tool_input = @{ file_path = $outside; content = 'xutFileOpen();' } }).ExitCode | Should Be 0
    }

    It 'reports its own failure without blocking the edit' {
        $result = Invoke-PowerShellFile -File $HookScript -StdIn '{not json'
        $result.ExitCode | Should Be 1
        $result.StdErr | Should Match '\[sl-api-check\]'
    }

    It 'passes when the headers hold no declarations' {
        $bare = Join-Path $script:work 'bare'
        Write-TestFile (Join-Path $bare 'fegate_api\empty.h') '// no declarations' | Out-Null
        $file = Write-TestFile (Join-Path $bare 'a.sl') 'void main() { dbNode::First(); }'
        (Invoke-Hook @{ tool_name = 'Write'; tool_input = @{ file_path = $file; content = 'void main() { dbNode::First(); }' } }).ExitCode | Should Be 0
    }
}
