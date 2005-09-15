# OSRF_LOG_PARAMS log all incoming method params at OSRF_INFO log level. 
# OSRF_STRICT_PARAMS instructs the app handler to return an error if the number of method arguments
#	provided to any method is not at least as large as the 'argc' setting for the method

CFLAGS	+=  -DASSUME_STATELESS  -DOSRF_LOG_PARAMS -DOSRF_STRICT_PARAMS -rdynamic -fno-strict-aliasing
LDLIBS	+= -lxml2 -lobjson -ldl -lmemcache

TARGETS = osrf_message.o \
			 osrf_app_session.o \
			 osrf_stack.o \
			 osrf_system.o \
			 osrf_settings.o \
			 osrf_prefork.o \
			 osrfConfig.o \
			 osrf_application.o \
			 osrf_cache.o \
			 osrf_log.o \
			 xml_utils.o

HEADERS = osrf_message.h \
			 osrf_app_session.h \
			 osrf_stack.h \
			 osrf_system.h \
			 osrf_settings.h \
			 osrf_prefork.h \
			 osrfConfig.h \
			 osrf_application.h \
			 osrf_cache.h \
			 osrf_log.h \
			 xml_utils.h

all: xml_utils.o $(TARGETS) copy 

xml_utils.o:
	cp ../utils/xml_utils.h .
	cp ../utils/xml_utils.c .
	$(CC) -c $(CFLAGS) xml_utils.c -o $@ 

copy:
	cp $(HEADERS) $(TMPDIR)/

osrf_message.o:	osrf_message.c osrf_message.h
osrf_app_session.o:	osrf_app_session.c osrf_app_session.h
osrf_stack.o:	osrf_stack.c osrf_stack.h
osrf_system.o:	osrf_system.c osrf_system.h
osrf_settings.o:	osrf_settings.c osrf_settings.h
osrf_prefork.o:	osrf_prefork.c osrf_prefork.h
osrfConfig.o:	osrfConfig.c osrfConfig.h xml_utils.o
osrf_application.o: osrf_application.c osrf_application.h
osrf_cache.o:	osrf_cache.c osrf_cache.h
osrf_log.o:	osrf_log.c osrf_log.h

clean:
	/bin/rm -f *.o libopensrf_stack.so xml_utils.h xml_utils.c
