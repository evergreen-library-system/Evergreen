# $Id$

CFLAGS		+= -g -O2 -Wall -std=gnu99 -D_GNU_SOURCE -D_REENTRANT -I ../../include -fPIC
LDFLAGS		+= -shared -W1 
LIB_DIR		= ../../lib
LDLIBS		+= -L . -ljson -L $(LIB_DIR)

LIB_OBJS 	= debug.o \
		  linkhash.o \
		  printbuf.o \
		  arraylist.o \
		  json_object.o \
		  json_tokener.o

TESTS		= test1 test2

all: tests lib oils_method

lib: $(LIB_OBJS)
	gcc $(LDFLAGS) $(LIB_OBJS) -o $(LIB_DIR)/libjson.so

tests: $(TESTS)

test1: test1.o lib 
	gcc $(LDLIBS) test1.o -o test1
test2: test2.o lib 
	gcc $(LDLIBS) test2.o -o test2
oils_method: oils_method.o lib
	gcc $(LDLIBS) oils_method.o -o oils_method

oils_method.o: oils_method.c
	gcc -c $(CFLAGS) oils_method.c -o oils_method.o

clean:
	rm -f *.o *~ $(TESTS) $(LIB_DIR)/libjson.so oils_method

cex.o: cex.c 
debug.o: debug.c 
linkhash.o: linkhash.c 
arraylist.o: arraylist.c 
json_object.o: json_object.c 
json_tokener.o: json_tokener.c 
test1.o: test1.c 
test2.o: test2.c 

