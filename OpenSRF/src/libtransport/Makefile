
TARGETS	= transport_message.o transport_session.o transport_client.o 
HEADERS	= transport_message.h transport_session.h transport_client.h 

TARGET = libopensrf_transport.so

all:	$(TARGETS) copy

copy:
	cp $(HEADERS) $(TMPDIR)

transport_session.o:	transport_session.c transport_session.h
transport_message.o:	transport_message.c transport_message.h
transport_client.o:	transport_client.c transport_client.h


clean:
	/bin/rm -f *.o 
