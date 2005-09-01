CCFLAGS	+= -DASSUME_STATELESS
LDLIBS	+= -lobjson -lxml2 -lopensrf

all: libmod_ils_gateway.so

install: 
	$(APXS2) -i -a -n ils_gateway libmod_ils_gateway.so

libmod_ils_gateway.so:	mod_ils_gateway.o
	$(CC) -shared -W1 mod_ils_gateway.o -o libmod_ils_gateway.so

mod_ils_gateway.o: mod_ils_gateway.h mod_ils_gateway.c	

clean:
	/bin/rm -f *.o *.so 
