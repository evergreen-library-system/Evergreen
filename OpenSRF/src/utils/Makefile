
UTIL_HEADERS = md5.h logging.h utils.h socket_bundle.h sha.h string_array.h xml_utils.h
UTIL_OBJECTS = md5.o logging.o utils.o socket_bundle.o sha.o string_array.o 

all:	$(UTIL_OBJECTS) copy

copy:
	cp $(UTIL_HEADERS) $(TMPDIR)

logging.o: logging.c logging.h
utils.o: utils.c utils.h
socket_bundle.o: socket_bundle.c socket_bundle.h
md5.o: md5.c md5.h
sha.o: sha.c sha.h
string_array.o: string_array.c string_array.h


clean:
	/bin/rm -f *.o 


