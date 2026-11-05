param([Parameter(Mandatory = $true)][string]$Request, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'

function Read-DecisionRequest([string]$path) {
    $requestData = [IO.File]::ReadAllText([IO.Path]::GetFullPath($path)) | ConvertFrom-Json
    if (-not ($requestData.taskId -is [string]) -or -not $requestData.taskId.Trim()) { throw 'A nonempty taskId is required.' }
    $questions = @($requestData.questions)
    if (-not $questions.Count -or $questions.Count -gt 12) { throw 'Provide one to twelve questions.' }
    $ids = @{}
    foreach ($q in $questions) {
        if (-not ($q.id -is [string]) -or -not $q.id.Trim() -or $ids.ContainsKey($q.id)) { throw 'Question IDs must be nonempty and unique.' }
        $ids[$q.id] = $true
        if (-not ($q.title -is [string]) -or -not $q.title.Trim() -or $q.kind -notin 'single', 'multiple') { throw "Invalid title or kind for $($q.id)." }
        if (-not ($q.approval -is [bool]) -or -not ($q.allowCustom -is [bool])) { throw "approval and allowCustom must be booleans for $($q.id)." }
        if ($q.approval -and $q.kind -ne 'single') { throw 'Approval questions must be single choice.' }
        if ($null -ne $q.allowEmpty -and (-not ($q.allowEmpty -is [bool]) -or ($q.allowEmpty -and $q.kind -ne 'multiple'))) { throw "allowEmpty must be a boolean and applies only to multiple-choice questions ($($q.id))." }
        $options = @($q.options)
        if (-not $options.Count -or $options.Count -gt 20) { throw "Provide one to twenty options for $($q.id)." }
        $values = @{}
        foreach ($o in $options) {
            if (-not ($o.value -is [string]) -or -not $o.value.Trim() -or $values.ContainsKey($o.value) -or -not ($o.label -is [string]) -or -not $o.label.Trim()) { throw "Invalid or duplicate option in $($q.id)." }
            $values[$o.value] = $true
        }
        $recommended = @($q.recommended | Where-Object { $null -ne $_ })
        if (($q.kind -eq 'single' -and $recommended.Count -gt 1) -or @($recommended | Where-Object { -not ($_ -is [string]) -or -not $values.ContainsKey($_) }).Count -or @($recommended | Select-Object -Unique).Count -ne $recommended.Count) { throw "Invalid recommendation for $($q.id)." }
        if ($recommended.Count -and (-not ($q.reason -is [string]) -or -not $q.reason.Trim())) { throw "Recommendations need evidence/reason for $($q.id)." }
    }
    $requestData
}

function Get-InitialAnswer($question) {
    [pscustomobject]@{ values = @($question.recommended | Where-Object { $null -ne $_ -and -not $question.approval }); custom = '' }
}

function Assert-DecisionAnswer($question, $answer) {
    $values = @($answer.values)
    if (@($values | Where-Object { $_ -cnotin @($question.options.value) }).Count -or @($values | Select-Object -Unique).Count -ne $values.Count) { throw [ArgumentException]::new('Select only the displayed options.') }
    $custom = "$($answer.custom)".Trim()
    if ($custom -and -not $question.allowCustom) { throw [ArgumentException]::new('Custom answers are not enabled.') }
    $count = $values.Count + $(if ($custom) { 1 } else { 0 })
    $emptyAllowed = $question.kind -eq 'multiple' -and $question.allowEmpty -eq $true   # "none of these" is a valid answer only when the question says so
    if ((-not $count -and -not $emptyAllowed) -or ($question.kind -eq 'single' -and $count -ne 1)) { throw [ArgumentException]::new('Select an answer or enter a Custom Answer before continuing.') }
}

try {
    $data = Read-DecisionRequest $Request
    if ($ValidateOnly) {
        [pscustomobject]@{ status = 'VALID'; taskId = $data.taskId; questions = @($data.questions | ForEach-Object {
            [pscustomobject]@{ id = $_.id; initial = Get-InitialAnswer $_; approval = $_.approval }
        }) } | ConvertTo-Json -Depth 6 -Compress
        return
    }
    if (-not [Environment]::UserInteractive) { throw 'An interactive Windows desktop is required; use host input or numbered choices.' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run this modal fallback with powershell -NoProfile -STA -File.' }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $questions = @($data.questions)
    $answers = @($questions | ForEach-Object { Get-InitialAnswer $_ })
    $state = @{ index = 0; submitted = $false; options = @(); customControl = $null; customText = $null }
    $form = New-Object Windows.Forms.Form -Property @{ Text = 'SDD decision - Windows modal fallback'; Width = 740; Height = 620; MinimumSize = New-Object Drawing.Size(740, 620); StartPosition = 'CenterScreen' }
    $heading = New-Object Windows.Forms.Label -Property @{ Left = 16; Top = 14; Width = 690; Height = 58; Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold) }
    $reason = New-Object Windows.Forms.Label -Property @{ Left = 16; Top = 76; Width = 690; Height = 72 }
    $panel = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Left = 16; Top = 152; Width = 690; Height = 300; AutoScroll = $true; FlowDirection = 'TopDown'; WrapContents = $false }
    $errorLabel = New-Object Windows.Forms.Label -Property @{ Left = 16; Top = 460; Width = 690; Height = 42; ForeColor = [Drawing.Color]::DarkRed }
    $previous = New-Object Windows.Forms.Button -Property @{ Text = 'Previous'; Left = 16; Top = 520; Width = 110 }
    $next = New-Object Windows.Forms.Button -Property @{ Text = 'Next'; Left = 466; Top = 520; Width = 110 }
    $cancel = New-Object Windows.Forms.Button -Property @{ Text = 'Cancel'; Left = 596; Top = 520; Width = 110; DialogResult = 'Cancel' }
    $form.Controls.AddRange(@($heading, $reason, $panel, $errorLabel, $previous, $next, $cancel))
    $form.CancelButton = $cancel
    $form.AcceptButton = $next
    $save = {
        $values = @($state.options | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Tag })
        $answers[$state.index] = [pscustomobject]@{ values = $values; custom = $(if ($state.customControl -and $state.customControl.Checked) { $state.customText.Text.Trim() } else { '' }) }
    }
    $render = {
        $q = $questions[$state.index]; $answer = $answers[$state.index]
        foreach ($control in @($panel.Controls)) { $panel.Controls.Remove($control); $control.Dispose() }
        $state.options = @(); $state.customControl = $null; $state.customText = $null
        $heading.Text = "$($state.index + 1)/$($questions.Count) - $($q.title)"
        $reason.Text = $(if ($q.approval) { "Explicit approval required; nothing is preselected.`r`n" }) + $(if ($q.allowEmpty -eq $true) { "Selecting nothing is a valid answer.`r`n" }) + "$($q.reason)"
        $errorLabel.Text = ''
        foreach ($o in $q.options) {
            $type = if ($q.kind -eq 'single') { 'RadioButton' } else { 'CheckBox' }
            $label = $o.label + $(if ($o.value -cin @($q.recommended) -and -not $q.approval) { ' (Recommended)' })
            $control = New-Object "Windows.Forms.$type" -Property @{ Text = $label; Tag = $o.value; Width = 650; Height = 30; Checked = ($o.value -cin @($answer.values)) }
            $panel.Controls.Add($control)
            $state.options += $control
        }
        if ($q.allowCustom) {
            $type = if ($q.kind -eq 'single') { 'RadioButton' } else { 'CheckBox' }
            $state.customControl = New-Object "Windows.Forms.$type" -Property @{ Text = 'Custom Answer'; Width = 650; Height = 30; Checked = [bool]$answer.custom }
            $state.customText = New-Object Windows.Forms.TextBox -Property @{ Width = 650; Text = $answer.custom; Enabled = [bool]$answer.custom; AccessibleName = 'Custom Answer text' }
            $state.customControl.Add_CheckedChanged({ $state.customText.Enabled = $state.customControl.Checked })
            # Enter while typing a Custom Answer must not press Next/Submit: the default button is off while the text box has focus.
            $state.customText.Add_GotFocus({ $form.AcceptButton = $null })
            $state.customText.Add_LostFocus({ $form.AcceptButton = $next })
            $panel.Controls.AddRange(@($state.customControl, $state.customText))
        }
        $previous.Enabled = $state.index -gt 0
        $next.Text = if ($state.index -eq $questions.Count - 1) { 'Submit' } else { 'Next' }
    }
    $previous.Add_Click({ & $save; $state.index--; & $render })
    $next.Add_Click({
        & $save
        try { Assert-DecisionAnswer $questions[$state.index] $answers[$state.index] }
        catch [ArgumentException] { $errorLabel.Text = $_.Exception.Message; return }
        if ($state.index -lt $questions.Count - 1) { $state.index++; & $render }
        else {
            $state.submitted = $true
            $form.DialogResult = 'OK'
            $form.Close()
        }
    })
    & $render
    try { [void]$form.ShowDialog() } finally { $form.Dispose() }
    [pscustomobject]@{
        status = $(if ($state.submitted) { 'SUBMITTED' } else { 'CANCELLED' })
        mechanism = 'WINDOWS_MODAL_NOT_COPILOT_CHAT'; taskId = $data.taskId
        selections = @($(if ($state.submitted) { for ($i = 0; $i -lt $questions.Count; $i++) {
            [pscustomobject]@{ id = $questions[$i].id; values = @($answers[$i].values); custom = $answers[$i].custom }
        } }))
        note = 'Returned user input only; no action executed, no state saved, no approval authenticated.'
    } | ConvertTo-Json -Depth 6 -Compress
} catch {
    [pscustomobject]@{ status = 'ERROR'; error = $_.Exception.Message } | ConvertTo-Json -Compress
    exit 1
}
