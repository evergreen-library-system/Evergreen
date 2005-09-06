#MALLOC_CHECK_=1 # XXX debug only

LDLIBS	+= -lxml2 -lopensrf -lobjson
CFLAGS	+= -D_ROUTER

all: opensrf_router 

install: 
	cp opensrf_router $(BINDIR)

opensrf_router:	router.o 
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) router.o -o $@
router.o:	router.c router.h

clean:
	/bin/rm -f *.o opensrf_router

