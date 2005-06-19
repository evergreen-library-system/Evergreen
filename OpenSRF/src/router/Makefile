# set this shell variable prior to calling make to run with malloc_check enabled
#MALLOC_CHECK_=1 # XXX debug only

LD_OPTS		+= -lc_utils -lxml2 -lopensrf_stack -ljson -lobjson
LP				= ../libtransport
LIB_SOURCES = $(LP)/transport_socket.c $(LP)/transport_session.c $(LP)/transport_message.c $(LP)/transport_client.c 

all: router 

install: 
	cp router $(BINDIR)

router:  router.c $(LIB_SOURCES)
	$(CC) $(LD_OPTS) -D_ROUTER $(CC_OPTS)	$(LIB_SOURCES) router.c -o $@ 

clean:
	/bin/rm -f *.o router
