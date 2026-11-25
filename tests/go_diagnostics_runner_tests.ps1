#Requires -Version 7.0

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$pwsh = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$root = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $root "scripts/test-go-diagnostics.ps1"
$fixture = Join-Path $PSScriptRoot "fixtures/go-diagnostics-runner.ps1"
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp = Join-Path $tempBase ("g2ray-go-runner-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $cases = @("success", "test_failure", "host_failure", "missing_go", "missing_compiler",
        "bad_json", "missing_host", "multiple_go", "multiple_compilers", "unset_environment", "empty_environment")
    foreach ($case in $cases) {
        $output = Join-Path $temp "$case.fixture.log"
        & $pwsh -NoLogo -NoProfile -NonInteractive -File $fixture -Case $case -Runner $runner -FixtureRoot $temp *> $output
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $output
            throw "Go diagnostic runner fixture failed: $case"
        }
        Get-Content -LiteralPath $output
    }
    Write-Output "PASS: all $($cases.Count) Go diagnostic runner fixtures"
} finally {
    $resolved = [IO.Path]::GetFullPath($temp)
    $prefix = $tempBase.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $resolved.StartsWith($prefix, $comparison) -or
        -not (Split-Path -Leaf $resolved).StartsWith("g2ray-go-runner-") -or
        ((Get-Item -LiteralPath $resolved).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing cleanup outside the owned non-junction fixture directory."
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
