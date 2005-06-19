# $Id$

CFLAGS		+= -g -O2 -Wall -std=gnu99 -D_GNU_SOURCE -D_REENTRANT -I ../../include -fPIC

DEST_INCLUDE = libjson

LIB_OBJS 	= debug.o \
		  linkhash.o \
		  printbuf.o \
		  arraylist.o \
		  json_object.o \
		  json_tokener.o

TESTS		= test1 test2

all: tests  

lib: $(LIB_OBJS)
	gcc -shared -W1 $(LIB_OBJS) -o $(TMPDIR)/libjson.so
	mkdir -p $(TMPDIR)/$(DEST_INCLUDE)/
	cp *.h $(TMPDIR)/$(DEST_INCLUDE)/

install:
	mkdir -p $(INCLUDE)/$(DEST_INCLUDE)/
	cp $(TMPDIR)/$(DEST_INCLUDE)/*.h $(INCLUDE)/$(DEST_INCLUDE)/
	cp $(TMPDIR)/libjson.so $(LIBDIR)/libjson.so


tests: $(TESTS)

test1: test1.o lib 
	gcc -ljson $(LD_OPTS) $(LDLIBS) test1.o -o test1
test2: test2.o lib 
	gcc -ljson $(LD_OPTS) $(LDLIBS) test2.o -o test2


clean:
	rm -f *.o *~ $(TESTS) 

cex.o: cex.c 
debug.o: debug.c 
linkhash.o: linkhash.c 
arraylist.o: arraylist.c 
json_object.o: json_object.c 
json_tokener.o: json_tokener.c 
test1.o: test1.c 
test2.o: test2.c 

