LD_OPTS	+= -lc_utils

#FM_HEADER	= fieldmapper.h
#FM_SOURCE	= fieldmapper.c
#HEADER_DIR  = $(INCLUDE)/opensrf



UTIL_SOURCES = logging.c utils.c socket_bundle.c md5.c sha.c string_array.c
UTIL_HEADERS = logging.h utils.h socket_bundle.h md5.h sha.h string_array.h
UTIL_OBJECTS = logging.o utils.o socket_bundle.o md5.o sha.o string_array.o


all: util

install: 
	cp $(UTIL_HEADERS) $(INCLUDEDIR)/
	cp $(TMPDIR)/libc_utils.so $(LIBDIR)/

util: $(UTIL_OBJECTS) 
	$(CC) -shared -W1 $(UTIL_OBJECTS) -o $(TMPDIR)/libc_utils.so
	cp $(UTIL_HEADERS) $(TMPDIR)/

logging.o: logging.c logging.h
	$(CC) -c $(CC_OPTS) logging.c -o $@ 

utils.o: utils.c utils.h
	$(CC) -c $(CC_OPTS) utils.c -o $@ 

socket_bundle.o: socket_bundle.c socket_bundle.h
	$(CC) -c $(CC_OPTS) socket_bundle.c -o $@ 

md5.o: md5.c md5.h
	$(CC) -c $(CC_OPTS) md5.c -o $@ 

sha.o: sha.c sha.h
	$(CC) -c $(CC_OPTS) sha.c -o $@ 

string_array.o: string_array.c string_array.h
	$(CC) -c $(CC_OPTS) string_array.c -o $@ 

clean:
	/bin/rm -f *.o socket_test




#fieldmapper: fieldmapper-c.pl
#perl fieldmapper-c.pl $(FM_HEADER) $(FM_SOURCE)
#$(CC) -c $(CC_OPTS) fieldmapper.c -o fieldmapper.o
#$(CC) -shared -W1 fieldmapper.o -o $(LIBDIR)/libopensrf_fm.so
#cp $(FM_HEADER) $(HEADER_DIR)/


