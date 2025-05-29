# TraceMoeSearch.ps1
param(
    [Parameter(Mandatory=$true)]
    [string]$ImagePath
)

# Helpers
function Throw-HttpError($req, $resp) {
    $body = ""
    try { $body = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd() } catch {}
    throw "HTTP $($resp.StatusCode) $($resp.StatusDescription)`n$body"
}

# Read the file
if (-not (Test-Path $ImagePath)) {
    throw "File not found: $ImagePath"
}
$fileName = [System.IO.Path]::GetFileName($ImagePath)
$fileBytes = [System.IO.File]::ReadAllBytes($ImagePath)

# Build multipart body
$boundary = [System.Guid]::NewGuid().ToString()
$lf = "`r`n"
$header = "--$boundary$lf" +
        'Content-Disposition: form-data; name="image"; filename="' + $fileName + '"' + $lf +
        "Content-Type: application/octet-stream$lf$lf"
$footer = "$lf--$boundary--$lf"

$encoding = [System.Text.Encoding]::UTF8
$headerBytes = $encoding.GetBytes($header)
$footerBytes = $encoding.GetBytes($footer)

# Total length
$totalLength = $headerBytes.Length + $fileBytes.Length + $footerBytes.Length

# Create request
$url = "https://api.trace.moe/search?anilistInfo=true"
$req = [System.Net.HttpWebRequest]::Create($url)
$req.Method        = "POST"
$req.AllowAutoRedirect = $true
$req.KeepAlive     = $false
$req.ProtocolVersion = [System.Net.HttpVersion]::Version11
$req.ContentType   = "multipart/form-data; boundary=$boundary"
$req.ContentLength = $totalLength
$req.UserAgent     = "PowerShell/$(($PSVersionTable.PSVersion).ToString())"

# Write body
$stream = $req.GetRequestStream()
try {
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    $stream.Write($fileBytes,   0, $fileBytes.Length)
    $stream.Write($footerBytes, 0, $footerBytes.Length)
}
finally { $stream.Close() }

# Send & receive
try {
    $resp = $req.GetResponse()
}
catch [System.Net.WebException] {
    if ($_.Response) {
        Throw-HttpError $req ($_.Response)
    } else {
        throw $_
    }
}

# Read JSON
$reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
$json = $reader.ReadToEnd()
$reader.Close()
$resp.Close()

# Parse
$obj = $json | ConvertFrom-Json
if ($obj.error) {
    throw "API error: $($obj.error)"
}
if (-not $obj.result -or $obj.result.Count -eq 0) {
    Write-Host "No results."
    exit 0
}

# Top result
$top = $obj.result[0]
$sim = [math]::Round($top.similarity * 100, 1)
$ts  = if ($top.from -ne $null) { ([TimeSpan]::FromSeconds($top.from)).ToString("hh\:mm\:ss") } else { "?" }
$epi = if ($top.episode.Count -gt 0) { $top.episode[0] } else { "?" }

Write-Host "Top match:"
Write-Host "  Similarity: $sim`%"
Write-Host "  AniList ID: $($top.anilist)"
Write-Host "  Episode:    $epi"
Write-Host "  Timecode:   $ts"
Write-Host ""
Write-Host " Frame image URL:`n  $($top.image)"
Write-Host " Video clip URL:`n  $($top.video)"
