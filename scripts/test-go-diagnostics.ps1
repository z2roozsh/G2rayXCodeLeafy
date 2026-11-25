#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$GoPath = "go",
    [string]$CompilerPath = "gcc"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$goExecutable = (Get-Command $GoPath -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$compilerExecutable = (Get-Command $CompilerPath -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$compilerDirectory = Split-Path -Parent $compilerExecutable
$root = Split-Path -Parent $PSScriptRoot
$environmentNames = @(
    "PATH", "CC", "CGO_ENABLED", "GOOS", "GOARCH", "GOFLAGS", "GOWORK",
    "GOTOOLCHAIN", "GOPROXY", "GOSUMDB", "CGO_CFLAGS", "CGO_CPPFLAGS",
    "CGO_CXXFLAGS", "CGO_LDFLAGS"
)
$previous = @{}
foreach ($name in $environmentNames) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

$exitCode = 1
$pushed = $false
try {
    Push-Location -LiteralPath $root
    $pushed = $true
    # GCC invokes helpers outside bin; their DLLs must come from this toolchain.
    $env:PATH = $compilerDirectory + [IO.Path]::PathSeparator + $previous["PATH"]
    # Resolve by basename after prepending PATH, including paths with spaces.
    $env:CC = Split-Path -Leaf $compilerExecutable
    $env:CGO_ENABLED = "1"
    $env:GOTOOLCHAIN = "local"
    $env:GOPROXY = "off"
    $env:GOSUMDB = "off"
    $env:GOWORK = "off"
    foreach ($name in @("GOOS", "GOARCH", "GOFLAGS", "CGO_CFLAGS", "CGO_CPPFLAGS", "CGO_CXXFLAGS", "CGO_LDFLAGS")) {
        if (Test-Path -LiteralPath ("Env:" + $name)) {
            Remove-Item -LiteralPath ("Env:" + $name)
        }
    }

    $hostJson = & $goExecutable env -json GOHOSTOS GOHOSTARCH
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Error "Could not query the local Go host toolchain (exit $exitCode)." -ErrorAction Continue
    } else {
        $goHost = ($hostJson -join [Environment]::NewLine) | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($goHost.GOHOSTOS) -or [string]::IsNullOrWhiteSpace($goHost.GOHOSTARCH)) {
            throw "Go did not report a native host OS and architecture."
        }
        $env:GOOS = $goHost.GOHOSTOS
        $env:GOARCH = $goHost.GOHOSTARCH
        & $goExecutable test -race -count=1 -timeout=120s -v `
            (Join-Path $root "tests/xray_retained_http_check.go") `
            (Join-Path $root "tests/xray_retained_http_check_test.go")
        $exitCode = $LASTEXITCODE
    }
} finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $previous[$name]) {
            if (Test-Path -LiteralPath ("Env:" + $name)) {
                Remove-Item -LiteralPath ("Env:" + $name)
            }
        } else {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process")
        }
    }
    if ($pushed) { Pop-Location }
}
exit $exitCode
