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


all: test prep router srfsh jserver gateway

test: test
	echo "TEST TEST TEST"

install: install-prep transport-install stack-install gateway-install	\
		router-install srfsh-install jserver-install perl-install			\
		objson-install utils-install bin-install info

prep:
	mkdir -p $(TMPDIR)

# --------------------------------------------------------------------------------
# LIBS 
# --------------------------------------------------------------------------------
c_utils: prep
	echo APXS2=$(APXS2) PREFIX=$(PREFIX) TMP=$(TMP) APCHE2_HEADERS=$(APACHE2_HEADERS) LIBXML2_HEADERS=$(LIBXML2_HEADERS)
	@echo -e "\n + c_utils"
	make -C utils

transport: c_utils
	@echo -e "\n + transport"
	make -C libtransport

objson: c_utils
	@echo -e "\n + objson"
	make -C objson

stack: objson transport 
	@echo -e "\n + stack"
	make -C libstack


# --------------------------------------------------------------------------------
# BINARIES
# --------------------------------------------------------------------------------
router: stack 
	@echo -e "\n + router"
	make -C router 

srfsh: stack
	@echo -e "\n + srfsh"
	make -C srfsh

gateway:	stack 
	@echo -e "\n + gateway"
	make -C gateway

jserver: c_utils
	@echo -e "\n + jserver"
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

bin-install: install-prep
	cp ../bin/opensrf_ctl $(BINDIR)


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
	@echo "Cleaning..."
	make -C libtransport clean
	make -C libstack clean
	make -C router clean
	make -C gateway clean
	make -C jserver clean
	make -C utils clean
	make -C objson clean
	make -C srfsh clean
	/bin/rm -rf $(TMPDIR)


