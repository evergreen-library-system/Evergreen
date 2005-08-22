# ---------------------------------------------------------------------------------
#CC_OPTS = -I /usr/include/libxml2 -I /opt/include -g
#APXS2 = /home/erickson/sandbox/apache2/bin/apxs
# ---------------------------------------------------------------------------------

LD_OPTS	+= -lxml2 -lc_utils -lxslt

all: mod_xmltools.so

install:	mod_xmltools-install

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

mod_xmltools-install:
	echo $@
	$(APXS2) -i -a -n mod_xmltools mod_xmltools.so
	@echo "-----------------------------------------------";
	@echo -e "* Important * : Change httpd.conf from this: \n \
		LoadModule mod_xmltools_module modules/mod_xmltools.so \n \
		to this: \n \
		LoadModule mod_xmltools    modules/mod_xmltools.so"
	@echo -e "Supported configuration options:\
			\nXMLToolsDefaultLocale <locale>\
			\nXMLToolsLocaleDir  <web-locale-dir>\
			\nXMLToolsPreXSL <pre_xsl_file>\
			\nXMLToolsPostXSL <post_xsl_file>"
	@echo "-----------------------------------------------";
	@sleep 3;

clean:
	echo $@
	/bin/rm -f *.o xmltools mod_xmltools.so
