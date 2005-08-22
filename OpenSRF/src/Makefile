# TOP level 'src' makefile for OpenSRF
#
#

# Change to suit...
#export PREFIX				= /usr
#export APXS2					= /pines/apps/apache2/bin/apxs
#export TMP					= /tmp/opensrf_build
#export APACHE2_HEADERS	= /pines/apps/apache2/include 


export TMPDIR			= $(TMP)/opensrf
export OPENSRF			= opensrf
export BINDIR			= $(PREFIX)/bin
export LIBDIR			= $(PREFIX)/lib
export PERLDIR			= $(LIBDIR)/perl5
export INCLUDEDIR		= $(PREFIX)/include
export CC				= gcc
export LD_OPTS			= -L $(TMPDIR) -L .
export CC_OPTS			= -g -Wall -O2 -fPIC -I$(LIBXML2_HEADERS) -I$(APACHE2_HEADERS) \
								-I$(LIBXML2_HEADERS)/libxml  -I$(TMP) -I$(TMPDIR)


all: prep router srfsh jserver gateway rest_gateway

install: install-prep transport-install stack-install gateway-install	\
		router-install srfsh-install jserver-install perl-install			\
		objson-install utils-install info

prep:
	mkdir -p $(TMPDIR)

# --------------------------------------------------------------------------------
# LIBS 
# --------------------------------------------------------------------------------
c_utils: prep
	make -C utils

transport: c_utils
	make -C libtransport

objson: c_utils
	make -C objson

stack: objson transport 
	make -C libstack


# --------------------------------------------------------------------------------
# BINARIES
# --------------------------------------------------------------------------------
router: stack 
	make -C router 

srfsh: stack
	make -C srfsh

gateway:	stack 
	make -C gateway

rest_gateway:	stack 
	make -e -C gateway rest_gateway

jserver: c_utils
	make -C jserver


# --------------------------------------------------------------------------------
# INSTALL
# --------------------------------------------------------------------------------
install-prep:	
	@echo "Creating install directories"
	mkdir -p $(LIBDIR)
	mkdir -p $(BINDIR)
	mkdir -p $(PERLDIR)
	mkdir -p $(INCLUDEDIR)
	mkdir -p $(INCLUDEDIR)/$(OPENSRF)
	mkdir -p $(ETCDIR)
	mkdir -p $(TEMPLATEDIR)

transport-install:	install-prep utils-install
	make -C libtransport install

utils-install:	install-prep
	make -C utils install

objson-install:	install-prep utils-install
	make -C objson install

stack-install:	install-prep transport-install  objson-install
	make -C libstack install

gateway-install:	install-prep stack-install	
	make -C gateway install

router-install:	install-prep stack-install
	make -C router install

srfsh-install:	install-prep stack-install 
	make -C srfsh install

jserver-install:	install-prep utils-install
	make -C jserver install

perl-install:	install-prep
	cp -r perlmods/* $(PERLDIR)/
	cp ../examples/bootstrap.conf.example $(ETCDIR)
	cp ../bin/opensrf_ctl $(BINDIR)
	cp ../bin/opensrf_all $(BINDIR)
	cp ../examples/opensrf.xml.example $(ETCDIR)
	cp ../examples/opensrf_core.xml.example $(ETCDIR)


# --------------------------------------------------------------------------------
# INFO
# --------------------------------------------------------------------------------
info:
	@echo
	@echo "OpenSRF is installed in $(PREFIX)"
	@echo ""
	@echo "It may be helpful to set some environment variables if the install "
	@echo "was set to a non-standard location.  These include:"
	@echo ""
	@echo "export LD_LIBRARY_PATH=$(LIBDIR):\$$LD_LIBRARY_PATH"
	@echo "export PERL5LIB=$(PERLDIR):\$$PERL5LIB"
	@echo "export PATH=$(BINDIR):\$$PATH"
	@echo ""


# --------------------------------------------------------------------------------
# CLEAN	
# --------------------------------------------------------------------------------
clean:
	make -C libtransport clean
	make -C libstack clean
	make -C router clean
	make -C gateway clean
	make -C jserver clean
	make -C utils clean
	make -C objson clean
	make -C srfsh clean
	/bin/rm -rf $(TMPDIR)


