CC = gcc
LIB_DIR=../../lib
CC_OPTS = -Wall -O2 -I /usr/include/libxml2 -I /usr/include/libxml2/libxml -I ../../include 
EXE_LD_OPTS = -L $(LIB_DIR) -lxml2 -lopensrf_transport -lopensrf_stack -ljson

all: srfsh

srfsh: lib
	$(CC) $(CC_OPTS) $(EXE_LD_OPTS) srfsh.c -o $@

lib: 
	make -C ../libtransport

clean:
	/bin/rm -f srfsh
