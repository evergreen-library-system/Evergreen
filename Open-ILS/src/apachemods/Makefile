
LDLIBS	+= -lxml2 -lopensrf -lxslt

all:	mod_xmltools.so mod_ils_rest_gateway.so

install:	mod_xmltools-install mod_ils_rest_gateway-install libfieldmapper-install


mod_xmltools.o: mod_xmltools.c mod_xmltools.h
apachetools.o: apachetools.c apachetools.h
xmltools.o:	xmltools.c xmltools.h
json_xml.o:	json_xml.c json_xml.h
fieldmapper_lookup.o:	fieldmapper_lookup.c fieldmapper_lookup.h
ils_rest_gateway.o:	mod_rest_gateway.c mod_rest_gateway.h
	$(CC) -c $(CFLAGS) mod_rest_gateway.c -o $@

fieldmapper_lookup.c:	
	./fieldmapper_lookup-gen.pl fieldmapper_lookup.c


# ------------------------------------------------------

mod_xmltools.so: mod_xmltools.o apachetools.o  xmltools.o 
	echo $@
	$(CC) $(LDFLAGS) $(LDLIBS) -shared -W1 apachetools.o xmltools.o mod_xmltools.o -o $@

libfieldmapper.so:	fieldmapper_lookup.o
	echo $@
	$(CC) $(LDFLAGS) $(LDLIBS) -shared -W1 fieldmapper_lookup.o -o $@

mod_ils_rest_gateway.so:	libfieldmapper.so ils_rest_gateway.o
	echo $@
	$(CC) $(LDFLAGS) $(LDLIBS) -shared -W1 ils_rest_gateway.o -lfieldmapper -o $@

# ------------------------------------------------------


libfieldmapper-install:	libfieldmapper.so
	echo installing libfieldmapper.so
	mkdir -p $(INCLUDEDIR)/
	cp fieldmapper_lookup.h $(INCLUDEDIR)/
	cp libfieldmapper.so $(LIBDIR)/libfieldmapper.so


mod_ils_rest_gateway-install:
	$(APXS2) -i -a -n mod_ils_rest_gateway mod_ils_rest_gateway.so
	echo "-----------------------------------------------";
	echo -e "* Important * : Change httpd.conf from this: \n \
		LoadModule mod_ils_rest_gateway_module modules/mod_ils_rest_gateway.so \n \
		to this: \n \
		LoadModule mod_ils_rest_gateway    modules/mod_ils_rest_gateway.so"
	echo -e "Supported configuration options:\
			\nILSRestGatewayConfig <config-file>"
	echo "-----------------------------------------------";
	echo ""

mod_xmltools-install:
	$(APXS2) -i -a -n mod_xmltools mod_xmltools.so
	echo "-----------------------------------------------";
	echo -e "* Important * : Change httpd.conf from this: \n \
		LoadModule mod_xmltools_module modules/mod_xmltools.so \n \
		to this: \n \
		LoadModule mod_xmltools    modules/mod_xmltools.so"
	echo -e "Supported configuration options:\
			\nXMLToolsDefaultLocale <locale>\
			\nXMLToolsLocaleDir  <web-locale-dir>\
			\nXMLToolsPreXSL <pre_xsl_file>\
			\nXMLToolsPostXSL <post_xsl_file>"
	echo "-----------------------------------------------";
	echo ""

clean:
	echo $@
	/bin/rm -f *.o xmltools mod_xmltools.so libfieldmapper.so mod_ils_rest_gateway.so
	/bin/rm -f fieldmapper_lookup.c

