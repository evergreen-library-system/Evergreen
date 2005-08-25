CC_OPTS		+=  -DASSUME_STATELESS 
LD_OPTS += -lxml2 -lopensrf_transport  -lopensrf_stack -lobjson -lc_utils

SOURCES = osrf_message.c osrf_app_session.c osrf_stack.c osrf_system.c osrf_config.c osrf_settings.c
TARGETS = osrf_message.o osrf_app_session.o osrf_stack.o osrf_system.o osrf_config.o osrf_settings.o
HEADERS = osrf_message.h osrf_app_session.h osrf_stack.h osrf_system.h osrf_config.h osrf_settings.h

all: msg libopensrf_stack.so  test

msg: 
	echo "-> $$(pwd)"	

test:	test.o
	echo $@
	$(CC) $(LD_OPTS) test.o xml_utils.o -o $@

test.o:	test.c xml_utils.o
	echo $@
	$(CC) -c $(CC_OPTS) test.c -o $@ 

xml_utils.o:
	echo $@
	cp ../utils/xml_utils.h .
	cp ../utils/xml_utils.c .
	$(CC) -c $(CC_OPTS) xml_utils.c -o $@ 

# -------------------------------------------------------------


libopensrf_stack.so: $(TARGETS)
	echo $@
	$(CC) -shared -W1 $(TARGETS) -o libopensrf_stack.so
	$(CC) -shared -W1 $(TARGETS) -o $(TMPDIR)/libopensrf_stack.so
	cp $(HEADERS) $(TMPDIR)/

osrf_message.o:	osrf_message.c osrf_message.h
	echo $@; $(CC) -c $(CC_OPTS) osrf_message.c -o $@

osrf_app_session.o:	osrf_app_session.c osrf_app_session.h
	echo $@; $(CC) -c $(CC_OPTS) osrf_app_session.c -o $@

osrf_stack.o:	osrf_stack.c osrf_stack.h
	echo $@; $(CC) -c $(CC_OPTS) osrf_stack.c -o $@

osrf_system.o:	osrf_system.c osrf_system.h
	echo $@; $(CC) -c $(CC_OPTS) osrf_system.c -o $@

osrf_config.o:	osrf_config.c osrf_config.h
	echo $@; $(CC) -c $(CC_OPTS) osrf_config.c -o $@

osrf_settings.o:	osrf_settings.c osrf_settings.h
	echo $@; $(CC) -c $(CC_OPTS) osrf_settings.c -o $@

install:
	echo installing libopensrf_stack.so
	cp $(HEADERS) $(INCLUDEDIR)/$(OPENSRF)
	cp $(TMPDIR)/libopensrf_stack.so $(LIBDIR)/

clean:
	/bin/rm -f *.o libopensrf_stack.so test
