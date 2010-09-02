#!/bin/bash

#generate draft html
xsltproc --xinclude  --stringparam base.dir /home/jbuhler/www/Sitka/draft/html/ /home/jbuhler/stylesheets/sitka_xhtml.xsl /home/jbuhler/www/Sitka/draft/root.xml

# generate temp.fo for draft pdf
xsltproc --xinclude  --output /home/jbuhler/www/Sitka/draft/pdf/temp.fo /home/jbuhler/stylesheets/sitka_fo.xsl /home/jbuhler/www/Sitka/draft/root.xml

# must run fop from same directory as root.xml
cd /home/jbuhler/www/Sitka/draft/

# create draft pdf for review
fop pdf/temp.fo pdf/Sitka_Training_Manual.pdf

# remove temporary .fo file
rm pdf/temp.fo
