// lib/get-solr-core-list.js
export default function getSolrCoreList() {
  const raw = process.env.SOLA_SOLR_LIST || '';
  console.log('trace.moe:search ▶ raw SOLA_SOLR_LIST =', raw);
  return raw
    .split(',')                   // multiple cores support
    .map(s => s.trim())          // strip whitespace
    .map(s => s.replace(/\/+$/, '')) // drop any trailing slash
    .filter(Boolean);
}
