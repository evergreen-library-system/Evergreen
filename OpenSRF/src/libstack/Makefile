LIB_DIR = ../../lib
CC_OPTS = -Wall -O2 -I /usr/include/libxml2 -I /usr/include/libxml2/libxml -I ../../include -fPIC -DASSUME_STATELESS
LIB_SOURCES = osrf_message.c osrf_app_session.c osrf_stack.c osrf_system.c string_array.c
LIB_TARGETS = osrf_message.o osrf_app_session.o osrf_stack.o osrf_system.o string_array.o
EXE_LD_OPTS = -L $(LIB_DIR) -lxml2 -lopensrf_transport  -lopensrf_stack -lobjson -ljson 
CC = gcc

all: lib 
#client sys_client

sys_client: sys_client.c lib 
	$(CC) $(CC_OPTS) $(EXE_LD_OPTS) *.o sys_client.c -o sys_client

#client: client.c lib 
#	$(CC) $(CC_OPTS) $(EXE_LD_OPTS) *.o client.c -o client
	
# ----------------------------------------------------------------

lib: libjson libopensrf_transport
	$(CC) -c $(CC_OPTS)	$(LIB_SOURCES)  
	$(CC) -shared -W1 $(LIB_TARGETS) -o $(LIB_DIR)/libopensrf_stack.so

libjson: 
	make -C ../libjson

libopensrf_transport:
	make -C ../libtransport

clean:
	/bin/rm -f *.o sys_client client $(LIB_DIR)/libopensrf_stack.so
