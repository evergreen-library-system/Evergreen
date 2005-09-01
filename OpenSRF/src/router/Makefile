#MALLOC_CHECK_=1 # XXX debug only

LDLIBS	+= -lxml2 -lopensrf -lobjson
CFLAGS	+= -D_ROUTER

all: router 

install: 
	cp router $(BINDIR)

router:	router.o 
router.o:	router.c router.h

clean:
	/bin/rm -f *.o router
