# OSRF_LOG_PARAMS log all incoming method params at OSRF_INFO log level. 
# OSRF_STRICT_PARAMS instructs the app handler to return an error if the number of method arguments
#	provided to any method is not at least as large as the 'argc' setting for the method

CFLAGS	+=  -rdynamic -fno-strict-aliasing -fPIC

TARGETS = strndup.o strnlen.o
HEADERS = strndup.h strnlen.h

all: libfreebsd_str_compat.so $(TARGETS)

libfreebsd_str_compat.so: $(TARGETS)
	$(CC) -shared -W1 $(TARGETS) -o $@

strndup.o:	strndup.c strndup.h
strnlen.o:	strnlen.c strnlen.h

clean:
	/bin/rm -f *o

