param(
    [string]$Root    = 'C:\Users\mazcr\trace.moe\hashes',
    [string]$SolrUrl = 'http://127.0.0.1:8983/solr/cl_0/update?wt=json&commit=true'
)

# Validate inputs
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Error "Root folder '$Root' not found."
    exit 1
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Error "curl.exe not found in PATH."
    exit 1
}

# Gather XML files
$files = Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.xml' -File
if ($files.Count -eq 0) {
    Write-Host "No XML files found under $Root. Nothing to do."
    exit 0
}

# Process each file
foreach ($item in $files) {
    $file     = $item.FullName
    $folderId = $item.Directory.Name
    $fileName = $item.Name
    Write-Host "Indexing id='$folderId', file_name='$fileName'"

    # Read entire XML
    $xmlRaw = Get-Content -LiteralPath $file -Raw

    # Inject <field name='file_name'> right after <doc>
    $xmlWithFile = $xmlRaw -replace '<doc>', "<doc><field name='file_name'>$fileName</field>"

    # Overwrite the id field
    $patched = [Regex]::Replace(
            $xmlWithFile,
            '<field name="id">.*?</field>',
            "<field name='id'>$folderId</field>"
    )

    # Write to a temp file
    $tmp = Join-Path $env:TEMP ("idx_{0}.xml" -f [GUID]::NewGuid().ToString())
    $patched | Out-File -LiteralPath $tmp -Encoding UTF8

    # POST to Solr
    & curl.exe -s -X POST -H "Content-Type: text/xml" --data-binary "@$tmp" $SolrUrl
    if ($LASTEXITCODE -eq 0) {
        Write-Host "�" "Indexed. Removing original."
        Remove-Item -LiteralPath $file -Force
    }
    else {
        Write-Warning "  ⚠ Index failed (exit code $LASTEXITCODE). Keeping file."
    }

    # Clean up temp file
    Remove-Item -LiteralPath $tmp -Force
}

# Final commit
Write-Host "Sending final commit..."
& curl.exe -s -X POST -H "Content-Type: application/json" --data '{"commit":{}}' $SolrUrl
Write-Host "Done."