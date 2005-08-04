LD_OPTS	+= -lxml2 -lc_utils

all: mod_xmltools.so

mod_xmltools.so: apachetools.o  xmltools.o
	$(CC) -c $(CC_OPTS) mod_xmltools.c 
	$(CC) $(LD_OPTS) -shared -W1 apachetools.o xmltools.o mod_xmltools.o -o $@

apachetools.o: apachetools.c apachetools.h
	$(CC) -c $(CC_OPTS)  apachetools.c -o $@

xmltools.o:	xmltools.c xmltools.h	
	$(CC) -c $(CC_OPTS) xmltools.c -o $@


install:
	$(APXS2) -i -a -n mod_xmltools mod_xmltools.so
	@echo "-----------------------------------------------";
	@echo -e "* Important * : Change httpd.conf from this: \n \
		LoadModule mod_xmltools_module modules/mod_xmltools.so \n \
		to this: \n \
		LoadModule mod_xmltools    modules/mod_xmltools.so"
	@echo "-----------------------------------------------";
	@sleep 3;

clean:
	/bin/rm -f *.o xmltools
