[CmdletBinding()]
param(
    [string]$Version = "0.7.0-dev",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepoRoot ".local/dist/builds"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$StageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("petsgraph-windows-" + [Guid]::NewGuid().ToString("N"))
$PublishDirectory = Join-Path $StageRoot "PetsGraph"
$ZipPath = Join-Path $OutputDirectory "PetsGraph-v$Version-Windows-x64.zip"
$Fixture = Join-Path $RepoRoot "petpack/fixtures/synthetic-cat-v1.petpack"

if (Test-Path $ZipPath) {
    throw "Refusing to overwrite $ZipPath"
}

try {
    New-Item -ItemType Directory -Path $PublishDirectory -Force | Out-Null
    dotnet publish (Join-Path $RepoRoot "player/windows/src/PetsGraph.App/PetsGraph.App.csproj") `
        --configuration Release `
        --runtime win-x64 `
        --self-contained true `
        --no-restore `
        -p:PublishSingleFile=false `
        -p:NuGetAudit=false `
        -p:RestoreLockedMode=true `
        -p:Version=$Version `
        --output $PublishDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }

    Copy-Item (Join-Path $RepoRoot "player/windows/README-Windows.md") $PublishDirectory
    Set-Content -Path (Join-Path $PublishDirectory "VERSION.txt") -Value $Version -Encoding utf8NoBOM
    $Executable = Join-Path $PublishDirectory "PetsGraph.exe"
    & $Executable --validate-only $Fixture
    if ($LASTEXITCODE -ne 0) {
        throw "native PetPack validation failed with exit code $LASTEXITCODE"
    }
    if (Test-Path (Join-Path $PublishDirectory "Pets")) {
        throw "zero-pet Player must not contain a Pets directory"
    }
    if (Get-ChildItem -Path $PublishDirectory -Recurse -File -Filter "*.petpack") {
        throw "zero-pet Player must not contain PetPack media"
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    Compress-Archive -Path $PublishDirectory -DestinationPath $ZipPath -CompressionLevel Optimal
    $Hash = Get-FileHash -Path $ZipPath -Algorithm SHA256
    Write-Output "$($Hash.Hash.ToLowerInvariant())  $ZipPath"
}
finally {
    if (Test-Path $StageRoot) {
        Remove-Item -Path $StageRoot -Recurse -Force
    }
}
