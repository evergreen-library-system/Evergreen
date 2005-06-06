CC				= gcc
LIB_DIR		= ../../lib
CC_OPTS		= -fPIC -Wall -O2  -I ../../include 
EXE_LD_OPTS = -L $(LIB_DIR) 
INCLUDE		= ../../include
FM_HEADER	= fieldmapper.h
FM_SOURCE	= fieldmapper.c
HEADER_DIR  = $(INCLUDE)/opensrf

all: util fieldmapper

util: md5

md5: md5.c
	$(CC) -c $(CC_OPTS) md5.c -o md5.o 
	$(CC) -shared -W1 md5.o -o $(LIB_DIR)/libmd5.so

fieldmapper: fieldmapper-c.pl
	perl fieldmapper-c.pl $(FM_HEADER) $(FM_SOURCE)
	$(CC) -c $(CC_OPTS) fieldmapper.c -o fieldmapper.o
	$(CC) -shared -W1 fieldmapper.o -o $(LIB_DIR)/libopensrf_fm.so
	cp $(FM_HEADER) $(HEADER_DIR)/

clean:
	/bin/rm -f md5.o
	/bin/rm -f $(FM_SOURCE) $(FM_HEADER)
