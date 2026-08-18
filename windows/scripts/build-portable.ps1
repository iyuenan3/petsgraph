[CmdletBinding()]
param(
    [string]$Version = "0.6.0",
    [string]$OutputDirectory = "",
    [string]$PetsDirectory = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepoRoot "dist"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$StageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("petsgraph-windows-" + [Guid]::NewGuid().ToString("N"))
$PublishDirectory = Join-Path $StageRoot "PetsGraph"
$ZipPath = Join-Path $OutputDirectory "PetsGraph-v$Version-Windows-x64-runtime.zip"

if (Test-Path $ZipPath) {
    throw "Refusing to overwrite $ZipPath"
}

try {
    New-Item -ItemType Directory -Path $PublishDirectory -Force | Out-Null
    dotnet publish (Join-Path $RepoRoot "windows/src/PetsGraph.App/PetsGraph.App.csproj") `
        --configuration Release `
        --runtime win-x64 `
        --self-contained true `
        -p:PublishSingleFile=false `
        -p:RestoreLockedMode=true `
        -p:Version=$Version `
        --output $PublishDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }

    Copy-Item (Join-Path $RepoRoot "windows/README-Windows.md") $PublishDirectory
    Set-Content -Path (Join-Path $PublishDirectory "VERSION.txt") -Value $Version -Encoding utf8NoBOM

    if (-not [string]::IsNullOrWhiteSpace($PetsDirectory)) {
        $PetsDirectory = (Resolve-Path $PetsDirectory).Path
        $Packages = @(Get-ChildItem -Path $PetsDirectory -Directory -Filter "*.petsgraph-pet" | Sort-Object Name)
        if ($Packages.Count -lt 1) {
            throw "No .petsgraph-pet package found in $PetsDirectory"
        }
        $DestinationPets = Join-Path $PublishDirectory "Pets"
        New-Item -ItemType Directory -Path $DestinationPets | Out-Null
        foreach ($Package in $Packages) {
            Copy-Item -Path $Package.FullName -Destination $DestinationPets -Recurse
        }
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
