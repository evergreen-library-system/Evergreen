SO=mod_xinclude.so

# --------------------------------------------------------
TMPDIR = /tmp/ilstmp/opensrf
LIBDIR = /openils/lib
CC_OPTS = -Wall -O2 -fPIC -I /usr/include/libxml2 -I /opt/include
LD_OPTS = -lxml2 
APXS2 = /opt/bin/apxs
# --------------------------------------------------------

all: $(SO)

install: 
	cp $(TMPDIR)/$(SO) $(LIBDIR)/$(SO)
	$(APXS2) -i -a -n xinclude $(LIBDIR)/$(SO)

$(SO): mod_xinclude.c	
	$(CC) -c $(CC_OPTS)  mod_xinclude.c
	$(CC) $(LD_OPTS) -shared -W1 mod_xinclude.o -o $(TMPDIR)/$(SO)

clean:
	/bin/rm -f *.o *.so
