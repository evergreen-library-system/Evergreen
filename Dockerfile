FROM node:latest

# Basic setup
COPY . /usr/src/Evergreen
COPY ./.docker/docs-entrypoint.sh /scripts/docs-entrypoint.sh
ENV DOCSEARCH_ENABLED=true
ENV DOCSEARCH_ENGINE=lunr

# Set up the UI environment
WORKDIR /usr/src
RUN git clone git://git.evergreen-ils.org/eg-antora.git
WORKDIR /usr/src/eg-antora
RUN npm install && npx gulp bundle

# Set up the docs environment
WORKDIR /usr/src/Evergreen/docs
RUN npm i @antora/cli@2.1 @antora/site-generator-default@2.1 antora-lunr antora-site-generator-lunr
ENTRYPOINT ["/scripts/docs-entrypoint.sh"]
