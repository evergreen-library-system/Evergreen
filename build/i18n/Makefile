POOUTDIR=po
POINDIR=po
PROJECT=locale
LOCALE=fr-CA
DTDDIR=../../Open-ILS/web/opac/locale
PROPSDIR=../../Open-ILS/xul/staff_client/chrome/locale
FMIDLSRC=../../Open-ILS/examples/fm_IDL.xml
FMIDLOUT=fm_IDL.pot
FMIDLENT=fm_IDL.xml
FMIDLENTITY=fm_IDL.xml.ent
FMIDLPO=fm_IDL.po
SQLSRC=../../Open-ILS/src/sql/Pg/950.data.seed-values.sql
SQLOUT=db.seed.pot
SQLPO=db.seed.po
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
# To create a new set of project files (DTDs, JavaScript message catalogs):
#   make LOCALE=ll-LL updatepo

# Generate PO files from all POT files in POOUTDIR for locale LOCALE
newpo: 
	@pot2po $(PROGRESS) -i $(POOUTDIR) -o $(POOUTDIR)/$(LOCALE) 
	@echo "Generated new PO files for locale $(LOCALE)"

# Generate a new set of POT files and entityized fieldmapper IDL
newpot: dtds2pot fmidl2pot fmidl2fmidlent props2pot sql2pot
	@echo "Generated new POT files"

# Generate DTD, JavaScript message catalogs, fieldmapper IDL,
# and SQL insert files from PO for locale LOCALE
newproject: po2dtds po2props po2sql fmidlpo2entity
	@echo "Generated project files for locale $(LOCALE)"

# Update PO files with new and changed strings from POT files
updatepo: 
	@pot2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(POOUTDIR) -t $(POOUTDIR)/$(LOCALE) 2>&1
	@echo "Updated PO files for locale $(LOCALE)"

dtds2po:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(DTDDIR)/en-US/ 2>&1

props2po:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(PROPSDIR)/en-US/ 2>&1

dtds2pot:
	@moz2po -P $(PROGRESS) -o $(POOUTDIR) -i $(DTDDIR)/en-US/ 2>&1

props2pot:
	@moz2po -P $(PROGRESS) -o $(POOUTDIR) -i $(PROPSDIR)/en-US/ 2>&1

po2dtds:
	@po2moz $(PROGRESS) -o $(PROJECT)/$(LOCALE) -t $(DTDDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

po2props:
	@po2moz $(PROGRESS) -o $(PROJECT)/$(LOCALE) -t $(PROPSDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

sql2pot:
	@scripts/db-seed-i18n.py --pot $(SQLSRC) --output $(POOUTDIR)/$(SQLOUT)

po2sql:
	scripts/db-seed-i18n.py --sql $(POINDIR)/$(LOCALE)/$(SQLPO) --locale $(LOCALE) --output $(PROJECT)/$(LOCALE)/$(SQLOUT)

# Generate a fieldmapper IDL file that uses entities instead of hard-coded strings
fmidl2fmidlent:
	@scripts/fieldmapper.py --convert $(FMIDLSRC) --output $(POOUTDIR)/$(FMIDLENT)

# Generate a POT file for translating the entity values
fmidl2pot:
	@scripts/fieldmapper.py --pot $(FMIDLSRC) --output $(POOUTDIR)/$(FMIDLOUT)

# Generate a set of entity declarations from a PO file
fmidlpo2entity:
	@scripts/fieldmapper.py --entity $(POINDIR)/$(FMIDLOUT) --output $(PROJECT)/$(LOCALE)/$(FMIDLENTITY)
