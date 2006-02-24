CCFLAGS	+= -DASSUME_STATELESS
LDLIBS	+= -lobjson -lxml2 -lopensrf

all: mod_ils_gateway.so osrf_json_gateway.so copy

install: 
	$(APXS2) -i -a -n ils_gateway mod_ils_gateway.so
	$(APXS2) -i -a -n osrf_json_gateway osrf_json_gateway.so
	cp apachetools.h $(INCLUDEDIR)/opensrf/

mod_ils_gateway.o: mod_ils_gateway.h mod_ils_gateway.c	
mod_ils_gateway.so:	mod_ils_gateway.o
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) -shared -W1 mod_ils_gateway.o -o mod_ils_gateway.so

copy:
	cp apachetools.h $(TMPDIR)

apachetools.o:	apachetools.h apachetools.c
osrf_json_gateway.o:	osrf_json_gateway.c
osrf_json_gateway.so: osrf_json_gateway.o apachetools.o
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) -shared -W1 apachetools.o osrf_json_gateway.o -o osrf_json_gateway.so


clean:
	/bin/rm -f *.o *.so 
