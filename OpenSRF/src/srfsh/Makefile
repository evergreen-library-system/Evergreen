CC				= gcc
LIB_DIR		= ../../lib 
CC_OPTS		= -fPIC -Wall -O2 -I /usr/include/libxml2 -I /usr/include/libxml2/libxml -I ../../include 
EXE_LD_OPTS = -L $(LIB_DIR) -lreadline -lxml2 -lopensrf_transport -lopensrf_stack -ljson -lncurses -lmd5

all: srfsh

install: srfsh
	cp srfsh ../../bin

srfsh: lib
	$(CC) $(CC_OPTS) $(EXE_LD_OPTS) srfsh.c -o $@

lib: 
	make -C ../libstack
	make -C ../libtransport
	make -C ../utils

clean:
	/bin/rm -f srfsh
