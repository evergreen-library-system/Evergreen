POTSRC=po/en-US
POOUTDIR=po
POINDIR=po
PROJECT=locale
LOCALE=fr-CA
DTDDIR=../../Open-ILS/web/opac/locale
CHROME_PROPSDIR=../../Open-ILS/xul/staff_client/chrome/locale
SERVER_PROPSDIR=../../Open-ILS/xul/staff_client/server/locale
DOJO_LOCALE := $(shell echo ${LOCALE} | tr '[:upper:]-' '[:lower:]/')
DOJOSRC=../../Open-ILS/web/js/dojo/openils/conify/nls
FMIDLSRC=../../Open-ILS/examples/fm_IDL.xml
FMIDLOUT=fm_IDL.pot
FMIDLENT=fm_IDL.xml
FMIDLENTITY=fm_IDL.dtd
FMIDLPO=fm_IDL.po
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

# Generate PO files from all POT files in POOUTDIR for locale LOCALE
newpo: 
	@pot2po $(PROGRESS) -i $(POTSRC) -o $(POOUTDIR)/$(LOCALE) 
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
	pot2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(POTSRC) -t $(POOUTDIR)/$(LOCALE) 2>&1
	@echo "Updated PO files for locale $(LOCALE)"

# Update PO files with new and changed strings from POT files
updateopac: 
	@msgmerge -U $(POOUTDIR)/$(LOCALE)/opac.dtd.po $(POTSRC)/opac.dtd.pot 2>&1
	@echo "Updated PO file opac.dtd.po for locale $(LOCALE)"

dtds2po:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(DTDDIR)/en-US/ 2>&1

props2po:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(CHROME_PROPSDIR)/en-US/ 2>&1
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(SERVER_PROPSDIR)/en-US/ 2>&1

dtds2pot:
	@moz2po -P $(PROGRESS) -o $(POTSRC) -i $(DTDDIR)/en-US/ 2>&1

dojo2pot:
	@scripts/dojo_resource.py --pot $(DOJOSRC)/aou.js --output $(POTSRC)/conify.aou.pot
	@scripts/dojo_resource.py --pot $(DOJOSRC)/aout.js --output $(POTSRC)/conify.aout.pot
	@scripts/dojo_resource.py --pot $(DOJOSRC)/cam.js --output $(POTSRC)/conify.cam.pot
	@scripts/dojo_resource.py --pot $(DOJOSRC)/ccs.js --output $(POTSRC)/conify.ccs.pot
	@scripts/dojo_resource.py --pot $(DOJOSRC)/pgt.js --output $(POTSRC)/conify.pgt.pot
	@scripts/dojo_resource.py --pot $(DOJOSRC)/ppl.js --output $(POTSRC)/conify.ppl.pot

po2dojo:
	@scripts/dojo_resource.py --create $(POINDIR)/$(LOCALE)/conify.aou.po --output $(PROJECT)/$(LOCALE)/conify.aou.js
	@scripts/dojo_resource.py --create $(POINDIR)/$(LOCALE)/conify.aout.po --output $(PROJECT)/$(LOCALE)/conify.aout.js
	@scripts/dojo_resource.py --create $(POINDIR)/$(LOCALE)/conify.cam.po --output $(PROJECT)/$(LOCALE)/conify.cam.js
	@scripts/dojo_resource.py --create $(POINDIR)/$(LOCALE)/conify.ccs.po --output $(PROJECT)/$(LOCALE)/conify.ccs.js
	@scripts/dojo_resource.py --create $(POINDIR)/$(LOCALE)/conify.pgt.po --output $(PROJECT)/$(LOCALE)/conify.pgt.js
	@scripts/dojo_resource.py --create $(POINDIR)/$(LOCALE)/conify.ppl.po --output $(PROJECT)/$(LOCALE)/conify.ppl.js

ils2pot:
	@scripts/ils_events.py --pot $(EVTSRC) --output $(POTSRC)/$(EVTOUT)

