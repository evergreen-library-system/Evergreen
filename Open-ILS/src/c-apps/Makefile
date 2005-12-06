LDLIBS += -lobjson -lopensrf -lfieldmapper
CFLAGS += -DOSRF_LOG_PARAMS

all:	oils_auth.so

oils_event.o:	oils_event.c oils_event.h
oils_utils.o:	oils_utils.c oils_utils.h
oils_auth.o:	oils_auth.c


oils_auth.so:	oils_auth.o oils_utils.o oils_event.o
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) oils_utils.o oils_event.o oils_auth.o -o $(TMPDIR)/oils_auth.so

install:
	cp $(TMPDIR)/oils_auth.so $(LIBDIR)/

clean:
	rm -f *.o *.so

