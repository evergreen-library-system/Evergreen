LDLIBS += -lobjson -lopensrf -lfieldmapper
CFLAGS += -DOSRF_LOG_PARAMS

all:	oils_auth.so

oils_event.o:	oils_event.c oils_event.h
oils_utils.o:	oils_utils.c oils_utils.h
oils_auth.o:	oils_auth.c


oils_auth.so:	oils_auth.o liboils_utils.so
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) -loils_utils oils_auth.o -o $(TMPDIR)/$@

liboils_utils.so:	oils_utils.o oils_event.o oils_constants.h
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) oils_utils.o oils_event.o -o $@
	cp $@ $(TMPDIR)/
	mkdir -p $(TMPDIR)/openils/
	cp oils_event.h $(TMPDIR)/openils/
	cp oils_utils.h $(TMPDIR)/openils/
	cp oils_constants.h $(TMPDIR)/openils/



install:
	@echo $@;
	cp $(TMPDIR)/oils_auth.so $(LIBDIR)/
	cp $(TMPDIR)/liboils_utils.so $(LIBDIR)/
	mkdir -p $(INCDIR)/
	cp oils_utils.h $(INCDIR)
	cp oils_event.h $(INCDIR)
	cp oils_constants.h $(INCDIR)

clean:
	rm -f *.o *.so

