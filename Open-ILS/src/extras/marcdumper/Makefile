#
# This utility code requires libxml2 and yaz version 2.0.34 or greater.
#

CC = gcc
LD = -lxml2 -lyaz 
COMP = -O2 -I /usr/include/libxml2/ 

all: marcdumper

marcdumper:  marcdumper.c
	$(CC) marcdumper.c $(COMP) $(LD) -o $@

install: 
	cp marcdumper $(BINDIR)

clean:
	/bin/rm -f *.o marcdumper


