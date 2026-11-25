#Requires -Version 7.0
param(
    [string]$Case,
    [string]$Runner,
    [string]$FixtureRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$global:G2RayFixtureCase = $Case
$global:G2RayFixtureCompiler = Join-Path $FixtureRoot "compiler with spaces/bin/gcc.exe"
$global:G2RayFixtureTrace = Join-Path $FixtureRoot "$Case.trace.jsonl"
$global:G2RayFixtureNames = @(
    "PATH", "CC", "CGO_ENABLED", "GOOS", "GOARCH", "GOFLAGS", "GOWORK",
    "GOTOOLCHAIN", "GOPROXY", "GOSUMDB", "CGO_CFLAGS", "CGO_CPPFLAGS",
    "CGO_CXXFLAGS", "CGO_LDFLAGS"
)

# Native command discovery and Go are mocked only in this fixture process.
function Get-Command {
    param($Name, $CommandType, $ErrorAction)
    if ($CommandType -ne "Application") { throw "Runner did not require a native application." }
    if ($Name -eq "fixture-go") {
        if ($global:G2RayFixtureCase -eq "missing_go") { throw "Fixture Go is missing." }
        [pscustomobject]@{ Source = "Invoke-FixtureGo" }
        if ($global:G2RayFixtureCase -eq "multiple_go") { [pscustomobject]@{ Source = "Do-Not-Run-Another-Go" } }
    } elseif ($Name -eq "fixture-gcc") {
        if ($global:G2RayFixtureCase -eq "missing_compiler") { throw "Fixture compiler is missing." }
        [pscustomobject]@{ Source = $global:G2RayFixtureCompiler }
        if ($global:G2RayFixtureCase -eq "multiple_compilers") { [pscustomobject]@{ Source = "Do-Not-Select-Another-Compiler" } }
    } else {
        throw "Unexpected command lookup: $Name"
    }
}

function Invoke-FixtureGo {
    $values = @{}
    foreach ($name in $global:G2RayFixtureNames) { $values[$name] = [Environment]::GetEnvironmentVariable($name, "Process") }
    $record = @{ args = @($args); environment = $values; directory = (Get-Location).Path }
    [IO.File]::AppendAllText($global:G2RayFixtureTrace, (($record | ConvertTo-Json -Depth 5 -Compress) + [Environment]::NewLine))
    $global:LASTEXITCODE = 0
    if ($args[0] -eq "env") {
        if ($global:G2RayFixtureCase -eq "host_failure") { $global:LASTEXITCODE = 7; return }
        if ($global:G2RayFixtureCase -eq "bad_json") { return "not-json" }
        if ($global:G2RayFixtureCase -eq "missing_host") { return '{"GOHOSTOS":"windows"}' }
        return '{"GOHOSTOS":"windows","GOHOSTARCH":"amd64"}'
    }
    if ($args[0] -ne "test") { throw "Unexpected Go operation." }
    if ($global:G2RayFixtureCase -eq "test_failure") { $global:LASTEXITCODE = 37 }
}

$env:CC = "original-compiler"
$env:CGO_ENABLED = "0"
$env:GOOS = "plan9"
$env:GOARCH = "386"
$env:GOFLAGS = "-tags=fixture"
$env:GOWORK = "original-workspace"
$env:GOTOOLCHAIN = "auto"
$env:GOPROXY = "https://invalid.fixture"
$env:GOSUMDB = "invalid.fixture"
foreach ($name in @("CGO_CFLAGS", "CGO_CPPFLAGS", "CGO_CXXFLAGS", "CGO_LDFLAGS")) {
    [Environment]::SetEnvironmentVariable($name, "original-flags", "Process")
}
if ($Case -eq "unset_environment") {
    foreach ($name in $global:G2RayFixtureNames) {
        if ($name -ne "PATH" -and (Test-Path -LiteralPath ("Env:" + $name))) {
            Remove-Item -LiteralPath ("Env:" + $name)
        }
    }
}
if ($Case -eq "empty_environment") {
    foreach ($name in $global:G2RayFixtureNames) {
        if ($name -ne "PATH") { [Environment]::SetEnvironmentVariable($name, "", "Process") }
    }
}
$before = @{}
foreach ($name in $global:G2RayFixtureNames) { $before[$name] = [Environment]::GetEnvironmentVariable($name, "Process") }
Push-Location -LiteralPath $FixtureRoot
try {
    $directory = (Get-Location).Path
    $caught = $false
    $caughtError = $null
    $code = 0
    try {
        & $Runner -GoPath fixture-go -CompilerPath fixture-gcc *> (Join-Path $FixtureRoot "$Case.output.log")
        $code = $LASTEXITCODE
    } catch {
        $caught = $true
        $caughtError = $_
    }
    foreach ($name in $global:G2RayFixtureNames) {
        if ([Environment]::GetEnvironmentVariable($name, "Process") -cne $before[$name]) {
            throw "Runner did not restore $name after $Case."
        }
    }
    if ((Get-Location).Path -cne $directory) { throw "Runner did not restore its directory." }
    $expectedThrow = $Case -in @("missing_go", "missing_compiler", "bad_json", "missing_host")
    if ($caught -ne $expectedThrow) { throw "Unexpected exception state for ${Case}: $caughtError" }
    $expectedCode = switch ($Case) { "test_failure" { 37 }; "host_failure" { 7 }; default { 0 } }
    if (-not $caught -and $code -ne $expectedCode) { throw "Runner changed exit $expectedCode to $code." }
    $records = @()
    if (Test-Path -LiteralPath $global:G2RayFixtureTrace) {
        $records = @(Get-Content -LiteralPath $global:G2RayFixtureTrace | ForEach-Object { $_ | ConvertFrom-Json })
    }
    $tests = @($records | Where-Object { $_.args[0] -eq "test" })
    $expectedTests = if ($expectedThrow -or $Case -eq "host_failure") { 0 } else { 1 }
    if ($tests.Count -ne $expectedTests) { throw "Unexpected Go test invocation count." }
    if ($tests.Count -eq 1) {
        $test = $tests[0]
        $prefix = (Split-Path -Parent $global:G2RayFixtureCompiler) + [IO.Path]::PathSeparator
        if ($test.environment.PATH -cne ($prefix + $before["PATH"]) -or $test.environment.CC -cne "gcc.exe") {
            throw "Compiler path ordering or paths with spaces are broken."
        }
        foreach ($setting in @{ CGO_ENABLED = "1"; GOTOOLCHAIN = "local"; GOPROXY = "off"; GOSUMDB = "off"; GOWORK = "off"; GOOS = "windows"; GOARCH = "amd64" }.GetEnumerator()) {
            if ($test.environment.($setting.Key) -cne $setting.Value) { throw "Unexpected $($setting.Key)." }
        }
        foreach ($name in @("GOFLAGS", "CGO_CFLAGS", "CGO_CPPFLAGS", "CGO_CXXFLAGS", "CGO_LDFLAGS")) {
            if (-not [string]::IsNullOrEmpty($test.environment.$name)) { throw "Inherited $name affected the test." }
        }
        $root = Split-Path -Parent (Split-Path -Parent $Runner)
        $expectedArgs = @("test", "-race", "-count=1", "-timeout=120s", "-v",
            (Join-Path $root "tests/xray_retained_http_check.go"),
            (Join-Path $root "tests/xray_retained_http_check_test.go"))
        if (($test.args | ConvertTo-Json -Compress) -cne ($expectedArgs | ConvertTo-Json -Compress)) {
            throw "Runner changed the race tests or their options."
        }
        if ($test.directory -cne $root) { throw "Tests did not run in the project root." }
    }
    Write-Output "PASS: Go diagnostic runner $Case; caller environment and directory restored"
} finally {
    Pop-Location
}
