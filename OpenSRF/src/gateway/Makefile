CCFLAGS	+= -DASSUME_STATELESS
LDLIBS	+= -lobjson -lxml2 -lopensrf

all: osrf_json_gateway.so copy

install: 
	$(APXS2) -i -a -n osrf_json_gateway osrf_json_gateway.so
	cp apachetools.h $(INCLUDEDIR)/opensrf/

copy:
	cp apachetools.h $(TMPDIR)

apachetools.o:	apachetools.h apachetools.c
osrf_json_gateway.o:	osrf_json_gateway.c
osrf_json_gateway.so: osrf_json_gateway.o apachetools.o
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) -shared -W1 apachetools.o osrf_json_gateway.o -o osrf_json_gateway.so


clean:
	/bin/rm -f *.o *.so 
