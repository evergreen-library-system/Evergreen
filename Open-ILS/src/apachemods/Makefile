# ---------------------------------------------------------------------------------
#CC_OPTS = -I /usr/include/libxml2 -I /opt/include -g
#APXS2 = /home/erickson/sandbox/apache2/bin/apxs
# ---------------------------------------------------------------------------------

LD_OPTS	+= -lxml2 -lc_utils -lxslt

all:	mod_xmltools.so mod_ils_rest_gateway.so

install:	mod_xmltools-install mod_ils_rest_gateway-install libfieldmapper-install

mod_xmltools.so: apachetools.o  xmltools.o mod_xmltools.c mod_xmltools.h
	echo $@
	$(CC) -c $(CC_OPTS) mod_xmltools.c 
	$(CC) $(LD_OPTS) -shared -W1 apachetools.o xmltools.o mod_xmltools.o -o $@

apachetools.o: apachetools.c apachetools.h
	echo $@
	$(CC) -c $(CC_OPTS)  apachetools.c -o $@

xmltools.o:	xmltools.c xmltools.h	
	echo $@
	$(CC) -c $(CC_OPTS) xmltools.c -o $@

fieldmapper_lookup.c:	fieldmapper_lookup.h
	./fieldmapper_lookup-gen.pl fieldmapper_lookup.c

json_xml.o:	json_xml.c json_xml.h
	echo $@
	$(CC) -c $(CC_OPTS) json_xml.c -o $@

fieldmapper_lookup.o:	fieldmapper_lookup.c fieldmapper_lookup.h
	echo $@
	$(CC) -c $(CC_OPTS) fieldmapper_lookup.c -o $@

libfieldmapper.so:	fieldmapper_lookup.o
	echo $@
	$(CC) $(LD_OPTS) -shared -W1 fieldmapper_lookup.o -o $@

libfieldmapper-install:	libfieldmapper.so
	echo installing libfieldmapper.so
	mkdir -p $(INCLUDEDIR)/
	cp fieldmapper_lookup.h $(INCLUDEDIR)/
	cp libfieldmapper.so $(LIBDIR)/libfieldmapper.so

ils_rest_gateway.o:     mod_rest_gateway.c mod_rest_gateway.h fieldmapper_lookup.h
	echo $@
	$(CC) -c $(CC_OPTS) mod_rest_gateway.c -o $@

mod_ils_rest_gateway.so:     libfieldmapper.so ils_rest_gateway.o
	echo $@
	$(CC) $(LD_OPTS) -shared -W1 ils_rest_gateway.o -lfieldmapper -o $@


mod_ils_rest_gateway-install:
	echo $@
	$(APXS2) -i -a -n mod_ils_rest_gateway mod_ils_rest_gateway.so
	echo "-----------------------------------------------";
	echo -e "* Important * : Change httpd.conf from this: \n \
		LoadModule mod_ils_rest_gateway_module modules/mod_ils_rest_gateway.so \n \
		to this: \n \
		LoadModule mod_ils_rest_gateway    modules/mod_ils_rest_gateway.so"
	echo -e "Supported configuration options:\
			\nILSRestGatewayConfig <config-file>\
	echo "-----------------------------------------------";
	echo ""

mod_xmltools-install:
	echo $@
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