po2ils:
	@scripts/ils_events.py --create $(POINDIR)/$(LOCALE)/$(EVTPO) --locale $(LOCALE) --output $(PROJECT)/$(LOCALE)/$(EVTXML) 

props2pot:
	@moz2po -P $(PROGRESS) -o $(POTSRC) -i $(CHROME_PROPSDIR)/en-US/ 2>&1
	@moz2po -P $(PROGRESS) -o $(POTSRC) -i $(SERVER_PROPSDIR)/en-US/ 2>&1

po2dtds:
	@po2moz $(PROGRESS) -o $(PROJECT)/$(LOCALE) -t $(DTDDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

po2props:
	@po2moz $(PROGRESS) -o $(PROJECT)/$(LOCALE) -t $(CHROME_PROPSDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1
	@po2moz $(PROGRESS) -o $(PROJECT)/$(LOCALE) -t $(SERVER_PROPSDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

sql2pot:
	@scripts/db-seed-i18n.py --pot $(SQLSRCDIR)/$(SQLSRCFILE) --output $(POTSRC)/$(SQLPOT)

po2sql:
	scripts/db-seed-i18n.py --sql $(POINDIR)/$(LOCALE)/$(SQLPO) --locale $(LOCALE) --output $(PROJECT)/$(LOCALE)/$(SQLOUT).sql

# Generate a fieldmapper IDL file that uses entities instead of hard-coded strings
fmidl2fmidlent:
	@scripts/fieldmapper.py --convert $(FMIDLSRC) --output $(POOUTDIR)/$(FMIDLENT)

# Generate a POT file for translating the entity values
fmidl2pot:
	@scripts/fieldmapper.py --pot $(FMIDLSRC) --output $(POTSRC)/$(FMIDLOUT)

# Generate a set of entity declarations from a PO file
fmidlpo2entity:
	@scripts/fieldmapper.py --entity $(POINDIR)/$(LOCALE)/$(FMIDLPO) --output $(PROJECT)/$(LOCALE)/$(FMIDLENTITY)

# Generate en-US DTD from a POT file; required if any other locale is installed
fmidlpo2entity-en:
	mkdir -p $(PROJECT)/en-US
	@scripts/fieldmapper.py --entity $(POINDIR)/en-US/$(FMIDLOUT) --output $(PROJECT)/en-US/$(FMIDLENTITY)
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
	cp $(PROJECT)/$(LOCALE)/vandelay.dtd $(DTDDIR)/$(LOCALE)/
	cp $(PROJECT)/$(LOCALE)/$(FMIDLENTITY) $(DTDDIR)/$(LOCALE)/
	@scripts/merge_ils_events.py --master $(EVTSRC) --localization $(PROJECT)/$(LOCALE)/$(EVTXML) --output $(EVTSRC)
	cp $(PROJECT)/$(LOCALE)/$(SQLOUT).sql $(SQLSRCDIR)/$(SQLOUT)-$(LOCALE).sql
	cp $(POOUTDIR)/$(FMIDLENT) $(REPORTDIR)/$(FMIDLENT)
	mkdir -p $(DOJOSRC)/$(DOJO_LOCALE)
	cp $(PROJECT)/$(LOCALE)/conify.aou.js $(DOJOSRC)/$(DOJO_LOCALE)/aou.js
	cp $(PROJECT)/$(LOCALE)/conify.aout.js $(DOJOSRC)/$(DOJO_LOCALE)/aout.js
	cp $(PROJECT)/$(LOCALE)/conify.cam.js $(DOJOSRC)/$(DOJO_LOCALE)/cam.js
	cp $(PROJECT)/$(LOCALE)/conify.ccs.js $(DOJOSRC)/$(DOJO_LOCALE)/ccs.js
	cp $(PROJECT)/$(LOCALE)/conify.pgt.js $(DOJOSRC)/$(DOJO_LOCALE)/pgt.js
	cp $(PROJECT)/$(LOCALE)/conify.ppl.js $(DOJOSRC)/$(DOJO_LOCALE)/ppl.js
