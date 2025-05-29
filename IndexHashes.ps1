# IndexHashes.ps1
# PowerShell 5.1 compatible – per-file, per-frame indexing of ha/hi, with ID format: anilistId/filename/frame

$rootFolder    = 'C:\Users\mazcr\trace.moe\hashes'
$solrUpdateUrl = 'http://127.0.0.1:8983/solr/cl_0/update?wt=json&commit=true'

function Add-FieldNode {
    param(
        [System.Xml.XmlDocument]$XmlDoc,
        [System.Xml.XmlNode]    $DocNode,
        [string]                $Name,
        [string]                $Value
    )
    $node = $XmlDoc.CreateElement('field')
    $node.SetAttribute('name', $Name)
    $node.InnerText = $Value
    $DocNode.AppendChild($node) | Out-Null
}

$files = Get-ChildItem -Path $rootFolder -Recurse -Filter *.xml
foreach ($file in $files) {
    try {
        $src = New-Object System.Xml.XmlDocument
        $src.Load($file.FullName)

        $animeId  = Split-Path $file.DirectoryName -Leaf
        $filename = $file.Name

        $out   = New-Object System.Xml.XmlDocument
        $addEl = $out.CreateElement('add')
        $out.AppendChild($addEl) | Out-Null

        $docs = $src.SelectNodes('//doc')
        foreach ($docSrc in $docs) {
            $fnode = $docSrc.SelectSingleNode("field[@name='id']")
            if ($fnode -ne $null -and $fnode.HasChildNodes) {
                $frame = $fnode.ChildNodes.Item(0).Value
            } else {
                Write-Host "Missing frame id in: $($file.FullName)"
                continue
            }

            $uniqueId = "$animeId/$filename/$frame"

            $newDoc = $out.CreateElement('doc')
            $addEl.AppendChild($newDoc) | Out-Null

            Add-FieldNode -XmlDoc $out -DocNode $newDoc -Name 'id'       -Value $uniqueId
            Add-FieldNode -XmlDoc $out -DocNode $newDoc -Name 'anime_id' -Value $animeId
            Add-FieldNode -XmlDoc $out -DocNode $newDoc -Name 'filename' -Value $filename

            $fields = $docSrc.SelectNodes("field[@name]")
            foreach ($fld in $fields) {
                $n = $fld.GetAttribute('name')
                if ($n -like '*_ha' -or $n -like '*_hi') {
                    Add-FieldNode -XmlDoc $out -DocNode $newDoc -Name $n -Value $fld.InnerText
                }
            }
        }

        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('Content-Type','text/xml')
        $wc.UploadString($solrUpdateUrl, 'POST', $out.OuterXml) | Out-Null

        Write-Host "Indexed: $($file.FullName)"
    } catch {
        Write-Host "ERROR processing $($file.FullName): $($_.Exception.Message)"
    }
}