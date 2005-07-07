#!/bin/sh
dropdb demo-dev
createdb -E UNICODE demo-dev
