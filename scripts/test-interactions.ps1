param([switch]$Gui)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$entry = Join-Path $root 'copilot\modules\interaction\scripts\select.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) "sdd-decisions-$([guid]::NewGuid().ToString('N'))"
$passes = 0
$started = @()
function Assert($value, $message) { if (-not $value) { throw $message }; $script:passes++; Write-Output "PASS $message" }
function Write-Request($requestData) { [IO.File]::WriteAllText("$temp\request.json", ($requestData | ConvertTo-Json -Depth 10)) }
function Run-Validation([switch]$Failure) {
    $ErrorActionPreference = 'Continue'
    $raw = & powershell -NoProfile -File $entry -Request "$temp\request.json" -ValidateOnly 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $value = $raw | ConvertFrom-Json
    if ($Failure) { Assert ($code -ne 0 -and $value.status -eq 'ERROR') 'malformed request returns explicit ERROR, not defaults'; return }
    if ($code) { throw $raw }
    $value
}
function New-Question($id, $title, $kind, $approval) {
    [pscustomobject]@{
        id = $id; title = $title; kind = $kind; approval = $approval; allowCustom = $true
        options = @([pscustomobject]@{ value = 'first'; label = 'First' }, [pscustomobject]@{ value = 'second'; label = 'Second' })
        recommended = @('first'); reason = 'Fixture source evidence recommends First; this is not permission.'
    }
}
try {
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $data = [pscustomobject]@{ taskId = 'isolated-interaction-fixture'; questions = @(
        (New-Question repository 'Repository selection' single $false),
        (New-Question scope 'Implementation scope' multiple $false),
        (New-Question branch 'Branch selection' single $false),
        (New-Question approval 'Implementation approval' single $true),
        (New-Question pbi 'PBI Resume / Modify / New' single $false)
    ) }
    $data.questions[3].options = @([pscustomobject]@{ value = 'approve'; label = 'Approve' }, [pscustomobject]@{ value = 'reject'; label = 'Reject' })
    $data.questions[3].recommended = @('approve')
    $data.questions[4].options = @(
        [pscustomobject]@{ value = 'resume'; label = 'Resume' },
        [pscustomobject]@{ value = 'modify'; label = 'Modify' },
        [pscustomobject]@{ value = 'new'; label = 'New' }
    )
    $data.questions[4].recommended = @('resume')
    Write-Request $data
    $validated = Run-Validation
    Assert ($validated.status -eq 'VALID' -and $validated.questions.Count -eq 5) 'all five interaction categories validate without UI or actions'
    Assert ($validated.questions[0].initial.values -eq 'first' -and $validated.questions[3].initial.values.Count -eq 0) 'evidence-backed default is selected but approval recommendation is never preselected'
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($entry, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Interaction script has syntax errors.' }
    foreach ($name in 'Read-DecisionRequest', 'Get-InitialAnswer', 'Assert-DecisionAnswer') {
        $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    Assert-DecisionAnswer $data.questions[1] ([pscustomobject]@{ values = @('first', 'second'); custom = '' })
    Assert $true 'multiple valid selections are accepted'
    Assert-DecisionAnswer $data.questions[2] ([pscustomobject]@{ values = @(); custom = 'feature/custom' })
    Assert $true 'custom answer is accepted instead of a single choice'
    foreach ($answer in @(
        [pscustomobject]@{ values = @(); custom = '' },
        [pscustomobject]@{ values = @('invented'); custom = '' },
        [pscustomobject]@{ values = @('first', 'second'); custom = '' },
        [pscustomobject]@{ values = @('first'); custom = 'conflict' }
    )) {
        $rejected = $false
        try { Assert-DecisionAnswer $data.questions[0] $answer } catch [ArgumentException] { $rejected = $true }
        Assert $rejected 'empty/unknown/conflicting single-choice answer is refused'
    }
    $rejected = $false
    try { Assert-DecisionAnswer $data.questions[1] ([pscustomobject]@{ values = @(); custom = '' }) } catch [ArgumentException] { $rejected = $true }
    Assert $rejected 'an empty multiple-choice answer is refused unless the question allows it'
    $optional = $data.questions[1] | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    $optional | Add-Member -NotePropertyName allowEmpty -NotePropertyValue $true
    Assert-DecisionAnswer $optional ([pscustomobject]@{ values = @(); custom = '' })
    Assert $true 'a multiple-choice question with allowEmpty accepts an empty selection'
    $original = $data | ConvertTo-Json -Depth 10
    foreach ($mutation in @(
        { $data.taskId = '' },
        { $data.questions[1].id = 'repository' },
        { $data.questions[0].recommended = @('missing') },
        { $data.questions[0].reason = '' },
        { $data.questions[3].kind = 'multiple' },
        { $data.questions[0] | Add-Member -NotePropertyName allowEmpty -NotePropertyValue $true },
        { $data.questions[1] | Add-Member -NotePropertyName allowEmpty -NotePropertyValue 'yes' }
    )) {
        $data = $original | ConvertFrom-Json
        & $mutation
        Write-Request $data
        Run-Validation -Failure
    }
    $data = $original | ConvertFrom-Json
    Write-Request $data
    if ($Gui) {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, UIAutomationClientSideProviders, Accessibility
        Add-Type -Name SddDecisionTestWin -Namespace '' -ReferencedAssemblies ([Accessibility.IAccessible].Assembly.Location) -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int message, IntPtr w, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int message, IntPtr w, string l);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int message, IntPtr w, IntPtr l);
[DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out Accessibility.IAccessible accessible);
public static bool IsChecked(IntPtr h) {
    var iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
    Accessibility.IAccessible accessible;
    Marshal.ThrowExceptionForHR(AccessibleObjectFromWindow(h, 0xFFFFFFFC, ref iid, out accessible));
    try { return ((int)accessible.get_accState(0) & 0x10) != 0; }
    finally { Marshal.ReleaseComObject(accessible); }
}
'@
        function Find-OwnWindow($process) {
            $deadline = (Get-Date).AddSeconds(30)
            do {
                $process.Refresh()
                if ($process.HasExited) { throw "Decision helper exited before displaying UI: $($process.ExitCode)" }
                if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
                    $found = [Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
                    if ($found.Current.Name -eq 'SDD decision - Windows modal fallback') { return $found }
                }
                Start-Sleep -Milliseconds 200
            } while ((Get-Date) -lt $deadline)
            throw 'Windows modal fallback did not display.'
        }
        function Control($window, $name) {
            $cond = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, $name)
            $found = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, $cond)
            if (-not $found -and $name -eq 'Custom Answer text') {
                $found = $window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition) |
                    Where-Object { $_.Current.ClassName -match '^WindowsForms10\.EDIT' } | Select-Object -First 1
            }
            if (-not $found) { throw "Control missing: $name; displayed: $(($window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition).Current.Name) -join ', ')" }
            $found
        }
        function Click($window, $name) {
            $control = Control $window $name
            if ($control.Current.NativeWindowHandle) {
                [void][SddDecisionTestWin]::PostMessage([IntPtr]$control.Current.NativeWindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
                Start-Sleep -Milliseconds 200
                return
            }
            $pattern = $null
            if ($control.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) { $pattern.Invoke() }
            elseif ($control.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) { $pattern.Select() }
            elseif ($control.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) { $pattern.Toggle() }
            else { throw "Control cannot be clicked: $name" }
            Start-Sleep -Milliseconds 200
        }
        function Is-Selected($window, $name) {
            $control = Control $window $name
            if ($control.Current.NativeWindowHandle) {
                return [SddDecisionTestWin]::IsChecked([IntPtr]$control.Current.NativeWindowHandle)
            }
            ([Windows.Automation.SelectionItemPattern]$control.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)).Current.IsSelected
        }
        foreach ($mode in 'submit', 'cancel', 'close') {
            $outputFile = "$temp\$mode.json"
            $process = Start-Process powershell.exe -ArgumentList "-NoProfile -STA -File `"$entry`" -Request `"$temp\request.json`"" -RedirectStandardOutput $outputFile -RedirectStandardError "$temp\$mode.error" -PassThru
            $null = $process.Handle
            $started += $process
            $window = Find-OwnWindow $process
            Assert ([bool]$window) 'actual native Windows modal wizard displayed (not Copilot Chat)'
            if ($mode -eq 'cancel') { Click $window Cancel }
            elseif ($mode -eq 'close') { ([Windows.Automation.WindowPattern]$window.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern)).Close() }
            else {
                Assert (Is-Selected $window 'First (Recommended)') 'radio recommendation is visibly preselected'
                Click $window Second
                Click $window Next
                Click $window Second
                Click $window Next
                Click $window 'Custom Answer'
                $text = Control $window 'Custom Answer text'
                [void][SddDecisionTestWin]::SendMessage([IntPtr]$text.Current.NativeWindowHandle, 0x000C, [IntPtr]::Zero, 'feature/custom')
                $text.SetFocus()
                [void][SddDecisionTestWin]::PostMessage([IntPtr]$text.Current.NativeWindowHandle, 0x0100, [IntPtr]0x0D, [IntPtr]::Zero)   # Enter down/up in the text box
                [void][SddDecisionTestWin]::PostMessage([IntPtr]$text.Current.NativeWindowHandle, 0x0101, [IntPtr]0x0D, [IntPtr]::Zero)
                Start-Sleep -Milliseconds 300
                $approvalShown = $window.FindFirst([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty, 'Approve'))
                Assert (-not $approvalShown) 'Enter while typing a Custom Answer does not press Next'
                Click $window Next
                Assert (-not (Is-Selected $window Approve)) 'actual approval radio is not selected'
                Click $window Next
                Assert ([bool](Control $window Approve)) 'Next without approval selection stays on the approval page'
                Click $window Reject
                Click $window Next
                Click $window Previous
                Assert (Is-Selected $window Reject) 'Previous navigation preserves the actual answer'
                Click $window Next
                Click $window Submit
            }
            if (-not $process.WaitForExit(30000)) { throw 'Interaction did not return after submit/cancel.' }
            $result = [IO.File]::ReadAllText($outputFile) | ConvertFrom-Json
            if ($process.ExitCode -ne 0 -or $result.taskId -ne $data.taskId -or $result.mechanism -ne 'WINDOWS_MODAL_NOT_COPILOT_CHAT') {
                throw "Interaction result failed (exit $($process.ExitCode)): $([IO.File]::ReadAllText($outputFile)); $([IO.File]::ReadAllText("$temp\$mode.error"))"
            }
            Assert $true 'selected values return to the same task and automation continues'
            if ($mode -eq 'submit') {
                Assert ($result.status -eq 'SUBMITTED' -and $result.selections[0].values -eq 'second' -and $result.selections[1].values.Count -eq 2 -and $result.selections[2].custom -eq 'feature/custom' -and $result.selections[3].values -eq 'reject' -and $result.selections[4].values -eq 'resume') 'all five pages return exact single/multiple/custom/approval/PBI answers'
            } else {
                Assert ($result.status -eq 'CANCELLED' -and $result.selections.Count -eq 0) 'Cancel/close returns no partial selections or approval'
            }
        }
    }
    Write-Output "Interaction regression: $passes passed, 0 failed; GUI=$Gui. Native Visual Studio Chat rendering NOT VERIFIED."
} finally {
    foreach ($process in $started) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
        $process.WaitForExit()
        $process.Dispose()
    }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
