# set this shell variable prior to calling make to run with malloc_check enabled
#MALLOC_CHECK_=1 # XXX debug only

CC = gcc
CC_OPTS = -Wall -O2 -I /usr/include/libxml2 -I /usr/include/libxml2/libxml -I ../../include
LD_OPTS = -L ../../lib -lxml2 -lopensrf_stack -ljson -lobjson
LP=../libtransport
UTIL_DIR = ../utils
LIB_SOURCES = $(UTIL_DIR)/utils.c $(LP)/generic_utils.c $(LP)/transport_socket.c $(LP)/transport_session.c $(LP)/transport_message.c $(LP)/transport_client.c $(UTIL_DIR)/sha.c

all: router 
install: router
	cp router ../../bin

router:  router.c $(LIB_SOURCES)
	$(CC) $(LD_OPTS) -D_ROUTER $(CC_OPTS)	$(LIB_SOURCES) router.c -o $@ 

clean:
	/bin/rm -f router  router_query
