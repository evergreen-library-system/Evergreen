JAVA_LIBDIR = .lib
JAVAC = javac -J-Xmx256m
JAVA = java -Xmx256m 
OSRF_HOME = ../../../../../OpenSRF/trunk/src/java
OSRFJAVA = $(OSRF_HOME)/opensrf.jar
EXT = $(OSRF_HOME)/ext
JAVA_LIBS = .:$(JAVA_LIBDIR):$(OSRFJAVA):$(EXT)/json-jdk1.5-2007-05-01.jar:$(EXT)/wstx-lgpl-3.2.1.jar:$(EXT)/stax-api-1.0.1.jar:$(EXT)/java_memcached-release_1.5.1.jar
JAVA_SRC = \
	org/open_ils/*.java\
	org/open_ils/idl/*.java\
	org/open_ils/util/*.java\
	org/open_ils/test/*.java

all-local:	jar

jar:
	mkdir -p $(JAVA_LIBDIR)
	$(JAVAC) -d $(JAVA_LIBDIR) -cp $(JAVA_LIBS) $(JAVA_SRC) 2>&1 
	rm -f openils.jar
	echo "creating openils.jar"
	jar cf openils.jar -C .lib org


# only prints the first 30 lines of errors
slim:
	mkdir -p $(JAVA_LIBDIR)
	$(JAVAC) -d $(JAVA_LIBDIR) -cp $(JAVA_LIBS) $(JAVA_SRC) 2>&1 | head -n 30
	@echo -e "\nTruncating at 30 lines"

check:
	mkdir -p $(JAVA_LIBDIR)
	$(JAVAC) -Xlint:unchecked -d $(JAVA_LIBDIR) -cp $(JAVA_LIBS) $(JAVA_SRC) 2>&1 | head -n 30
	@echo -e "\nTruncating at 30 lines"

run:
	@$(JAVA) -cp $(JAVA_LIBS):openils.jar $(JAVA_EXE) $(JAVA_ARGS)

deps:
	mkdir -p ext

docs:
	find . -name *.java > files;
	javadoc -classpath $(JAVA_LIBS) -d doc @files;
	rm files;

clean:
	rm -r $(JAVA_LIBDIR)
	


