LDLIBS	+= -lxml2 -lopensrf -lxslt

all:	mod_xmlent.so

install: mod_xmlent-install

mod_xmlent.o:	mod_xmlent.c
mod_xmlent.so: mod_xmlent.o
	@echo $@
	$(CC) $(LDFLAGS) $(LDLIBS) -shared -W1 mod_xmlent.o -lexpat -o $@

mod_xmlent-install:
	$(APXS2) -i -a -n xmlent mod_xmlent.so


clean:
	echo $@
	/bin/rm -f *.o *.so 
