# set this shell variable prior to calling make to run with malloc_check enabled
#MALLOC_CHECK_=1 # XXX debug only

LD_OPTS	+= -lxml2 -lc_utils 

SOURCES	= transport_session.c transport_message.c transport_client.c
TARGETS	= transport_message.o transport_session.o transport_client.o 
HEADERS	= transport_message.h transport_session.h transport_client.h 

TARGET = libopensrf_transport.so

all:	msg libopensrf_transport.so

msg:
	echo "-> $$(pwd)"	

libopensrf_transport.so:  $(TARGETS)
	echo $@
	$(CC) -shared -W1 $(LD_OPTS) $(TARGETS) -o libopensrf_transport.so
	$(CC) -shared -W1 $(LD_OPTS) $(TARGETS) -o $(TMPDIR)/libopensrf_transport.so
	cp $(HEADERS) $(TMPDIR)

transport_session.o:	transport_session.c transport_session.h
	echo $@
	$(CC) -c $(CC_OPTS) transport_session.c -o $@

transport_message.o:	transport_message.c transport_message.h
	echo $@
	$(CC) -c $(CC_OPTS) transport_message.c -o $@

transport_client.o:	transport_client.c transport_client.h
	echo $@
	$(CC) -c $(CC_OPTS) transport_client.c -o $@

install:
	echo installing $(TARGET)
	cp $(TMPDIR)/libopensrf_transport.so $(LIBDIR)/
	cp $(HEADERS) $(INCLUDEDIR)/$(OPENSRF)

clean:
	echo $@
	/bin/rm -f *.o libopensrf_transport.so
