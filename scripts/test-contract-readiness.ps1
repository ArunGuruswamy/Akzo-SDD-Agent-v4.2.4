param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$helper = Join-Path $root 'copilot\modules\investigate\scripts\akzo.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) "sdd-contract-$([guid]::NewGuid().ToString('N'))"
$savedHome = $env:AKZO_AGENT_HOME
$passes = 0
function Assert($value, $message) {
    if (-not $value) { throw $message }
    $script:passes++
    Write-Output "PASS $message"
}
function Put($path, $text) {
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $text)
}
function Run([string[]]$arguments) {
    $ErrorActionPreference = 'Continue'
    $output = & powershell -NoProfile -File $helper @arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code) { throw $output }
    $output | ConvertFrom-Json
}
try {
    $env:AKZO_AGENT_HOME = Join-Path $temp 'state'
    $repo = Join-Path $temp 'renamed-backend'
    Put "$repo\schema.graphqls" "type Query {`n  record(id: ID!): Record`n}`ninput RecordInput {`n  name: String!`n}`ntype Record {`n  id: ID!`n}"
    [IO.File]::AppendAllText("$repo\schema.graphqls", "`n#" + ('x' * 1MB))
    Put "$repo\operations\lookup.graphql" "query LookupRecord(`$id: ID!) {`n  record(id: `$id) { ...RecordFields }`n}"
    Put "$repo\operations\fields.gql" "fragment RecordFields on Record {`n  id`n}"
    Put "$repo\src\RecordValidator.cs" "public class RecordValidator : AbstractValidator<RecordInput>`n{`n}"
    & git -C $repo init --quiet --initial-branch=fixture
    if ($LASTEXITCODE) { throw 'Fixture Git initialization failed.' }
    Put "$env:AKZO_AGENT_HOME\repos.json" ([pscustomobject]@{ version = 1; repos = @([pscustomobject]@{ id = 'fixture'; path = $repo }) } | ConvertTo-Json -Depth 4)
    $initial = Run @('context', '-Repo', 'fixture', '-Query', 'LookupRecord')
    $symbols = [IO.File]::ReadAllText("$env:AKZO_AGENT_HOME\maps\fixture\symbols.tsv")
    Assert ($symbols -match "graphql-operation`tLookupRecord" -and $symbols -match "graphql-fragment`tRecordFields" -and $symbols -match "graphql-type`tRecordInput") 'schema types over 1MB, fragments and operations have indexed source locations'
    Assert (($initial | ConvertTo-Json -Depth 10 -Compress).Length -lt 24000) 'contract retrieval stays bounded instead of returning the entire large schema'
    $warm = Run @('context', '-Repo', 'fixture', '-Query', 'RecordInput')
    Assert ($warm.memory.event -eq 'hit' -and $warm.memory.symbolsParsed -eq 0) 'unchanged contract evidence reuses the repository index'
    $gql = Run @('graphql', '-Repo', 'fixture', '-Query', 'RecordInput')
    Assert ($gql.status -eq 'VALID' -and $gql.errorCount -eq 0 -and (@(@($gql.scopes)[0].operations) -contains 'query LookupRecord') -and (@(@($gql.scopes)[0].context.types.name) -contains 'RecordInput')) 'mechanical GraphQL validation accepts the operation and fragment that match the schema and returns only the named schema context'
    $gqlWarm = Run @('graphql', '-Repo', 'fixture')
    Assert (@($gqlWarm.scopes)[0].cached -eq $true -and $gqlWarm.errorCount -eq 0) 'an unchanged GraphQL scope reuses its cached validation'
    Put "$repo\schema.graphqls" "type Query { record(id: ID!): Record }`ninput UpdatedRecordInput { name: String! }"
    $changed = Run @('context', '-Repo', 'fixture', '-Query', 'UpdatedRecordInput')
    $symbols = [IO.File]::ReadAllText("$env:AKZO_AGENT_HOME\maps\fixture\symbols.tsv")
    Assert ($changed.memory.symbolsParsed -eq 1 -and $symbols -match "graphql-type`tUpdatedRecordInput" -and $symbols -notmatch "graphql-type`tRecordInput\b") 'changed schema invalidates only its declaration rows'
    $broken = Run @('graphql', '-Repo', 'fixture')
    Assert ($broken.status -eq 'INVALID' -and @($broken.scopes)[0].cached -eq $false -and (@(@($broken.scopes)[0].errors | ForEach-Object { "$($_.at) $($_.message)" }) -join ' ') -match "schema\.graphqls:1 .*undefined type 'Record'") 'a changed schema is revalidated and the undefined type is reported at its file and line'

    $taskDir = "$env:AKZO_AGENT_HOME\tasks\fixture\CHECK1"
    Put "$taskDir\refined-pbi.md" "# CHECK1 Contract readiness`nAC1: validate input before the business operation."
    $task = Run @('task', '-Repo', 'fixture', '-Id', 'CHECK1')
    Assert ($task.implementationReadiness.status -eq 'BLOCKED') 'unfilled plan readiness is blocked'
    Assert ($task.implementationReadiness.checks -match 'GraphQL schema: PENDING' -and $task.implementationReadiness.checks -match 'Architecture compliance: PENDING' -and $task.implementationReadiness.blockerCount -eq 12 -and ($task.implementationReadiness | ConvertTo-Json -Compress).Length -lt 500) 'task readiness summarizes all checks and blocker count without repeating plan evidence'
    Put $task.spec "Gap map: Approved (by fixture)`nStatus: Approved (by fixture)"
    $prefix = "Status: Draft`n`n## 1b. Contract and validation readiness`n"
    $rows = @(
        '| GraphQL schema | VERIFIED | schema.graphqls:1 | |',
        '| GraphQL operations | NEW OPERATION PLANNED | operations/lookup.graphql:1 | T1 |',
        '| Generated client | REGENERATION PLANNED | existing generation command documented in project configuration | T1 |',
        '| FluentValidation | NEW VALIDATOR PLANNED | src/RecordValidator.cs:1 | T2 |',
        '| Validator execution | EXPLICIT IMPLEMENTATION TASK | existing request pipeline at src/Pipeline.cs:8 | T2 |',
        '| Architecture compliance | VERIFIED | source and selected project dependencies reviewed | |'
    )
    $tasks = "`n## 2. Tasks`n| T1 | Generate client | REQ-1 | Not Started |`n| T2 | Wire and test validator | REQ-1 | Not Started |"
    $valid = $prefix + ($rows -join "`n") + $tasks
    foreach ($case in @(
        @{ name = 'material schema incompatibility'; text = $valid.Replace('| GraphQL schema | VERIFIED |', '| GraphQL schema | INCOMPATIBLE |') },
        @{ name = 'missing evidence'; text = $valid.Replace('schema.graphqls:1', '') },
        @{ name = 'placeholder evidence'; text = $valid.Replace('schema.graphqls:1', '<schema evidence>') },
        @{ name = 'unknown planned task'; text = $valid.Replace('| T1 |', '| T99 |').Replace('| T99 | Generate client', '| T1 | Generate client') },
        @{ name = 'missing readiness row'; text = $valid.Replace($rows[4], '') },
        @{ name = 'duplicate readiness row'; text = $prefix + ($rows -join "`n") + "`n$($rows[0])" + $tasks },
        @{ name = 'inconsistent GraphQL applicability'; text = $valid.Replace('| GraphQL operations | NEW OPERATION PLANNED | operations/lookup.graphql:1 | T1 |', '| GraphQL operations | NOT APPLICABLE | REST only | |') },
        @{ name = 'unresolved client blocker'; text = $valid.Replace('| Generated client | REGENERATION PLANNED |', '| Generated client | COMPATIBLE |').Replace('configuration | T1 |', 'configuration | incompatible output |') }
    )) {
        Put $task.plan $case.text
        $before = (Get-FileHash -LiteralPath $task.plan).Hash
        $decision = Run @('decide', '-Repo', 'fixture', '-Id', 'CHECK1', '-Gate', 'G4', '-Decision', 'approve')
        Assert ($decision.status -eq 'READINESS_BLOCKED' -and @($decision.readiness.blockers).Count -gt 0 -and @($decision.readiness.checks).Count -gt 0 -and (Get-FileHash -LiteralPath $task.plan).Hash -eq $before -and -not (Test-Path "$taskDir\approvals.jsonl")) "approval refuses $($case.name) with detailed errors and without changing the plan or approval log"
    }
    Put $task.plan $valid
    $ready = Run @('task', '-Repo', 'fixture', '-Id', 'CHECK1')
    Assert ($ready.implementationReadiness.status -eq 'READY_FOR_APPROVAL' -and $ready.implementationReadiness.approval -eq 'REQUIRED') 'verified evidence and real planned task references permit asking for approval, not automatic writes'
    $before = (Get-FileHash -LiteralPath $task.plan).Hash
    $decision = Run @('decide', '-Repo', 'fixture', '-Id', 'CHECK1', '-Gate', 'G4', '-Decision', 'approve')
    Assert ($decision.status -eq 'GRAPHQL_BLOCKED' -and (@($decision.blockers) -join ' ') -match "undefined type 'Record'" -and (Get-FileHash -LiteralPath $task.plan).Hash -eq $before -and -not (Test-Path "$taskDir\approvals.jsonl")) 'a plan marked GraphQL VERIFIED is refused while the repository operations do not match its schema; nothing is recorded'
    Put "$repo\schema.graphqls" "type Query {`n  record(id: ID!): Record`n}`ninput RecordInput {`n  name: String!`n}`ntype Record {`n  id: ID!`n}"
    $decision = Run @('decide', '-Repo', 'fixture', '-Id', 'CHECK1', '-Gate', 'G4', '-Decision', 'approve')
    Assert ($decision.status -eq 'RECORDED' -and $decision.newStatus -like 'Approved*' -and $decision.graphql.status -eq 'VALID') 'explicit valid plan decision is recorded after the mechanical GraphQL check passes'
    Put $task.plan ($valid.Replace('Status: Draft', 'Status: Waived (Auto Mode, authorized by fixture)'))
    $resume = Run @('task', '-Repo', 'fixture', '-Id', 'CHECK1')
    Assert ($resume.nextGate.id -eq 'G4') 'legacy Auto Mode waiver still requires concrete plan approval'
    $rest = $prefix + (@(
        '| GraphQL schema | NOT APPLICABLE | REST-only contracts | |',
        '| GraphQL operations | NOT APPLICABLE | REST-only contracts | |',
        '| Generated client | NOT APPLICABLE | no generated GraphQL client | |',
        '| FluentValidation | EXISTING RULES REUSED | src/RecordValidator.cs:1 | |',
        '| Validator execution | VERIFIED | existing awaited pipeline and DI test | |',
        '| Architecture compliance | VERIFIED | selected project dependencies reviewed | |'
    ) -join "`n")
    Put $task.plan $rest
    $restTask = Run @('task', '-Repo', 'fixture', '-Id', 'CHECK1')
    Assert ($restTask.implementationReadiness.status -eq 'READY_FOR_APPROVAL') 'REST and existing FluentValidation do not require GraphQL'
    Put $task.plan ($rest.Replace('| FluentValidation | EXISTING RULES REUSED | src/RecordValidator.cs:1 | |', '| FluentValidation | NOT APPLICABLE | frontend reactive-form validation only | |'))
    $frontend = Run @('task', '-Repo', 'fixture', '-Id', 'CHECK1')
    Assert ($frontend.implementationReadiness.status -eq 'READY_FOR_APPROVAL') 'non-.NET validation does not require introducing FluentValidation'
    Write-Output "Contract readiness regression: $passes passed, 0 failed. GraphQL validation is mechanical on fixtures; real application schemas are NOT VERIFIED here."
} finally {
    $env:AKZO_AGENT_HOME = $savedHome
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
