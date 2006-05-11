LDLIBS += -lobjson -lopensrf -lfieldmapper 
CFLAGS += -DOSRF_LOG_PARAMS

#all:	oils_auth.so oils_fetch.so oils_cstore.so
#all:	oils_auth.so oils_cstore.so
all:	oils_auth.so

oils_event.o:	oils_event.c oils_event.h
oils_utils.o:	oils_utils.c oils_utils.h
oils_auth.o:	oils_auth.c
oils_fetch.o:	oils_fetch.c oils_utils.h 
oils_cstore.o:	oils_cstore.c oils_utils.h 

oils_cstore.so:	oils_cstore.o liboils_utils.so
	@echo $@
	$(CC) -shared -W1 -L/usr/local/lib/dbd \
		$(LDLIBS) $(LDFLAGS) -loils_utils -ldbi -ldbdpgsql oils_cstore.o -o $(TMPDIR)/$@

oils_fetch.so:	oils_fetch.o liboils_utils.so
	@echo $@
	$(CC) -shared -W1 -L/usr/local/lib/dbd \
		$(LDLIBS) $(LDFLAGS) -ldbi -ldbdpgsql -loils_utils oils_fetch.o -o $(TMPDIR)/$@

oils_auth.so:	oils_auth.o liboils_utils.so
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) -loils_utils oils_auth.o -o $(TMPDIR)/$@

liboils_utils.so:	oils_utils.o oils_event.o oils_constants.h
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) oils_utils.o oils_event.o -o $@
	cp $@ $(TMPDIR)/
	mkdir -p $(TMPDIR)/openils/
	cp oils_event.h $(TMPDIR)/openils/
	cp oils_utils.h $(TMPDIR)/openils/
	cp oils_constants.h $(TMPDIR)/openils/



install:
	@echo $@;
	cp $(TMPDIR)/oils_auth.so $(LIBDIR)/
	#cp $(TMPDIR)/oils_fetch.so $(LIBDIR)/
	#cp $(TMPDIR)/oils_cstore.so $(LIBDIR)/
	cp $(TMPDIR)/liboils_utils.so $(LIBDIR)/
	mkdir -p $(INCDIR)/
	cp oils_utils.h $(INCDIR)
	cp oils_event.h $(INCDIR)
	cp oils_constants.h $(INCDIR)

clean:
	@echo $@;
	rm -f *.o *.so

