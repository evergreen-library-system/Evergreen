LDLIBS	+= -lopensrf -lobjson -lxml2
CFLAGS	+= -D_GNU_SOURCE

all: chopchop

chopchop: osrf_chat.o osrf_chat_main.o
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) osrf_chat.o osrf_chat_main.o -o $@

osrf_chat.o: osrf_chat.c osrf_chat.h
osrf_chat_main.o: osrf_chat_main.c

install: 
	cp chopchop $(BINDIR)

clean:
	/bin/rm -f *.o chopchop

