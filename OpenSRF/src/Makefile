# TOP level 'src' makefile for OpenSRF
#
#

# Change to suit...
export PREFIX				= /pines
export APXS					= /pines/apps/apache2/bin/apxs
export TMP					= /tmp/opensrf_build
export APACHE_HEADERS	= /pines/apps/apache2/include 


export TMPDIR			= $(TMP)/opensrf
export OPENSRF			= opensrf
export BINDIR			= $(PREFIX)/bin
export LIBDIR			= $(PREFIX)/lib
export PERLDIR			= $(LIBDIR)/perl5
export INCLUDEDIR		= $(PREFIX)/include
export CC				= gcc
export LD_OPTS			= -L $(TMPDIR) -L .
export CC_OPTS			= -Wall -O2 -fPIC -I/usr/include/libxml2 -I$(APACHE_HEADERS) \
								-I/usr/include/libxml2/libxml  -I$(TMP) -I$(TMPDIR)


all: prep router srfsh jserver gateway

install: install-prep transport-install stack-install gateway-install	\
		router-install srfsh-install jserver-install perl-install			\
		libjson-install objson-install utils-install info

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

json: prep
	make -C libjson

stack: json objson transport 
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

transport-install:
	make -C libtransport install

libjson-install:
	make -C libjson install

utils-install:
	make -C utils install

objson-install:
	make -C objson install

stack-install:
	make -C libstack install

gateway-install:	
	make -C gateway install

router-install: 
	make -C router install

srfsh-install: 
	make -C srfsh install

jserver-install:
	make -C jserver install

perl-install:
	cp -r perlmods/* $(PERLDIR)/


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
	@echo "export LD_LIBRARY_PATH=\$$LD_LIBRARY_PATH:$(LIBDIR)"
	@echo "export PERL5LIB=\$$PERL5LIB:$(PERLDIR)"
	@echo "export PATH=\$$PATH:$(BINDIR)"
	@echo ""


# --------------------------------------------------------------------------------
# CLEAN	
# --------------------------------------------------------------------------------
clean:
	@echo "Cleaning..."
	make -C libtransport clean
	make -C libjson clean
	make -C libstack clean
	make -C router clean
	make -C gateway clean
	make -C jserver clean
	make -C utils clean
	make -C objson clean
	make -C libjson clean
	/bin/rm -rf $(TMPDIR)


