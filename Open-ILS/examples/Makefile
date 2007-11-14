# vim:noet:ts=4
#
# This is a simple implementation of a test suite for XML validity
# (where possible) or well-formedness (if no schema is available)
# to ensure that our sample XML configuration files are reasonably
# clean.

TESTIDL := $(shell xmllint --noout --schema fm_IDL.xsd fm_IDL.xml 2>&1 | wc -l)
TESTOSRF := $(shell xmllint --noout opensrf.xml 2>&1 | wc -l)
TESTOSRFCORE := $(shell xmllint --noout opensrf_core.xml 2>&1 | wc -l)

test_idl:
TOTAL := $(TOTAL).
ifeq ($(TESTIDL), 1)
SUCCESS := $(SUCCESS).
else
$(warning fm_IDL.xml does not validate)
endif

test_osrf:
TOTAL := $(TOTAL).
ifeq ($(TESTOSRF), 1)
SUCCESS := $(SUCCESS).
else
$(warning opensrf.xml is not well-formed)
endif

test_osrf_core:
TOTAL := $(TOTAL).
ifeq ($(TESTOSRFCORE), 1)
SUCCESS := $(SUCCESS).
else
$(warning opensrf_core.xml is not well-formed)
endif

test: test_idl test_osrf test_osrf_core
# First we count the number of characters returned
SUCCESSES ?= $(shell echo $(SUCCESS) | wc -m )
FAILED ?= $(shell echo $(FAILURE) | wc -m )
TOTALED ?= $(shell echo $(TOTAL) | wc -m )
# Then we subtract one from the count to make it accurate
SUCCESSTESTS ?= $(shell echo $(SUCCESSES) - 1 | bc )
FAILEDTESTS ?= $(shell echo $(FAILED) -1 | bc )
TOTALTESTS ?= $(shell echo $(TOTALED) -1 | bc )
$(info Succesful tests: $(SUCCESSTESTS)/$(TOTALTESTS))
$(info Failed tests: $(FAILEDTESTS)/$(TOTALTESTS))


