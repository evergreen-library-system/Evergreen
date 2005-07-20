# if EXEC_DEFAULT is defined, then srfsh will send all unknown commands to the shell for execution

LD_OPTS	+= -lobjson -lreadline -lxml2 -lopensrf_transport -lopensrf_stack -lncurses -lc_utils -DEXEC_DEFAULT

all: srfsh

install: 
	cp srfsh $(BINDIR)

srfsh:	srfsh.c srfsh.h
	$(CC) $(CC_OPTS) $(LD_OPTS) srfsh.c -o $@

clean:
	/bin/rm -f *.o srfsh
