#!/bin/bash
# Author: Bill Erickson <berickxx@gmail.com>
#
# Script to rebuild the set of Angular dependencies.
# 1. Remove node_modules
# 2. Remove dependencies and devDependencies from package.json
# 3. Install @angular/core using the requested version of angular.
# 4. Reinstall dependencies and devDependencies
#
# Building in this fashion, where we start with a single Angular package
# allows the other packages to better determine the version to use.
# 
# Script requires 'jq' program (sudo apt-get install jq) for 
# parsing and manipulating JSON.
# ----------------------------------------------------------------------------
set -euo pipefail
ANGULAR_VERSION="" # Example ^8.0.0

function usage {
    cat <<USAGE
        
        Synopsis:

            $0 -v "^8.0.0"

        Options:

            -v Angular version string
USAGE

    exit 0;
}

while getopts "v:h" opt; do
    case $opt in
        v) ANGULAR_VERSION="$OPTARG";;
        h) usage;
    esac
done;

if [ -z "$ANGULAR_VERSION" ]; then
    echo "Angular version required"
    usage;
fi;

echo "Removing node_modules"
rm -rf ./node_modules

echo "Removing package-lock.json"
rm -f package-lock.json

# Exctract the dependencies from package.json
DEPS=$(jq '.dependencies | keys' package.json | tr '[],"' ' ' | xargs);
DEV_DEPS=$(jq '.devDependencies | keys' package.json | tr '[],"' ' ' | xargs);

# Remove deps from package.json
jq '.devDependencies={} | .dependencies={}' package.json > package.wip.json
mv package.wip.json package.json

# Start by installing the version of Angular we want to use
npm install @angular/cli@$ANGULAR_VERSION @angular/core@$ANGULAR_VERSION

# Then let NPM figure out the versioning for the rest.

npm install --save $DEPS
npm install --save-dev $DEV_DEPS


