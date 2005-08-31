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

OBJS			= object.o json_parser.o utils.o
UTIL_DIR		= ../utils
DEST_INCLUDE = objson
CC_OPTS		+= -DSTRICT_JSON_WRITE #-DSTRICT_JSON_READ

# -------------
#CC_OPTS		+= -I ../utils/
#LD_OPTS += -L .
#TMPDIR = .
# -------------

all:	msg test

msg: 
	echo "-> $$(pwd)"	

test: libobjson.so
	echo $@
	$(CC) $(CC_OPTS) $(LD_OPTS) -lobjson objson_test.c -o $@

install:
	echo installing libobjson.so
	mkdir -p $(INCLUDEDIR)/$(DEST_INCLUDE)
	cp $(TMPDIR)/$(DEST_INCLUDE)/*.h $(INCLUDEDIR)/objson/
	cp $(TMPDIR)/libobjson.so $(LIBDIR)/libobjson.so

libobjson.so:	$(OBJS)
	echo $@
	$(CC) -shared -W1 $(OBJS) -o $(TMPDIR)/libobjson.so
	$(CC) -shared -W1 $(OBJS) -o libobjson.so
	mkdir -p $(TMPDIR)/$(DEST_INCLUDE)/
	cp *.h $(TMPDIR)/$(DEST_INCLUDE)/

object.o:	object.h object.c
	echo $@
	$(CC) -c $(CC_OPTS) object.c -o $@

json_parser.o:	json_parser.h json_parser.c
	echo $@
	$(CC) -c $(CC_OPTS) json_parser.c -o $@

utils.o:	$(UTIL_DIR)/utils.h $(UTIL_DIR)/utils.c
	echo $@
	$(CC) -c $(CC_OPTS) $(UTIL_DIR)/utils.c -o $@

clean:
	/bin/rm -f *.o *.so test libobjson.so
