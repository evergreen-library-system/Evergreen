JAVA_LIBDIR = .lib
JAVAC = javac -J-Xmx256m
JAVA = java -Xmx256m 
OSRF_HOME = ../../../../OpenSRF/src/java
OSRFJAVA = $(OSRF_HOME)/opensrf.jar
EXT = $(OSRF_HOME)/deps
JAVA_LIBS = .:$(JAVA_LIBDIR):$(OSRFJAVA):$(EXT)/json.jar:$(EXT)/java_memcached-release_2.0.1.jar
JAVA_SRC = \
	org/open_ils/*.java\
	org/open_ils/idl/*.java\
	org/open_ils/util/*.java\
	org/open_ils/test/*.java

all-local:	jar

jar:
	$(MKDIR_P) $(JAVA_LIBDIR)
	$(JAVAC) -d $(JAVA_LIBDIR) -cp $(JAVA_LIBS) $(JAVA_SRC) 2>&1 
	rm -f openils.jar
	echo "creating openils.jar"
	jar cf openils.jar -C .lib org


# only prints the first 30 lines of errors
slim:
	$(MKDIR_P) $(JAVA_LIBDIR)
	$(JAVAC) -d $(JAVA_LIBDIR) -cp $(JAVA_LIBS) $(JAVA_SRC) 2>&1 | head -n 30
	@echo -e "\nTruncating at 30 lines"

check:
	$(MKDIR_P) $(JAVA_LIBDIR)
	$(JAVAC) -Xlint:unchecked -d $(JAVA_LIBDIR) -cp $(JAVA_LIBS) $(JAVA_SRC) 2>&1 | head -n 30
	@echo -e "\nTruncating at 30 lines"

run:
	@$(JAVA) -cp $(JAVA_LIBS):openils.jar $(JAVA_EXE) $(JAVA_ARGS)

deps:
	$(MKDIR_P) ext

docs:
	find . -name *.java > files;
	javadoc -classpath $(JAVA_LIBS) -d doc @files;
	rm files;

clean:
	rm -r $(JAVA_LIBDIR)


