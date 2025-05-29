# 2) Transform & index each XML
wsl bash -lc '
for xml in /hashes/*/*.xml; do
  folder=$(basename "$(dirname "$xml")")
  echo "Indexing $xml as $folder"
  sed "s#<field name=\"id\">.*</field>#<field name=\"id\">${folder}</field>#" "$xml" \
    | curl -X POST -H "Content-Type: text/xml" \
           --data-binary @- \
           "http://127.0.0.1:8983/solr/mycore/update?wt=json&commit=true"
done
'

# 3) Commit
wsl curl "http://127.0.0.1:8983/solr/cl_0/update?commit=true&wt=json" `
     -H "Content-Type: application/json" `
     --data-binary '{"commit":{}}'