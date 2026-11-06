param([string]$Analyzer)
$ErrorActionPreference = 'Stop'
if (-not $Analyzer) { $Analyzer = Join-Path (Split-Path $PSScriptRoot) 'copilot\modules\analyzers\architecture\Akzo.ArchitectureAnalyzer.dll' }
$temp = Join-Path ([IO.Path]::GetTempPath()) "sdd-semantic-$([guid]::NewGuid().ToString('N'))"
$clock = [Diagnostics.Stopwatch]::StartNew()
function Put($file, $text) {
    $full = Join-Path $temp $file
    New-Item -ItemType Directory -Path (Split-Path $full) -Force | Out-Null
    [IO.File]::WriteAllText($full, $text)
}
function Assert($value, $message) { if (-not $value) { throw $message }; Write-Output "PASS $message" }
function Analyze($cache) {
    $raw = & dotnet $Analyzer scan --root "$temp\workspace" --out (Join-Path $temp $cache)
    if ($LASTEXITCODE) { throw "$raw" }
    ($raw -join "`n") | ConvertFrom-Json
}
try {
    $major = ([version]((& dotnet --version) -replace '-.*$', '')).Major
    $project = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net' + $major + '.0</TargetFramework></PropertyGroup>{0}</Project>'
    Put 'workspace\Library\Library.csproj' ($project -f '')
    Put 'workspace\Consumer\Consumer.csproj' ($project -f '<ItemGroup><ProjectReference Include="..\Library\Library.csproj" /></ItemGroup>')
    Put 'workspace\Library\Service.cs' 'namespace Fixture; public class Service { public int Run(int value) => value; }'
    Put 'workspace\Consumer\Consumer.cs' 'namespace Fixture; public class Consumer { public int Use() => new Service().Run(1); }'
    Put 'workspace\NuGet.Config' '<configuration><packageSources><clear /></packageSources></configuration>'
    & dotnet build "$temp\workspace\Consumer\Consumer.csproj" --nologo --configfile "$temp\workspace\NuGet.Config" | Out-Host
    if ($LASTEXITCODE) { throw 'Fixture build failed.' }
    $cold = Analyze 'cache'
    $warm = Analyze 'cache'
    Assert ($cold.coverage.semantic -eq 2 -and $warm.status -eq 'UP_TO_DATE') 'cold semantic coverage and unchanged warm cache'
    Put 'workspace\Library\Service.cs' 'namespace Fixture; public class Service { public int Run(long value) => (int)value; }'
    $incremental = Analyze 'cache'
    $fresh = Analyze 'fresh'
    $ix = [IO.File]::ReadAllText("$temp\cache\index.json") | ConvertFrom-Json
    $freshIx = [IO.File]::ReadAllText("$temp\fresh\index.json") | ConvertFrom-Json
    $edge = @($ix.documents | Where-Object { $_.path -eq 'Consumer/Consumer.cs' })[0].calls.to
    $freshEdge = @($freshIx.documents | Where-Object { $_.path -eq 'Consumer/Consumer.cs' })[0].calls.to
    Assert (($edge -join ';') -eq ($freshEdge -join ';') -and ($edge -join ';') -match 'Run\(System.Int64\)' -and $incremental.revalidatedDocuments -eq 2) 'signature changes rebind unchanged transitive consumers'
    Put 'workspace\Library\Service.cs' 'namespace Fixture; public class Service { public int Run(long value) { return (int)value + 1; } }'
    $bodyOnly = Analyze 'cache'
    $bodyIx = [IO.File]::ReadAllText("$temp\cache\index.json") | ConvertFrom-Json
    $bodyEdge = @($bodyIx.documents | Where-Object { $_.path -eq 'Consumer/Consumer.cs' })[0].calls.to
    Assert ($bodyOnly.bodyOnlyDocuments -eq 1 -and $bodyOnly.revalidatedDocuments -eq 1 -and @($bodyOnly.affectedProjects).Count -eq 1 -and ($bodyEdge -join ';') -eq ($freshEdge -join ';')) 'a body-only edit (arrow to block body) reloads only its project and keeps the dependent bindings'
    Put 'workspace\Library\Registration.cs' @'
using System;
using System.Reflection;
namespace Fixture
{
    public interface IHandler<T> { }
    public class CatalogHandler : IHandler<int> { }
    public class CatalogMapper { }
    public class Selector
    {
        public Selector AssignableTo(Type type) => this;
        public Selector Where(Func<Type, bool> predicate) => this;
    }
    public class Builder
    {
        public Builder FromAssemblies(params Assembly[] assemblies) => this;
        public Builder AddClasses(Func<Selector, Selector> select) => this;
        public Builder AsImplementedInterfaces() => this;
        public Builder AsSelf() => this;
        public Builder WithScopedLifetime() => this;
    }
    public class Registration
    {
        public void Add()
        {
            var assembly = typeof(CatalogHandler).Assembly;
            new Builder().FromAssemblies(assembly)
                .AddClasses(c => c.AssignableTo(typeof(IHandler<>)).Where(t => t.Name.EndsWith("Handler")))
                .AsImplementedInterfaces().WithScopedLifetime();
            new Builder().FromAssemblies(assembly)
                .AddClasses(c => c.Where(t => t.Name.EndsWith("Mapper")))
                .AsSelf().WithScopedLifetime();
            new Builder().FromAssemblies(assembly)
                .AddClasses(c => c.Where(t => t.Name.EndsWith("Handler") && t.Namespace == "Unknown"))
                .AsSelf().WithScopedLifetime();
        }
    }
}
'@
    $registrations = Analyze 'cache'
    $regIx = [IO.File]::ReadAllText("$temp\cache\index.json") | ConvertFrom-Json
    $regs = @($regIx.documents | Where-Object { $_.path -eq 'Library/Registration.cs' })[0]
    Assert (@($regs.registrations).Count -eq 2 -and (@($regs.registrations.implementation) -join ';') -match 'CatalogHandler@Library' -and (@($regs.registrations.service) -join ';') -match 'CatalogMapper@Library' -and $regs.unresolved.Count -eq 1) 'assembly scanning resolves generic interfaces and AsSelf, but reports unsupported predicates'
    Put 'workspace\Library\Validation.cs' @'
using System;
using System.Threading.Tasks;
using FluentValidation;
namespace FluentValidation
{
    public class ValidationResult { }
    public interface IValidator<T> { ValidationResult Validate(T instance); }
    public interface IRuleBuilder<T, P> { }
    public abstract class AbstractValidator<T> : IValidator<T> { public ValidationResult Validate(T instance) => new ValidationResult(); protected IRuleBuilder<T, P> RuleFor<P>(Func<T, P> f) => null; }
    public static class RuleExtensions { public static IRuleBuilder<T, P> MustAsync<T, P>(this IRuleBuilder<T, P> b, Func<P, Task<bool>> f) => b; }
}
namespace Fixture
{
    public class Order { public string Code { get; set; } }
    public class OrderValidator : FluentValidation.AbstractValidator<Order> { public OrderValidator() { RuleFor(o => o.Code).MustAsync(c => Task.FromResult(c != null)); } }
    public class Checkout { public void Run(FluentValidation.IValidator<Order> v, Order o) => v.Validate(o); }
}
'@
    $null = Analyze 'cache'
    $fvIx = [IO.File]::ReadAllText("$temp\cache\index.json") | ConvertFrom-Json
    $risk = @($fvIx.patterns | Where-Object { $_.name -like 'FluentValidation risk*' })[0]
    $riskEvidence = @($risk.evidence) -join ';'
    $riskOk = $risk.observed -and $riskEvidence -match 'Validation\.cs:\d+ Validate ' -and $riskEvidence -match 'Validation\.cs:\d+ MustAsync '
    $validationDetails = @($fvIx.documents | ForEach-Object { "$($_.path) [$($_.analysis)]: $(@($_.validation | ForEach-Object { "$($_.kind):$($_.method):$($_.model):$($_.line)" }) -join ',')" }) -join '; '
    $projectDetails = @($fvIx.projects | ForEach-Object { "$($_.path) [$($_.analysis), errors=$($_.compilationErrors)]: $(@($_.compilationDiagnostics) -join ',')" }) -join '; '
    Assert $riskOk "FluentValidation: an async rule reached through a synchronous Validate call is reported at both locations; observed=$($risk.observed); evidence=$riskEvidence; validation=$validationDetails; projects=$projectDetails"
    Remove-Item -LiteralPath "$temp\workspace\Library\Service.cs"
    $removed = Analyze 'cache'
    $removedIx = [IO.File]::ReadAllText("$temp\cache\index.json") | ConvertFrom-Json
    Assert ($removed.removedDocuments -eq 1 -and -not @($removedIx.documents.calls | Where-Object { $_.to -like 'M:Fixture.Service.Run(System.Int64)*' }).Count) 'removed declarations invalidate consumer edges'
    [pscustomobject]@{ coldMs = $cold.elapsedMs; warmMs = $warm.elapsedMs; incrementalMs = $incremental.elapsedMs; freshMs = $fresh.elapsedMs; totalMs = $clock.ElapsedMilliseconds } | ConvertTo-Json -Compress
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
