POOUTDIR=po
POINDIR=po
LOCALE=fr-CA
DTDDIR=../../Open-ILS/web/opac/locale
PROPSDIR=../../Open-ILS/xul/staff_client/chrome/locale
FMIDLSRC=../../Open-ILS/examples/fm_IDL.xml
FMIDLOUT=fm_IDL.pot
SQLSRC=../../Open-ILS/src/sql/Pg/950.data.seed-values.sql
SQLOUT=db.seed.pot
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

newpo: dtds2po props2po
	@echo "Generated new PO files for locale $(LOCALE)"

newpot: dtds2pot fmidl2pot props2pot sql2pot
	@echo "Generated new POT files"

newproject: po2dtds po2props
	@echo "Generated newly translated project files for locale $(LOCALE)"

updatepo: 
	@pot2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(POOUTDIR) -t $(POOUTDIR)/$(LOCALE) 2>&1
	@echo "Updated PO files for locale $(LOCALE)"

updateproject: update_moz_dtds update_moz_props
	@echo "Updated translated project files for locale $(LOCALE)"

dtds2po:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(DTDDIR)/en-US/ 2>&1

props2po:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(PROPSDIR)/en-US/ 2>&1

dtds2pot:
	@moz2po -P $(PROGRESS) -o $(POOUTDIR) -i $(DTDDIR)/en-US/ 2>&1

props2pot:
	@moz2po -P $(PROGRESS) -o $(POOUTDIR) -i $(PROPSDIR)/en-US/ 2>&1

po2dtds:
	@po2moz $(PROGRESS) -o locale/$(LOCALE) -t $(DTDDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

po2props:
	@po2moz $(PROGRESS) -o locale/$(LOCALE) -t $(PROPSDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

sql2pot:
	@scripts/db-seed-i18n.py --pot $(SQLSRC) --output $(POOUTDIR)/$(SQLOUT)

fmidl2pot:
	@scripts/fieldmapper.py --pot $(FMIDLSRC) --output $(POOUTDIR)/$(FMIDLOUT)

update_moz_dtds:
	@po2moz $(PROGRESS) -o locale/$(LOCALE) -t $(DTDDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

update_moz_props:
	@po2moz $(PROGRESS) -o locale/$(LOCALE) -t $(PROPSDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1
