CC				= gcc
LIB_DIR		= ../../lib
CC_OPTS		= -Wall -O2  -I ../../include 
EXE_LD_OPTS = -L $(LIB_DIR) 

all: util 

util: md5

md5: md5.c
	$(CC) -c $(CC_OPTS) md5.c -o md5.o 
	$(CC) -shared -W1 md5.o -o $(LIB_DIR)/libmd5.so
	/bin/rm -f md5.o

clean:
	/bin/rm -f $(LIB_DIR)/libmd5.so
