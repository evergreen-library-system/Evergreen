# if EXEC_DEFAULT is defined, then srfsh will send all unknown commands to the shell for execution

LDLIBS	+= -lobjson -lreadline -lxml2 -lopensrf -lncurses 
LDFLAGS	+= -DEXEC_DEFAULT

all: srfsh

srfsh:	srfsh.o
srfsh.o:	srfsh.c srfsh.h

install: 
	cp srfsh $(BINDIR)

clean:
	/bin/rm -f *.o srfsh
