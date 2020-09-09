#!/bin/bash

cd /usr/src/Evergreen/docs
npx antora --ui-bundle-url /usr/src/eg-antora/build/ui-bundle.zip --generator antora-site-generator-lunr site.yml
