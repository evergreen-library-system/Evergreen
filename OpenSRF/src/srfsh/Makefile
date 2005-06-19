LD_OPTS	+= -lobjson -lreadline -lxml2 -lopensrf_transport -lopensrf_stack -ljson -lncurses -lc_utils

all: srfsh

install: 
	cp srfsh $(BINDIR)

srfsh:	srfsh.c srfsh.h
	$(CC) $(CC_OPTS) $(LD_OPTS) srfsh.c -o $@

clean:
	/bin/rm -f *.o srfsh
