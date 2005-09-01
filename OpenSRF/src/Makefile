# TOP level 'src' makefile for OpenSRF


export TMPDIR			= $(TMP)/opensrf
export OPENSRF			= opensrf
export BINDIR			= $(PREFIX)/bin
export LIBDIR			= $(PREFIX)/lib
export PERLDIR			= $(LIBDIR)/perl5
export INCLUDEDIR		= $(PREFIX)/include

export LDLIBS			+= 
export LDFLAGS			+= -L $(TMPDIR) -L .
export CFLAGS			+= -g -Wall -O2 -fPIC -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) \
								-I$(LIBXML2_HEADERS)/libxml  -I$(TMP) -I$(TMPDIR)

LIBOPENSRF				= libopensrf.so

OPENSRF_TARGETS = libtransport/transport_session.o \
						libtransport/transport_client.o \
						libtransport/transport_message.o \
						libstack/osrf_app_session.o \
						libstack/osrf_stack.o \
						libstack/osrfConfig.o \
						libstack/osrf_settings.o \
						libstack/osrf_message.o \
						libstack/osrf_prefork.o \
						libstack/osrf_system.o \
						libstack/xml_utils.o \
						utils/socket_bundle.o \
						utils/string_array.o \
						utils/utils.o \
						utils/logging.o \
						utils/md5.o \
						utils/sha.o \

OPENSRF_HEADERS = libtransport/transport_session.h \
						libtransport/transport_client.h \
						libtransport/transport_message.h \
						libstack/osrf_app_session.h \
						libstack/osrf_stack.h \
						libstack/osrfConfig.h \
						libstack/osrf_settings.h \
						libstack/osrf_message.h \
						libstack/osrf_prefork.h \
						libstack/osrf_system.h \
						libstack/xml_utils.h \
						utils/socket_bundle.h \
						utils/string_array.h \
						utils/utils.h \
						utils/logging.h \
						utils/md5.h \
						utils/sha.h \


all: prep libopensrf.so router srfsh jserver gateway

install: install-prep opensrf-install gateway-install	router-install \
		srfsh-install jserver-install perl-install objson-install

prep:
	mkdir -p $(TMPDIR)

libopensrf.so:	objson/libobjson.so
	@echo utils
	make -C utils
	@echo transport
	make -C libtransport
	@echo stack
	make -C libstack
	@echo $@
	$(CC) -shared -W1 $(LDFLAGS) -lobjson $(OPENSRF_TARGETS) -o $(TMPDIR)/$(LIBOPENSRF)


opensrf-install:
	@echo $@
	cp $(TMPDIR)/$(LIBOPENSRF) $(LIBDIR)/$(LIBOPENSRF)
	cp $(OPENSRF_HEADERS) $(INCLUDEDIR)/opensrf/


objson/libobjson.so: 
	@echo $@
	make -C objson

# --------------------------------------------------------------------------------
# BINARIES
# --------------------------------------------------------------------------------
router: libopensrf.so
	@echo $@
	make -C router 

srfsh: libopensrf.so
	@echo $@
	make -C srfsh

gateway:	libopensrf.so
	@echo $@
	make -C gateway

jserver:	libopensrf.so
	@echo $@
	make -C jserver


# --------------------------------------------------------------------------------
# INSTALL
# --------------------------------------------------------------------------------
install-prep:	
	@echo $@
	mkdir -p $(LIBDIR)
	mkdir -p $(BINDIR)
	mkdir -p $(PERLDIR)
	mkdir -p $(INCLUDEDIR)
	mkdir -p $(INCLUDEDIR)/$(OPENSRF)
	mkdir -p $(ETCDIR)
	mkdir -p $(TEMPLATEDIR)

objson-install:	install-prep 
	@echo $@
	make -C objson install

libopensrf-install:	install-prep
	@echo $@
	cp $(TMPDIR)/$(LIBOPENSRF) $(LIBDIR)

gateway-install:	install-prep opensrf-install	
	@echo $@
	make -C gateway install

router-install:	install-prep opensrf-install
	@echo $@
	make -C router install

srfsh-install:	install-prep opensrf-install 
	@echo $@
	make -C srfsh install

jserver-install:	install-prep 
	@echo $@
	make -C jserver install

perl-install:	install-prep
	@echo $@
	cp -r perlmods/* $(PERLDIR)/
	cp ../examples/bootstrap.conf.example $(ETCDIR)
	cp ../bin/opensrf_ctl $(BINDIR)
	cp ../bin/opensrf_all $(BINDIR)
	cp ../examples/opensrf.xml.example $(ETCDIR)
	cp ../examples/opensrf_core.xml.example $(ETCDIR)
	cp ../examples/srfsh.xml.example $(ETCDIR)


# --------------------------------------------------------------------------------
# CLEAN	
# --------------------------------------------------------------------------------
clean:
	@echo $@
	make -C libtransport clean
	make -C libstack clean
	make -C router clean
	make -C gateway clean
	make -C jserver clean
	make -C utils clean
	make -C objson clean
	make -C srfsh clean
	echo "Removing directory [$(TMPDIR)]"
	/bin/rm -rf $(TMPDIR)


