CC				= gcc
LIB_DIR		= ../../lib 

CC_OPTS		= -fPIC -Wall -O2 -I /usr/include/libxml2 \
				  -I /usr/include/libxml2/libxml -I ../../include \
				  -I /pines/apps/apache2/include

EXE_LD_OPTS = -L $(LIB_DIR) -lxml2 -lopensrf_transport -lopensrf_stack -ljson -lmd5

all: gateway 

install: gateway
	@echo "As Root, Run: /pines/apps/apache2/bin/apxs -i -a -n ils_gateway libmod_ils_gateway.so";

gateway: lib mod_ils_gateway.c	
	$(CC) -c $(CC_OPTS)  mod_ils_gateway.c
	$(CC)  $(EXE_LD_OPTS) -shared -W1 mod_ils_gateway.o -o libmod_ils_gateway.so			

lib: 
	make -C ../libstack
	make -C ../libtransport
	make -C ../utils

clean:
	/bin/rm -f *.o *.so
