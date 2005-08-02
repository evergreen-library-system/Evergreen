CC_OPTS	+= -DASSUME_STATELESS
LD_OPTS	+= -lc_utils -lobjson -lxml2 -lopensrf_transport -lopensrf_stack

all: libmod_ils_gateway.so
rest_gateway: libmod_ils_rest_gateway.so

install: 
	cp $(TMPDIR)/libmod_ils_gateway.so $(LIBDIR)/libmod_ils_gateway.so
	cp gateway.xml.example $(ETCDIR)
	$(APXS2) -i -a -n ils_gateway $(LIBDIR)/libmod_ils_gateway.so

libmod_ils_gateway.so: mod_ils_gateway.c	
	$(CC) -c $(CC_OPTS)  mod_ils_gateway.c
	$(CC) $(LD_OPTS) -shared -W1 mod_ils_gateway.o -o $(TMPDIR)/libmod_ils_gateway.so

libmod_ils_rest_gateway.so: mod_ils_gateway.c	
	./fieldmapper-c-xml-out.pl rest_xml.h rest_xml.c
	$(CC) -c $(CC_OPTS) -o rest_xml.o rest_xml.c
	$(CC) -c -DRESTGATEWAY $(CC_OPTS) -o mod_ils_rest_gateway.o mod_ils_gateway.c
	$(CC) $(LD_OPTS) -shared -W1 mod_ils_rest_gateway.o -o $(TMPDIR)/libmod_ils_rest_gateway.so

clean:
	/bin/rm -f *.o *.so
