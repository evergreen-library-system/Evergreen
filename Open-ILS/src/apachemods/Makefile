
LDLIBS	+= -lxml2 -lopensrf -lxslt

all:	mod_xmlent.so libfieldmapper.so

install: libfieldmapper-install mod_xmlent-install


apachetools.o: 
	cp ../../../OpenSRF/src/gateway/apachetools.o .

json_xml.o:	json_xml.c json_xml.h

fieldmapper_lookup.o:	fieldmapper_lookup.c fieldmapper_lookup.h 


fieldmapper_lookup.c:	
	./fieldmapper_lookup-gen.pl fieldmapper_lookup.c


mod_xmlent.o:	mod_xmlent.c
mod_xmlent.so: mod_xmlent.o
	@echo $@
	$(CC) $(LDFLAGS) $(LDLIBS) -shared -W1 mod_xmlent.o -lexpat -o $@


# ------------------------------------------------------

libfieldmapper.so:	fieldmapper_lookup.o
	@echo $@
	mkdir -p $(TMPDIR)/openils/
	cp fieldmapper_lookup.h $(TMPDIR)/openils/
	$(CC) $(LDFLAGS) $(LDLIBS) -shared -W1 fieldmapper_lookup.o -o $@
	cp libfieldmapper.so $(TMPDIR)/libfieldmapper.so

# ------------------------------------------------------


libfieldmapper-install:	libfieldmapper.so
	echo installing libfieldmapper.so
	mkdir -p $(INCDIR)/
	@echo "Copying fieldmapper_lookup.h to $(INCDIR)"
	cp fieldmapper_lookup.h $(INCDIR)/
	cp libfieldmapper.so $(LIBDIR)/libfieldmapper.so


mod_xmlent-install:
	$(APXS2) -i -a -n xmlent mod_xmlent.so


clean:
	echo $@
	/bin/rm -f *.o *.so 
	/bin/rm -f fieldmapper_lookup.c


