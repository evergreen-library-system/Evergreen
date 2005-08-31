# ------------------------------------------------------------------------
#CC_OPTS = -O2 -Wall 
#TMPDIR = ./tmp
# ------------------------------------------------------------------------


UTIL_SOURCES = logging.c utils.c socket_bundle.c md5.c sha.c string_array.c
UTIL_HEADERS = logging.h utils.h socket_bundle.h md5.h sha.h string_array.h
UTIL_OBJECTS = logging.o utils.o socket_bundle.o md5.o sha.o string_array.o

all:	msg libc_utils.so 

msg:
	echo "-> $$(pwd)"	


install: 
	echo installing libc_utils.so
	cp $(UTIL_HEADERS) $(INCLUDEDIR)/$(OPENSRF)/
	cp xml_utils.h $(INCLUDEDIR)/$(OPENSRF)/
	cp $(TMPDIR)/libc_utils.so $(LIBDIR)/

libc_utils.so: $(UTIL_OBJECTS) 
	@echo $@
	$(CC) -shared -W1 $(UTIL_OBJECTS) -o libc_utils.so
	$(CC) -shared -W1 $(UTIL_OBJECTS) -o $(TMPDIR)/libc_utils.so
	cp $(UTIL_HEADERS) $(TMPDIR)/

logging.o: logging.c logging.h
	@echo $@
	$(CC) -c $(CC_OPTS) logging.c -o $@ 

utils.o: utils.c utils.h
	@echo $@
	$(CC) -c $(CC_OPTS) utils.c -o $@ 

socket_bundle.o: socket_bundle.c socket_bundle.h
	@echo $@
	$(CC) -c $(CC_OPTS) socket_bundle.c -o $@ 

md5.o: md5.c md5.h
	@echo $@
	$(CC) -c $(CC_OPTS) md5.c -o $@ 

sha.o: sha.c sha.h
	@echo $@
	$(CC) -c $(CC_OPTS) sha.c -o $@ 

string_array.o: string_array.c string_array.h
	@echo $@
	$(CC) -c $(CC_OPTS) string_array.c -o $@ 


clean:
	/bin/rm -f *.o socket_test libc_utils.so test




#fieldmapper: fieldmapper-c.pl
#perl fieldmapper-c.pl $(FM_HEADER) $(FM_SOURCE)
#$(CC) -c $(CC_OPTS) fieldmapper.c -o fieldmapper.o
#$(CC) -shared -W1 fieldmapper.o -o $(LIBDIR)/libopensrf_fm.so
#cp $(FM_HEADER) $(HEADER_DIR)/


