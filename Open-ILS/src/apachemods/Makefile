# ---------------------------------------------------------------------------------
#CC_OPTS = -I /usr/include/libxml2 -I /opt/include -g
#APXS2 = /home/erickson/sandbox/apache2/bin/apxs
# ---------------------------------------------------------------------------------

LD_OPTS	+= -lxml2 -lc_utils

all: mod_xmltools.so

install:	mod_xmltools-install

mod_xmltools.so: apachetools.o  xmltools.o
	$(CC) -c $(CC_OPTS) mod_xmltools.c 
	$(CC) $(LD_OPTS) -shared -W1 apachetools.o xmltools.o mod_xmltools.o -o $@

apachetools.o: apachetools.c apachetools.h
	$(CC) -c $(CC_OPTS)  apachetools.c -o $@

xmltools.o:	xmltools.c xmltools.h	
	$(CC) -c $(CC_OPTS) xmltools.c -o $@


mod_xmltools-install:
	$(APXS2) -i -a -n mod_xmltools mod_xmltools.so
	@echo "-----------------------------------------------";
	@echo -e "* Important * : Change httpd.conf from this: \n \
		LoadModule mod_xmltools_module modules/mod_xmltools.so \n \
		to this: \n \
		LoadModule mod_xmltools    modules/mod_xmltools.so"
	@echo "Also, you can add \nXMLToolsDefaultLocale <locale>\nand\n \
			XMLToolsLocaleDir  <web-locale-dir> to httpd.conf"
	@echo "-----------------------------------------------";
	@sleep 3;

clean:
	/bin/rm -f *.o xmltools
