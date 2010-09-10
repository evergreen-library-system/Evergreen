#/bin/bash

#generate draft html
 xsltproc --xinclude --stringparam base.dir /openils/var/web/evergreen_documentation/draft/html/ /home/rsoulliere/doctools/EvergreenDocumentation/evergreen_docbook_files/evergreen_xhtml.xsl /home/rsoulliere/doctools/EvergreenDocumentation/root.xml


#Generate PDF via FO
xsltproc --xinclude  --output /home/rsoulliere/doctools/EvergreenDocumentation/pdf/temp.fo /home/rsoulliere/doctools/EvergreenDocumentation/evergreen_docbook_files/evergreen_fo.xsl /home/rsoulliere/doctools/EvergreenDocumentation/root.xml

# must run fop from same directory as root.xml
cd /home/rsoulliere/doctools/EvergreenDocumentation/

 ~/doctools/fop/fop -fo pdf/temp.fo -pdf /openils/var/web/evergreen_documentation/draft/pdf/Evergreen_Documentation.pdf 

# remove temporary .fo file
rm pdf/temp.fo
