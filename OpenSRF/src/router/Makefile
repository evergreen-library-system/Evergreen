# set this shell variable prior to calling make to run with malloc_check enabled
#MALLOC_CHECK_=1 # XXX debug only

CC = gcc
CC_OPTS = -Wall -O2 -I /usr/include/libxml2 -I /usr/include/libxml2/libxml -I ../../include -I /home/erickson/cc/libxml2-2.6.16
LD_OPTS = -lxml2
LP=../libtransport
LIB_SOURCES = $(LP)/generic_utils.c $(LP)/transport_socket.c $(LP)/transport_session.c $(LP)/transport_message.c $(LP)/transport_client.c

# The router is compiled as a static binary because of some 
# necessary #defines that would break the library
router: 
	$(CC) $(LD_OPTS) -D_ROUTER $(CC_OPTS)	$(LIB_SOURCES) router.c -o $@ 

clean:
	/bin/rm -f router 
