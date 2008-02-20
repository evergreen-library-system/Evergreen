LDLIBS += -lobjson -lopensrf #-lfieldmapper 
LDFLAGS += -Wl,-rpath=$(LIBDIR) -L$(DBI_LIBS)
CFLAGS += -DOSRF_LOG_PARAMS -I../../include

#all:	oils_auth.so oils_fetch.so oils_cstore.so
all:	liboils_idl.so oils_auth.so oils_cstore.so oils_rstore.so oils_dataloader
#all:	oils_auth.so

oils_event.o:	oils_event.c
oils_utils.o:	oils_utils.c
oils_auth.o:	oils_auth.c
oils_fetch.o:	oils_fetch.c
oils_cstore.o:	oils_cstore.c
oils_dataloader.o:	oils_dataloader.c

oils_dataloader:	oils_dataloader.o
	@echo $@
	$(CC) $(LDLIBS) $(LDFLAGS) -loils_idl -loils_utils oils_dataloader.o -o $@

oils_cstore.so:	oils_cstore.o liboils_utils.so liboils_idl.so
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) -loils_idl -ldbi -loils_utils -ldbdpgsql oils_cstore.o -o $@

oils_rstore.o:	oils_cstore.c
	$(CC) $(CFLAGS) -DRSTORE -c -o $@ oils_cstore.c 

oils_rstore.so:	oils_rstore.o liboils_utils.so liboils_idl.so
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) -loils_idl -ldbi -ldbdpgsql oils_rstore.o -o $@

oils_fetch.so:	oils_fetch.o liboils_utils.so
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) -ldbi -ldbdpgsql -loils_utils oils_fetch.o -o $@

oils_idl-core.o:	oils_idl-core.c

liboils_idl.so:	oils_idl-core.o
	@echo $@
	$(CC) $(CFLAGS) -shared -W1 $(LDLIBS) $(LDFLAGS) oils_idl-core.o -o $@

oils_auth.so:	oils_auth.o liboils_utils.so
	@echo $@
	$(CC) -shared -W1 $(CFLAGS) $(LDLIBS) $(LDFLAGS) -loils_utils -loils_idl oils_auth.o -o $@

liboils_utils.so:	oils_utils.o oils_event.o
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) oils_utils.o oils_event.o -o $@

install:
	@echo $@;
	cp oils_auth.so $(LIBDIR)/
	cp oils_cstore.so $(LIBDIR)/
	cp oils_rstore.so $(LIBDIR)/
	cp liboils_utils.so $(LIBDIR)/
	cp liboils_idl.so $(LIBDIR)/
	cp oils_dataloader $(BINDIR)/
	mkdir -p $(INCDIR)/
	cp ../../include/openils/*.h $(INCDIR)/

clean:
	@echo $@;
	rm -f *.o *.so oils_dataloader

