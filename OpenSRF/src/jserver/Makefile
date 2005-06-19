LD_OPTS	+= -lc_utils -lxml2
OBJECTS		= jserver-c.o jserver-c_main.o jserver-c_session.o


all: jserver-c 

jserver-c: $(OBJECTS)
	$(CC) $(LD_OPTS) $(OBJECTS) -o $@

jserver-c_main.o: jserver-c_main.c 
	$(CC) -c $(CC_OPTS) jserver-c_main.c -o $@

jserver-c.o: jserver-c.c jserver-c.h
	$(CC) -c $(CC_OPTS) jserver-c.c -o $@

jserver-c_session.o: jserver-c_session.c jserver-c_session.h
	$(CC) -c $(CC_OPTS) jserver-c_session.c -o $@


install: 
	cp jserver-c $(BINDIR)


clean:
	/bin/rm -f *.o jserver-c 

