LDLIBS	+= -lopensrf -lobjson -lxml2
OBJECTS	= jserver-c.o jserver-c_main.o jserver-c_session.o

all: jserver-c 

jserver-c: $(OBJECTS)
#	$(CC) $(LD_OPTS) $(OBJECTS) -o $@

jserver-c_main.o: jserver-c_main.c 
jserver-c.o: jserver-c.c jserver-c.h
jserver-c_session.o: jserver-c_session.c jserver-c_session.h


install: 
	cp jserver-c $(BINDIR)

clean:
	/bin/rm -f *.o jserver-c 

