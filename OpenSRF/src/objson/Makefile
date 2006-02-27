# --------------------------------------------------------------------
# Copyright (C) 2005  Georgia Public Library Service 
# Bill Erickson <highfalutin@gmail.com>
# Mike Rylander <mrylander@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# --------------------------------------------------------------------


# --------------------------------------------------------------------
#
# -DSTRICT_JSON_WRITE if not defined, 'null' objects will be written
#	as empty strings. e.g. [null, null] => [,,]
#
# -DSTRICT_JSON_READ if not defiend, empty array and object values
#	(not keys) will be considered null.
#	e.g. [,,{"key":}] will be parsed as [null, null, {"key":null}]
#
# --------------------------------------------------------------------

OBJS				= md5.o utils.o json2xml.o object.o json_parser.o
UTIL_DIR			= ../utils
DEST_INCLUDE	= objson
CFLAGS			+= -DSTRICT_JSON_WRITE #-DSTRICT_JSON_READ

JSON_HEADERS = object.h json_parser.h json2xml.h

all:	test

test: libobjson.so objson_test.o

objson_test.o: objson_test.c 
object.o:	object.h object.c
json_parser.o:	json_parser.h json_parser.c

install:
	mkdir -p $(INCLUDEDIR)/$(DEST_INCLUDE)
	cp $(TMPDIR)/$(DEST_INCLUDE)/*.h $(INCLUDEDIR)/objson/
	cp $(TMPDIR)/libobjson.so $(LIBDIR)/libobjson.so

libobjson.so:	$(OBJS)
	$(CC) -shared -W1 $(OBJS) -o $(TMPDIR)/libobjson.so
	$(CC) -shared -W1 $(OBJS) -o libobjson.so
	mkdir -p $(TMPDIR)/$(DEST_INCLUDE)/
	cp $(JSON_HEADERS) $(TMPDIR)/$(DEST_INCLUDE)/

utils.o:	$(UTIL_DIR)/utils.h $(UTIL_DIR)/utils.c
	cp $(UTIL_DIR)/utils.h .
	cp $(UTIL_DIR)/utils.c .
	$(CC) -c $(CFLAGS) utils.c -o $@

md5.o:	$(UTIL_DIR)/md5.h $(UTIL_DIR)/md5.c
	cp $(UTIL_DIR)/md5.h .
	cp $(UTIL_DIR)/md5.c .
	$(CC) -c $(CFLAGS) md5.c -o $@

json2xml.o:	json2xml.h json2xml.c
	$(CC) -c $(CFLAGS) json2xml.c -o $@


clean:
	/bin/rm -f *.o *.so utils.c utils.h libobjson.so

