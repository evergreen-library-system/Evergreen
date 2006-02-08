LDLIBS += -lreadline -loils_utils
all:	oils_requestor

oils_requestor:	oils_requestor.o
oils_requestor-install:
	cp oils_requestor $(BINDIR)
oils_requestor.o:	oils_requestor.c

clean:
	/bin/rm -f *.o oils_requestor
