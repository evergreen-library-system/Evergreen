# set this shell variable prior to calling make to run with malloc_check enabled
#MALLOC_CHECK_=1 # XXX debug only

CC = gcc
LIB_DIR=../../lib
CC_OPTS = -Wall -O2 -I /usr/include/libxml2 -I /usr/include/libxml2/libxml -I ../../include -I ../../../../cc/libxml2-2.6.16
LD_OPTS = -lxml2
EXE_LD_OPTS = -L $(LIB_DIR) -lxml2 -ltransport 
LIB_SOURCES = generic_utils.c transport_socket.c transport_session.c transport_message.c transport_client.c

TARGETS=generic_utils.o transport_socket.o transport_message.o transport_session.o transport_client.o 

all: router basic_client

basic_client: lib
	$(CC) $(CC_OPTS) $(EXE_LD_OPTS) basic_client.c -o $@

# --- Libs -----------------------------------------------
	
lib: 
	$(CC) -c $(CC_OPTS)	$(LIB_SOURCES)  
	$(CC) -shared -W1 $(LD_OPTS) $(TARGETS) -o $(LIB_DIR)/libtransport.so


# The router is compiled as a static binary because of some 
# necessary #defines that would break the library
router: 
	$(CC) $(LD_OPTS) -D_ROUTER $(CC_OPTS)	$(LIB_SOURCES) transport_router.c -o $@ 

clean:
	/bin/rm -f *.o ../../lib/libtransport.so router basic_client
