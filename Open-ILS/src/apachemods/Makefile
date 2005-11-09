
LDLIBS	+= -lxml2 -lopensrf -lxslt

all:	mod_xmlbuilder.so mod_ils_rest_gateway.so

install:	mod_xmlbuilder-install mod_ils_rest_gateway-install libfieldmapper-install


mod_xmlbuilder.o: mod_xmlbuilder.h mod_xmlbuilder.c
apachetools.o: apachetools.c apachetools.h
json_xml.o:	json_xml.c json_xml.h
fieldmapper_lookup.o:	fieldmapper_lookup.c fieldmapper_lookup.h
ils_rest_gateway.o:	mod_rest_gateway.c mod_rest_gateway.h
	$(CC) -c $(CFLAGS) mod_rest_gateway.c -o $@

fieldmapper_lookup.c:	
	./fieldmapper_lookup-gen.pl fieldmapper_lookup.c


# ------------------------------------------------------

mod_xmlbuilder.so: mod_xmlbuilder.o apachetools.o 
	@echo $@
	$(CC) $(LDFLAGS) $(LDLIBS) -shared -W1 apachetools.o mod_xmlbuilder.o -o $@

libfieldmapper.so:	fieldmapper_lookup.o
	@echo $@
	mkdir -p $(TMPDIR)/openils/
	cp fieldmapper_lookup.h $(TMPDIR)/openils/
	$(CC) $(LDFLAGS) $(LDLIBS) -shared -W1 fieldmapper_lookup.o -o $@
	cp libfieldmapper.so $(TMPDIR)/libfieldmapper.so

mod_ils_rest_gateway.so:	libfieldmapper.so ils_rest_gateway.o json_xml.o
	@echo $@
	$(CC) $(LDFLAGS) $(LDLIBS) -shared -W1 json_xml.o ils_rest_gateway.o -lfieldmapper -o $@

# ------------------------------------------------------


libfieldmapper-install:	libfieldmapper.so
	echo installing libfieldmapper.so
	mkdir -p $(INCDIR)/
	@echo "Copying fieldmapper_lookup.h to $(INCDIR)"
	cp fieldmapper_lookup.h $(INCDIR)/
	cp libfieldmapper.so $(LIBDIR)/libfieldmapper.so


mod_ils_rest_gateway-install:
	$(APXS2) -i -a -n ils_rest_gateway mod_ils_rest_gateway.so
	echo "-----------------------------------------------";
	echo -e "* Important * : Change httpd.conf from this: \n \
		LoadModule mod_ils_rest_gateway_module modules/mod_ils_rest_gateway.so \n \
		to this: \n \
		LoadModule mod_ils_rest_gateway    modules/mod_ils_rest_gateway.so"
	echo -e "Supported configuration options:\
			\nILSRestGatewayConfig <config-file>"
	echo "-----------------------------------------------";
	echo ""

mod_xmlbuilder-install:
	$(APXS2) -i -a -n xmlbuilder mod_xmlbuilder.so


clean:
	echo $@
	/bin/rm -f *.o mod_xmlbuilder.so libfieldmapper.so mod_ils_rest_gateway.so
	/bin/rm -f fieldmapper_lookup.c

