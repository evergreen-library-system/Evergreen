LDLIBS += -lobjson -lopensrf


all:	osrf_math.so

osrf_math.o: osrf_math.c

osrf_math.so: osrf_math.o
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) osrf_math.o -o $(TMPDIR)/osrf_math.so

install:
	cp $(TMPDIR)/osrf_math.so $(LIBDIR)/

clean:
	rm -f *.o *.so
