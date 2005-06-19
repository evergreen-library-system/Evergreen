CC_OPTS		+=  -DASSUME_STATELESS
EXE_LD_OPTS += -lxml2 -lopensrf_transport  -lopensrf_stack -lobjson -ljson -lc_utils

SOURCES = osrf_message.c osrf_app_session.c osrf_stack.c osrf_system.c 
TARGETS = osrf_message.o osrf_app_session.o osrf_stack.o osrf_system.o 
HEADERS = osrf_message.h osrf_app_session.h osrf_stack.h osrf_system.h 

all: lib 

lib: $(SOURCES) $(HEADERS)
	$(CC) -c $(CC_OPTS)	$(SOURCES)  
	$(CC) -shared -W1 $(TARGETS) -o $(TMPDIR)/libopensrf_stack.so
	cp $(HEADERS) $(TMPDIR)/

install:
	cp $(HEADERS) $(INCLUDEDIR)/$(OPENSRF)
	cp $(TMPDIR)/libopensrf_stack.so $(LIBDIR)/

clean:
	/bin/rm -f *.o 
