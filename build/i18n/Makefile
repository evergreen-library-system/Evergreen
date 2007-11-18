POOUTDIR=po
POINDIR=po
LOCALE=fr-CA
DTDDIR=../../Open-ILS/web/opac/locale
PROPSDIR=../../Open-ILS/xul/staff_client/chrome/locale
PROGRESS=--progress none

# This Makefile can be used to generate and update PO files for Evergreen,
# as well as generate updated DTD and JavaScript property files from the PO.
#
# Usage:
#
# To create a new set of untranslated PO files for locale ll-LL:
#   make LOCALE=ll-LL newpo
#
# To update a set of translated PO files with new or changed en-US strings:
#   make LOCALE=ll-LL updatepo

newpo: dtds2po props2po
	@echo "Generated new PO files for locale $(LOCALE)"

newproject: po2dtds po2props
	@echo "Generated newly translated project files for locale $(LOCALE)"

updatepo: update_po_dtds update_po_props
	@echo "Updated PO files for locale $(LOCALE)"

updatemoz: update_moz_dtds update_moz_props
	@echo "Updated translated project files for locale $(LOCALE)"

dtds2po:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(DTDDIR)/en-US/ 2>&1

props2po:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -i $(PROPSDIR)/en-US/ 2>&1

update_po_dtds:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -t $(DTDDIR)/en-US/ -i $(DTDDIR)/$(LOCALE)/ 2>&1

update_po_props:
	@moz2po $(PROGRESS) -o $(POOUTDIR)/$(LOCALE) -t $(PROPSDIR)/en-US/ -i $(PROPSDIR)/$(LOCALE)/ 2>&1

po2dtds:
	@po2moz $(PROGRESS) -o locale/$(LOCALE) -t $(DTDDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

po2props:
	@po2moz $(PROGRESS) -o locale/$(LOCALE) -t $(PROPSDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

update_moz_dtds:
	@po2moz $(PROGRESS) -o locale/$(LOCALE) -t $(DTDDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1

update_moz_props:
	@po2moz $(PROGRESS) -o locale/$(LOCALE) -t $(PROPSDIR)/en-US/ -i $(POINDIR)/$(LOCALE) 2>&1
