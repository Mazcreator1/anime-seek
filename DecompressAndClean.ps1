param(
    [string]$Root     = 'C:\Users\mazcr\trace.moe\hashes',
    [string]$SevenZip = "${env:ProgramFiles}\7-Zip\7z.exe"
)

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Error "Root folder '$Root' does not exist."
    exit 1
}
if (-not (Test-Path -LiteralPath $SevenZip -PathType Leaf)) {
    Write-Error "7z.exe not found at '$SevenZip'."
    exit 1
}

Get-ChildItem -Path $Root -Recurse -Filter '*.xz' | ForEach-Object {
    $src  = $_.FullName
    # strip off the .xz suffix for the destination
    $dest = [IO.Path]::ChangeExtension($src, $null)

    Write-Host "Decompressing:" 
    Write-Host "  $src" 
    Write-Host "→ $dest"

    # decompress to the dest file, forcing literal paths
    & "$SevenZip" e -so -- "$src" |
      Set-Content -LiteralPath $dest -Encoding UTF8

    # only delete the .xz if the dest exists and is non-empty
    if ((Test-Path -LiteralPath $dest -PathType Leaf) -and
        ((Get-Item -LiteralPath $dest).Length -gt 0)) {
        Write-Host "  ✔ Removing original: $($_.Name)"
        Remove-Item  -LiteralPath $src -Force
    }
    else {
        Write-Warning "  ⚠️ Decompressed file missing or empty; keeping $($_.Name)"
    }
}

Write-Host "`n✅ All done."
