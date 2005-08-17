# -------------------------------------------------------------------------------
#CC_OPTS = -Wall -O2 -I /opt/include -I /openils/include -I /usr/include/libxml2
#LD_OPTS = -L /openils/lib
#APXS2 = /opt/bin/apxs
#TMPDIR = /tmp/blah
#ETCDIR = /tmp/blah
# -------------------------------------------------------------------------------

CC_OPTS	+= -DASSUME_STATELESS
LD_OPTS	+= -lc_utils -lobjson -lxml2 -lopensrf_transport -lopensrf_stack

all: msg  ils_gateway rest_gateway

ils_gateway: libmod_ils_gateway.so
rest_gateway: libmod_ils_rest_gateway.so

msg:
	echo "-> $$(pwd)"	

install: 
	cp gateway.xml.example $(ETCDIR)
	echo installing ils_gateway
	$(APXS2) -i -a -n ils_gateway libmod_ils_gateway.so
	echo installing ils_rest_gateway
	$(APXS2) -i -a -n ils_rest_gateway libmod_ils_rest_gateway.so

libmod_ils_gateway.so:	mod_ils_gateway.o
	echo $@
	$(CC) $(LD_OPTS) -shared -W1 mod_ils_gateway.o -o libmod_ils_gateway.so


libmod_ils_rest_gateway.so:	rest_xml.o mod_ils_gateway.c	
	echo $@
	$(CC) -c -DRESTGATEWAY $(CC_OPTS) -o mod_ils_rest_gateway.o mod_ils_gateway.c
	$(CC) $(LD_OPTS) -shared -W1 rest_xml.o mod_ils_rest_gateway.o -o libmod_ils_rest_gateway.so

rest_xml.c:	
	./fieldmapper-c-xml-out.pl rest_xml.h rest_xml.c

rest_xml.o:	rest_xml.c rest_xml.h
	echo $@
	$(CC) -c $(CC_OPTS) -o rest_xml.o rest_xml.c

mod_ils_gateway.o:	mod_ils_gateway.c	
	echo $@
	$(CC) -c $(CC_OPTS)  mod_ils_gateway.c

clean:
	/bin/rm -f *.o *.so rest_xml.c rest_xml.h
