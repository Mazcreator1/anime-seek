#!/bin/sh
set -eux

echo "[BOOTSTRAP] starting…"

INDEX_DIR=/var/solr/data/cl_0/data/index
TARBALL=/tmp/liresolr_index.tar.gz

echo "[BOOTSTRAP] INDEX_DIR=$INDEX_DIR"
echo "[BOOTSTRAP] TARBALL=$TARBALL"

# ensure the dir exists
mkdir -p "$INDEX_DIR"
chown solr:solr "$INDEX_DIR"

# bail if we don't even have a tarball
if [ ! -f "$TARBALL" ]; then
  echo "[BOOTSTRAP][ERROR] tarball not found at $TARBALL"
  exit 1
fi

# look for any segments* file already in the index
if ls "$INDEX_DIR"/segments* 1> /dev/null 2>&1; then
  echo "[BOOTSTRAP] existing segments found → doing incremental extract"
  # only add new files, leave existing untouched
  sudo -u solr tar --skip-old-files -xzf "$TARBALL" \
    -C "$INDEX_DIR" \
    --strip-components=1
else
  echo "[BOOTSTRAP] no segments found → doing full extract"
  # clear out the dir just in case partial garbage left behind
  rm -rf "$INDEX_DIR"/*
  sudo -u solr tar -xzf "$TARBALL" \
    -C "$INDEX_DIR" \
    --strip-components=1
fi

# ensure ownership
chown -R solr:solr "$INDEX_DIR"

# optionally: reload the core so Solr picks up the index immediately
echo "[BOOTSTRAP] reloading core cl_0"
curl "http://localhost:8983/solr/admin/cores?action=RELOAD&core=cl_0" \
  || echo "[BOOTSTRAP][WARN] reload failed, maybe Solr not up yet"

echo "[BOOTSTRAP] done."
