# set this shell variable prior to calling make to run with malloc_check enabled
#MALLOC_CHECK_=1 # XXX debug only

CC = gcc
LIB_DIR=../../lib
CC_OPTS = -Wall -O2 -I /usr/include/libxml2 -I /usr/include/libxml2/libxml -I ../../include -I /home/erickson/cc/libxml2-2.6.16
EXE_LD_OPTS = -L $(LIB_DIR) -lxml2 -lopensrf_transport 
LIB_SOURCES = generic_utils.c transport_socket.c transport_session.c transport_message.c transport_client.c

TARGETS=generic_utils.o transport_socket.o transport_message.o transport_session.o transport_client.o 

basic_client: lib
	$(CC) $(CC_OPTS) $(EXE_LD_OPTS) basic_client.c -o $@

test: lib
	$(CC) $(CC_OPTS) $(EXE_LD_OPTS) test.c -o $@


# --- Libs -----------------------------------------------
	
lib: 
	$(CC) -c $(CC_OPTS)	$(LIB_SOURCES)  
	$(CC) -shared -W1 $(LD_OPTS) $(TARGETS) -o $(LIB_DIR)/libopensrf_transport.so


clean:
	/bin/rm -f *.o $(LIB_DIR)/libopensrf_transport.so basic_client
