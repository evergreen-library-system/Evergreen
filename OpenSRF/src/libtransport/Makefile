# set this shell variable prior to calling make to run with malloc_check enabled
#MALLOC_CHECK_=1 # XXX debug only

LD_OPTS	+= -lxml2 -lc_utils 

SOURCES	= transport_socket.c transport_session.c transport_message.c transport_client.c
TARGETS	= transport_socket.o transport_message.o transport_session.o transport_client.o 
HEADERS	= transport_socket.h transport_message.h transport_session.h transport_client.h 

all:  lib
	
lib:  $(SOURCES) $(HEADERS)
	$(CC) -c $(CC_OPTS) $(SOURCES)  
	$(CC) -shared -W1 $(LD_OPTS) $(TARGETS) -o $(TMPDIR)/libopensrf_transport.so
	cp $(HEADERS) $(TMPDIR)


install:
	@echo "Installing libopensrf_transport..."
	cp $(TMPDIR)/libopensrf_transport.so $(LIBDIR)/
	cp $(HEADERS) $(INCLUDEDIR)/$(OPENSRF)

clean:
	/bin/rm -f *.o basic_client component
