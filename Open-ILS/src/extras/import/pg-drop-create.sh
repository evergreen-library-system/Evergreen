#!/bin/sh
dropdb open-ils-ascii
createdb -E SQL_ASCII open-ils-ascii

dropdb open-ils-utf8
createdb -E UNICODE open-ils-utf8
