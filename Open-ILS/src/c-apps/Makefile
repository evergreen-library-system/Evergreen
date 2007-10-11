LDLIBS += -lobjson -lopensrf #-lfieldmapper 
LDFLAGS += -Wl,-rpath=$(LIBDIR) -L$(DBI_LIBS)
CFLAGS += -DOSRF_LOG_PARAMS

#all:	oils_auth.so oils_fetch.so oils_cstore.so
all:	liboils_idl.so oils_auth.so oils_cstore.so oils_rstore.so oils_dataloader
#all:	oils_auth.so

oils_event.o:	oils_event.c oils_event.h
oils_utils.o:	oils_utils.c oils_utils.h idl_fieldmapper.h
oils_auth.o:	oils_auth.c
oils_fetch.o:	oils_fetch.c oils_utils.h 
oils_cstore.o:	oils_cstore.c oils_utils.h
oils_dataloader.o:	oils_dataloader.c

oils_dataloader:	oils_dataloader.o
	@echo $@
	$(CC) $(LDLIBS) $(LDFLAGS) -loils_idl -loils_utils oils_dataloader.o -o $(TMP)/$@

oils_cstore.so:	oils_cstore.o liboils_utils.so liboils_idl.so
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) -loils_idl -ldbi -loils_utils -ldbdpgsql oils_cstore.o -o $(TMP)/$@

oils_rstore.o:	oils_cstore.c oils_utils.h
	$(CC) $(CFLAGS) -I$(TMP) -DRSTORE -c -o $@ oils_cstore.c 

oils_rstore.so:	oils_rstore.o liboils_utils.so liboils_idl.so
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) -loils_idl -ldbi -ldbdpgsql oils_rstore.o -o $(TMP)/$@

oils_fetch.so:	oils_fetch.o liboils_utils.so
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) -ldbi -ldbdpgsql -loils_utils oils_fetch.o -o $(TMP)/$@

oils_idl-core.o:	oils_idl-core.c oils_idl.h

liboils_idl.so:	oils_idl-core.o
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) oils_idl-core.o -o $@
	cp $@ $(TMP)/
	mkdir -p $(TMP)/openils/
	cp oils_idl.h $(TMP)/openils/
	cp idl_fieldmapper.h $(TMP)/openils/

oils_auth.so:	oils_auth.o liboils_utils.so
	@echo $@
	$(CC) -shared -W1 $(CFLAGS) $(LDLIBS) $(LDFLAGS) -loils_utils -loils_idl oils_auth.o -o $(TMP)/$@

liboils_utils.so:	oils_utils.o oils_event.o oils_constants.h
	@echo $@
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) oils_utils.o oils_event.o -o $@
	cp $@ $(TMP)/
	mkdir -p $(TMP)/openils/
	cp oils_event.h $(TMP)/openils/
	cp oils_utils.h $(TMP)/openils/
	cp oils_constants.h $(TMP)/openils/

install:
	@echo $@;
	cp $(TMP)/oils_auth.so $(LIBDIR)/
	#cp $(TMP)/oils_fetch.so $(LIBDIR)/
	cp $(TMP)/oils_cstore.so $(LIBDIR)/
	cp $(TMP)/oils_rstore.so $(LIBDIR)/
	cp $(TMP)/liboils_utils.so $(LIBDIR)/
	cp $(TMP)/liboils_idl.so $(LIBDIR)/
	cp $(TMP)/oils_dataloader $(BINDIR)/
	mkdir -p $(INCDIR)/
	cp oils_utils.h $(INCDIR)
	cp oils_idl.h $(INCDIR)
	cp oils_event.h $(INCDIR)
	cp oils_constants.h $(INCDIR)
	cp idl_fieldmapper.h $(INCDIR)

clean:
	@echo $@;
	rm -f *.o *.so oils_dataloader

