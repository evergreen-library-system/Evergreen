#MALLOC_CHECK_=1 # XXX debug only

LDLIBS	+= -lxml2 -lopensrf -lobjson
CFLAGS	+= -D_ROUTER

all: opensrf_router 
#osrf_router

install: 
	cp opensrf_router $(BINDIR)

#opensrf_router:	router.o 
#	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) router.o -o $@
#router.o:	router.c router.h

opensrf_router:	osrf_router.o osrf_router_main.o
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) osrf_router.o osrf_router_main.o -o $@
osrf_router.o: osrf_router.c osrf_router.h
osrf_router_main.o: osrf_router_main.c 

clean:
	/bin/rm -f *.o opensrf_router

