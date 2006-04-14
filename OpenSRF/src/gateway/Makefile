#CFLAGS	+= -DASSUME_STATELESS -DOSRF_GATEWAY_NASTY_DEBUG
CFLAGS	+= -DASSUME_STATELESS 
LDLIBS	+= -lobjson -lopensrf

all: osrf_json_gateway.so copy

install: 
	$(APXS2) -i -a -n osrf_json_gateway osrf_json_gateway.so
	cp apachetools.h $(INCLUDEDIR)/opensrf/

copy:
	cp apachetools.h $(TMPDIR)

apachetools.o:	apachetools.h apachetools.c
	$(CC) -c $(CFLAGS) apachetools.c -o $@

osrf_json_gateway.o:	osrf_json_gateway.c
	$(CC) -c $(CFLAGS) osrf_json_gateway.c -o $@

osrf_json_gateway.so:	copy apachetools.o osrf_json_gateway.o
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) -shared -W1 apachetools.o osrf_json_gateway.o -o osrf_json_gateway.so


clean:
	/bin/rm -f *.o *.so 
