# set this shell variable prior to calling make to run with malloc_check enabled
#MALLOC_CHECK_=1 # XXX debug only

CC = gcc
CC_OPTS = -Wall -O2 -I /usr/include/libxml2 -I /usr/include/libxml2/libxml -I ../../include
LD_OPTS = -L ../../lib -lxml2 -lopensrf_stack -ljson
LP=../libtransport
LIB_SOURCES = $(LP)/generic_utils.c $(LP)/transport_socket.c $(LP)/transport_session.c $(LP)/transport_message.c $(LP)/transport_client.c $(LP)/sha.c

all: router router_query router_register

router_register: router_register.c
	$(CC) $(CC_OPTS) -L ../../lib -lopensrf_transport -lxml2 router_register.c -o router_register

router_query: router_query.c
	$(CC) $(CC_OPTS) -L ../../lib -lopensrf_transport -lxml2 router_query.c -o router_query

# The router is compiled as a static binary because of some 
# necessary #defines that would break the library
router: 
	$(CC) $(LD_OPTS) -D_ROUTER $(CC_OPTS)	$(LIB_SOURCES) router.c -o $@ 

clean:
	/bin/rm -f router  router_query
