CC				= gcc
HEADER_DIR	= ../../include
CFLAGS		= -g -O2 -Wall -fPIC -I $(HEADER_DIR) #-D_REENTRANT 
LDFLAGS		= -shared -W1 
LIB_DIR		= ../../lib
LDLIBS		= -L . -lobjson -L $(LIB_DIR)
OBJS			= object.o json_parser.o utils.o
UTIL_DIR		= ../utils

all:	test
	
test: lib objson_test.c
	$(CC) $(CFLAGS) $(LDLIBS) objson_test.c -o $@

lib:	$(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) -o $(LIB_DIR)/libobjson.so
	if [ ! -d $(HEADER_DIR)/objson/ ];then mkdir $(HEADER_DIR)/objson; fi;
	cp *.h $(HEADER_DIR)/objson/

object.o:	object.h object.c
	$(CC) -c $(CFLAGS) object.c -o $@

json_parser.o:	json_parser.h json_parser.c
	$(CC) -c $(CFLAGS) json_parser.c -o $@

utils.o:	$(HEADER_DIR)/utils.h $(UTIL_DIR)/utils.c
	$(CC) -c $(CFLAGS) $(UTIL_DIR)/utils.c -o $@

clean:
	/bin/rm -f *.o test
