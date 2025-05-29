# Dockerfile
FROM soruly/liresolr:latest

# Copy in your baked index (with cl_0/data/index/*)
# and also your configset if you need to override it:
COPY solr-data/cl_0 /var/solr/data/cl_0

# Ensure permissions
USER root
RUN chown -R solr:solr /var/solr/data/cl_0

USER solr

# Expose port
EXPOSE 8983

# Healthcheck: ping Solr core until it's ready
HEALTHCHECK --interval=30s --timeout=10s --retries=5 \
  CMD curl -fs http://localhost:8983/solr/cl_0/admin/ping?wt=json || exit 1

# Entrypoint is inherited from the base image, which does `solr-precreate` if needed


FROM node:18-alpine

# add curl so we can debug connectivity
RUN apk add --no-cache curl

WORKDIR /app
COPY . .
RUN npm install
CMD ["node", "src/search.js"]