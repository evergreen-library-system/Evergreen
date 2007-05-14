# OSRF_LOG_PARAMS log all incoming method params at OSRF_INFO log level. 
# OSRF_STRICT_PARAMS instructs the app handler to return an error if the number of method arguments
#	provided to any method is not at least as large as the 'argc' setting for the method

CFLAGS	+=  -DASSUME_STATELESS  -DOSRF_LOG_PARAMS -DOSRF_STRICT_PARAMS -rdynamic -fno-strict-aliasing -I.
LDLIBS	+= -lxml2  -ldl -lmemcache

TARGETS = osrf_message.o \
			 osrf_app_session.o \
			 osrf_stack.o \
			 osrf_system.o \
			 osrf_settings.o \
			 osrf_prefork.o \
			 osrfConfig.o \
			 osrf_application.o \
			 osrf_cache.o \
			 osrf_transgroup.o \
			 osrf_list.o \
			 osrf_hash.o \
			 xml_utils.o \
			 osrf_hash.o \
			 osrf_json_object.o \
			 osrf_json_parser.o \
			 osrf_json_tools.o \
			 legacy_json.o \
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
			 osrf_transgroup.h \
			 osrf_list.h \
			 osrf_hash.h \
			 osrf_json.h \
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
osrf_list.o:	osrf_list.c osrf_list.h
osrf_hash.o:	osrf_hash.c osrf_hash.h
osrf_json_object.o:	osrf_json_object.c osrf_json.h osrf_json_utils.h
osrf_json_parser.o:	osrf_json_parser.c osrf_json.h osrf_json_utils.h
osrf_json_tools.o:	osrf_json_tools.c osrf_json.h osrf_json_utils.h
legacy_json.o:	legacy_json.c osrf_json.h osrf_json_utils.h

clean:
	/bin/rm -f *.o libopensrf_stack.so xml_utils.h xml_utils.c opensrf

