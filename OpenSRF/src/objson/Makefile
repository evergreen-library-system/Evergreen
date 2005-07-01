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


OBJS			= object.o json_parser.o utils.o
UTIL_DIR		= ../utils
DEST_INCLUDE = objson

all:	test

test: lib 
	$(CC) $(CC_OPTS) $(LD_OPTS) -lobjson objson_test.c -o $@

install:
	mkdir -p $(INCLUDEDIR)/$(DEST_INCLUDE)
	cp $(TMPDIR)/$(DEST_INCLUDE)/*.h $(INCLUDEDIR)/objson/
	cp $(TMPDIR)/libobjson.so $(LIBDIR)/libobjson.so

lib:	$(OBJS)
	$(CC) -shared -W1 $(OBJS) -o $(TMPDIR)/libobjson.so
	mkdir -p $(TMPDIR)/$(DEST_INCLUDE)/
	cp *.h $(TMPDIR)/$(DEST_INCLUDE)/

object.o:	object.h object.c
	$(CC) -c $(CC_OPTS) object.c -o $@

json_parser.o:	json_parser.h json_parser.c
	$(CC) -c $(CC_OPTS) json_parser.c -o $@

utils.o:	$(UTIL_DIR)/utils.h $(UTIL_DIR)/utils.c
	$(CC) -c $(CC_OPTS) $(UTIL_DIR)/utils.c -o $@

clean:
	/bin/rm -f *.o test
