#JAVA_LIBS = .:lib:ext/json-jdk1.5-2007-05-01.jar:ext/wstx-asl-3.2.1.jar:ext/stax-api-1.0.1.jar:ext/xercesImpl-1.4.4-2.jar
JAVA_LIBDIR = .lib
JAVAC=javac -J-Xmx256m
JAVA=java -Xmx256m 
JAVA_LIBS = .:$(JAVA_LIBDIR):ext/json-jdk1.5-2007-05-01.jar:ext/wstx-asl-3.2.1.jar:ext/stax-api-1.0.1.jar
JAVA_SRC = \
	org/opensrf/net/xmpp/*.java \
	org/opensrf/util/*.java \
	org/opensrf/*.java \
	org/opensrf/test/*.java 

all:
	mkdir -p $(JAVA_LIBDIR)
	$(JAVAC) -d $(JAVA_LIBDIR) -cp $(JAVA_LIBS) $(JAVA_SRC) 2>&1 

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
	$(JAVA) -cp $(JAVA_LIBS) $(JAVA_EXE) $(JAVA_ARGS)

docs:
	find . -name *.java > files;
	javadoc -classpath $(JAVA_LIBS) -d doc @files;
	rm files;

clean:
	rm -r $(JAVA_LIBDIR)
	


