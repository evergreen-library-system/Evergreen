LDLIBS += -lobjson -lopensrf


all:	osrf_math.so osrf_dbmath.so

osrf_math.o: osrf_math.c
osrf_dbmath.o: osrf_dbmath.c

osrf_math.so: osrf_math.o
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) osrf_math.o -o $(TMPDIR)/osrf_math.so

osrf_dbmath.so: osrf_dbmath.o
	$(CC) -shared -W1 $(LDLIBS) $(LDFLAGS) osrf_dbmath.o -o $(TMPDIR)/osrf_dbmath.so

install:
	cp $(TMPDIR)/osrf_math.so $(LIBDIR)/
	cp $(TMPDIR)/osrf_dbmath.so $(LIBDIR)/

clean:
	rm -f *.o *.so
