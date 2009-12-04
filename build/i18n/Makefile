PO=po
PROJECT=locale
LOCALE=fr-CA
POTLIST=$(shell ls -d po/*)
DTDDIR=../../Open-ILS/web/opac/locale
CHROME_PROPSDIR=../../Open-ILS/xul/staff_client/chrome/locale
SERVER_PROPSDIR=../../Open-ILS/xul/staff_client/server/locale
DOJO_LOCALE := $(shell echo ${LOCALE} | tr '[:upper:]-' '[:lower:]/')
DOJO_CON_SRC=../../Open-ILS/web/js/dojo/openils/conify/nls
DOJO_OPAC_SRC=../../Open-ILS/web/js/dojo/openils/opac/nls
DOJO_RPT_SRC=../../Open-ILS/web/js/dojo/openils/reports/nls
FMIDLSRC=../../Open-ILS/examples/fm_IDL.xml
FMIDLOUT=fm_IDL.dtd.pot
FMIDLENT=fm_IDL.xml
FMIDLENTITY=fm_IDL.dtd
EVTSRC=../../Open-ILS/src/extras/ils_events.xml
EVTOUT=ils_events.xml.pot
EVTPO=ils_events.xml.po
EVTXML=ils_events.xml
REPORTDIR=../../Open-ILS/web/reports/
SQLSRCDIR=../../Open-ILS/src/sql/Pg/
SQLSRCFILE=950.data.seed-values.sql
SQLPOT=db.seed.pot
SQLPO=db.seed.po
SQLOUT=950.data.seed-values
PROGRESS=--progress none

# This Makefile can be used to generate and update PO files for Evergreen,
# as well as generate updated SQL, fieldmapper IDL, DTD and JavaScript
# property files from the PO.
#
# Usage:
#
# To create a new set of untranslated PO files for locale ll-LL:
#   make LOCALE=ll-LL newpo
#
# To create a new set of POT files from the en-US source:
#   make LOCALE=ll-LL newpot
#
# To update a set of translated PO files with new or changed en-US strings:
#   make LOCALE=ll-LL updatepo
#
# To create a set of translated project files (DTDs, JavaScript message catalogs):
#   make LOCALE=ll-LL project
#
# To install a set of translated project files:
#   make LOCALE=ll-LL install

# Generate PO files from all POT files in PO for locale LOCALE
#
# The template for the standard GNU gettext format is
# template1/template1.pot
# template1/ll-LL.po
# template2/template2.pot
# template2/ll-LL.po

# So, iterate over the list of POT directories and 
# generate / update the specified locale PO file
newpo: 
	@pot2po $(PROGRESS) -i po/admin.properties/admin.properties.pot -o $(PO)/admin.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/auth.properties/auth.properties.pot -o $(PO)/auth.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/cat.properties/cat.properties.pot -o $(PO)/cat.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/circ.properties/circ.properties.pot -o $(PO)/circ.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/common.properties/common.properties.pot -o $(PO)/common.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/conify.dtd/conify.dtd.pot -o $(PO)/conify.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/conify.js/conify.js.pot -o $(PO)/conify.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/db.seed/db.seed.pot -o $(PO)/db.seed/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/fm_IDL.dtd/fm_IDL.dtd.pot -o $(PO)/fm_IDL.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/ils_events.xml/ils_events.xml.pot -o $(PO)/ils_events.xml/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/lang.dtd/lang.dtd.pot -o $(PO)/lang.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/multiclass_search_help.html/multiclass_search_help.html.pot -o $(PO)/multiclass_search_help.html/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/offline.properties/offline.properties.pot -o $(PO)/offline.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/opac.dtd/opac.dtd.pot -o $(PO)/opac.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/opac.js/opac.js.pot -o $(PO)/opac.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/patron.properties/patron.properties.pot -o $(PO)/patron.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reports.dtd/reports.dtd.pot -o $(PO)/reports.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reports.js/reports.js.pot -o $(PO)/reports.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/vandelay.dtd/vandelay.dtd.pot -o $(PO)/vandelay.dtd/$(LOCALE).po 
	@echo "Generated new PO files for locale $(LOCALE)"

# Generate a new set of POT files and entityized fieldmapper IDL
newpot: dtds2pot fmidl2pot fmidl2fmidlent ils2pot props2pot sql2pot dojo2pot
	@echo "Generated new POT files"

# Generate DTD, JavaScript message catalogs, fieldmapper IDL,
# and SQL insert files from PO for locale LOCALE
project: po2dtds po2props po2sql fmidlpo2entity po2ils po2dojo
	@echo "Generated project files for locale $(LOCALE)"

# Update PO files with new and changed strings from POT files
updatepo: 
	@pot2po $(PROGRESS) -i po/admin.properties/admin.properties.pot -o $(PO)/admin.properties/$(LOCALE).po  -t $(PO)/admin.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/auth.properties/auth.properties.pot -o $(PO)/auth.properties/$(LOCALE).po  -t $(PO)/auth.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/cat.properties/cat.properties.pot -o $(PO)/cat.properties/$(LOCALE).po  -t $(PO)/cat.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/circ.properties/circ.properties.pot -o $(PO)/circ.properties/$(LOCALE).po  -t $(PO)/circ.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/common.properties/common.properties.pot -o $(PO)/common.properties/$(LOCALE).po  -t $(PO)/common.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/conify.dtd/conify.dtd.pot -o $(PO)/conify.dtd/$(LOCALE).po  -t $(PO)/conify.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/conify.js/conify.js.pot -o $(PO)/conify.js/$(LOCALE).po  -t $(PO)/conify.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/db.seed/db.seed.pot -o $(PO)/db.seed/$(LOCALE).po  -t $(PO)/db.seed/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/fm_IDL/fm_IDL.pot -o $(PO)/fm_IDL/$(LOCALE).po  -t $(PO)/fm_IDL/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/fm_IDL.dtd/fm_IDL.dtd.pot -o $(PO)/fm_IDL.dtd/$(LOCALE).po  -t $(PO)/fm_IDL.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/ils_events.xml/ils_events.xml.pot -o $(PO)/ils_events.xml/$(LOCALE).po  -t $(PO)/ils_events.xml/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/lang.dtd/lang.dtd.pot -o $(PO)/lang.dtd/$(LOCALE).po  -t $(PO)/lang.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/multiclass_search_help.html/multiclass_search_help.html.pot -o $(PO)/multiclass_search_help.html/$(LOCALE).po  -t $(PO)/multiclass_search_help.html/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/offline.properties/offline.properties.pot -o $(PO)/offline.properties/$(LOCALE).po  -t $(PO)/offline.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/opac.dtd/opac.dtd.pot -o $(PO)/opac.dtd/$(LOCALE).po  -t $(PO)/opac.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/opac.js/opac.js.pot -o $(PO)/opac.js/$(LOCALE).po  -t $(PO)/opac.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/patron.properties/patron.properties.pot -o $(PO)/patron.properties/$(LOCALE).po  -t $(PO)/patron.properties/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reports.dtd/reports.dtd.pot -o $(PO)/reports.dtd/$(LOCALE).po  -t $(PO)/reports.dtd/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/reports.js/reports.js.pot -o $(PO)/reports.js/$(LOCALE).po  -t $(PO)/reports.js/$(LOCALE).po 
	@pot2po $(PROGRESS) -i po/vandelay.dtd/vandelay.dtd.pot -o $(PO)/vandelay.dtd/$(LOCALE).po  -t $(PO)/vandelay.dtd/$(LOCALE).po 
	@echo "Updated PO files for locale $(LOCALE)"

dtds2pot:
	@moz2po -P $(PROGRESS) -o $(PO)/conify.dtd/conify.dtd.pot -i $(DTDDIR)/en-US/conify.dtd 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/lang.dtd/lang.dtd.pot -i $(DTDDIR)/en-US/lang.dtd 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/opac.dtd/opac.dtd.pot -i $(DTDDIR)/en-US/opac.dtd 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/reports.dtd/reports.dtd.pot -i $(DTDDIR)/en-US/reports.dtd 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/vandelay.dtd/vandelay.dtd.pot -i $(DTDDIR)/en-US/vandelay.dtd 2>&1

dojo2pot:
	@scripts/dojo_resource.py --pot $(DOJO_CON_SRC)/conify.js --output $(PO)/conify.js/conify.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_OPAC_SRC)/opac.js --output $(PO)/opac.js/opac.js.pot
	@scripts/dojo_resource.py --pot $(DOJO_RPT_SRC)/reports.js --output $(PO)/reports.js/reports.js.pot

po2dojo:
	@mkdir -p locale/$(LOCALE)
	@scripts/dojo_resource.py --create $(PO)/conify.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/conify.js
	@scripts/dojo_resource.py --create $(PO)/opac.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/opac.js
	@scripts/dojo_resource.py --create $(PO)/reports.js/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/reports.js

ils2pot:
	@scripts/ils_events.py --pot $(EVTSRC) --output $(PO)/ils_events.xml/$(EVTOUT)

po2ils:
	@mkdir -p locale/$(LOCALE)
	@scripts/ils_events.py --create $(PO)/ils_events.xml/$(LOCALE).po --locale $(LOCALE) --output $(PROJECT)/$(LOCALE)/$(EVTXML) 

props2pot:
	@mkdir -p locale/$(LOCALE)
	@moz2po -P $(PROGRESS) -o $(PO)/auth.properties/auth.properties.pot -i $(CHROME_PROPSDIR)/en-US/auth.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/offline.properties/offline.properties.pot -i $(CHROME_PROPSDIR)/en-US/offline.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/admin.properties/admin.properties.pot -i $(SERVER_PROPSDIR)/en-US/admin.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/cat.properties/cat.properties.pot -i $(SERVER_PROPSDIR)/en-US/cat.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/circ.properties/circ.properties.pot -i $(SERVER_PROPSDIR)/en-US/circ.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/common.properties/common.properties.pot -i $(SERVER_PROPSDIR)/en-US/common.properties 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/multiclass_search_help.html/multiclass_search_help.html.pot -i $(SERVER_PROPSDIR)/en-US/multiclass_search_help.html 2>&1
	@moz2po -P $(PROGRESS) -o $(PO)/patron.properties/patron.properties.pot -i $(SERVER_PROPSDIR)/en-US/patron.properties 2>&1

po2dtds:
	@mkdir -p locale/$(LOCALE)
	@po2moz $(PROGRESS) -i $(PO)/conify.dtd/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/conify.dtd -t $(DTDDIR)/en-US/conify.dtd 2>&1
	@po2moz $(PROGRESS) -i $(PO)/lang.dtd/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/lang.dtd -t $(DTDDIR)/en-US/lang.dtd 2>&1
	@po2moz $(PROGRESS) -i $(PO)/opac.dtd/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/opac.dtd -t $(DTDDIR)/en-US/opac.dtd 2>&1
	@po2moz $(PROGRESS) -i $(PO)/reports.dtd/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/reports.dtd -t $(DTDDIR)/en-US/reports.dtd 2>&1
	@po2moz $(PROGRESS) -i $(PO)/vandelay.dtd/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/vandelay.dtd -t $(DTDDIR)/en-US/vandelay.dtd 2>&1

po2props:
	@po2moz $(PROGRESS) -i $(PO)/auth.properties/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/auth.properties -t $(CHROME_PROPSDIR)/en-US/auth.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/offline.properties/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/offline.properties -t $(CHROME_PROPSDIR)/en-US/offline.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/admin.properties/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/admin.properties -t $(SERVER_PROPSDIR)/en-US/admin.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/cat.properties/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/cat.properties -t $(SERVER_PROPSDIR)/en-US/cat.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/circ.properties/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/circ.properties -t $(SERVER_PROPSDIR)/en-US/circ.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/common.properties/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/common.properties -t $(SERVER_PROPSDIR)/en-US/common.properties 2>&1
	@po2moz $(PROGRESS) -i $(PO)/multiclass_search_help.html/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/multiclass_search_help.html -t $(SERVER_PROPSDIR)/en-US/multiclass_search_help.html 2>&1
	@po2moz $(PROGRESS) -i $(PO)/patron.properties/$(LOCALE).po -o $(PROJECT)/$(LOCALE)/patron.properties -t $(SERVER_PROPSDIR)/en-US/patron.properties 2>&1

sql2pot:
	@scripts/db-seed-i18n.py --pot $(SQLSRCDIR)/$(SQLSRCFILE) --output $(PO)/db.seed/$(SQLPOT)
#	@msghack --empty -o $(PO)/$(SQLPOT) $(PO)/$(SQLPOT)

po2sql:
	@mkdir -p locale/$(LOCALE)
	@scripts/db-seed-i18n.py --sql $(PO)/db.seed/$(LOCALE).po --locale $(LOCALE) --output $(PROJECT)/$(LOCALE)/$(SQLOUT).sql

# Generate a fieldmapper IDL file that uses entities instead of hard-coded strings
fmidl2fmidlent:
	@scripts/fieldmapper.py --convert $(FMIDLSRC) --output $(PO)/$(FMIDLENT)

# Generate a POT file for translating the entity values
fmidl2pot:
	@scripts/fieldmapper.py --pot $(FMIDLSRC) --output $(PO)/fm_IDL.dtd/$(FMIDLOUT)

# Generate a set of entity declarations from a PO file
fmidlpo2entity:
	@mkdir -p locale/$(LOCALE)
	@scripts/fieldmapper.py --entity $(PO)/fm_IDL.dtd/$(LOCALE).po --output $(PROJECT)/$(LOCALE)/$(FMIDLENTITY)

# Generate en-US DTD from a POT file; required if any other locale is installed
fmidlpo2entity-en:
	mkdir -p $(PROJECT)/en-US
	@scripts/fieldmapper.py --entity $(PO)/fm_IDL.dtd/$(FMIDLOUT) --output $(PROJECT)/en-US/$(FMIDLENTITY)
	cp $(PROJECT)/en-US/$(FMIDLENTITY) $(DTDDIR)/en-US/

# Install updated project files to their corresponding location in the source tree
install: updatepo project fmidl2fmidlent fmidlpo2entity-en
	mkdir -p $(CHROME_PROPSDIR)/$(LOCALE)
	cp $(PROJECT)/$(LOCALE)/auth.properties $(CHROME_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/offline.properties $(CHROME_PROPSDIR)/$(LOCALE)/.
	mkdir -p $(SERVER_PROPSDIR)/$(LOCALE)
	cp $(PROJECT)/$(LOCALE)/admin.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/cat.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/circ.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/common.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/multiclass_search_help.html $(SERVER_PROPSDIR)/$(LOCALE)/.
	cp $(PROJECT)/$(LOCALE)/patron.properties $(SERVER_PROPSDIR)/$(LOCALE)/.
	mkdir -p $(DTDDIR)/$(LOCALE)
	cp $(PROJECT)/$(LOCALE)/conify.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/lang.dtd $(CHROME_PROPSDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/lang.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/opac.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/reports.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/vandelay.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/$(FMIDLENTITY) $(DTDDIR)/$(LOCALE)/
	@scripts/merge_ils_events.py --master $(EVTSRC) --localization $(PROJECT)/$(LOCALE)/$(EVTXML) --output $(EVTSRC)
	cp $(PROJECT)/$(LOCALE)/$(SQLOUT).sql $(SQLSRCDIR)/$(SQLOUT)-$(LOCALE).sql
	cp $(PO)/$(FMIDLENT) $(REPORTDIR)/$(FMIDLENT)
	mkdir -p $(DOJO_CON_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/conify.js $(DOJO_CON_SRC)/$(DOJO_LOCALE)/conify.js
	mkdir -p $(DOJO_OPAC_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/opac.js $(DOJO_OPAC_SRC)/$(DOJO_LOCALE)/opac.js
	mkdir -p $(DOJO_RPT_SRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/reports.js $(DOJO_RPT_SRC)/$(DOJO_LOCALE)/reports.js
