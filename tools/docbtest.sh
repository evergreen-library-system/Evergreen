#/bin/bash

#generate draft html
 # xsltproc --xinclude --stringparam base.dir /openils/var/web/evergreen_documentation/1.6/draft/html/ ~/Evergreen-DocBook/stylesheets/evergreen_docbook_files/evergreen_xhtml.xsl ~/Evergreen-DocBook/1.6/root.xml


#Generate PDF via FO
 xsltproc --xinclude  --output ~/temp.fo ~/Evergreen-DocBook/stylesheets/evergreen_docbook_files/evergreen_fo.xsl ~/Evergreen-DocBook/1.6/test.xml

# must run fop from same directory as file
cd ~/Evergreen-DocBook/1.6/

 ~/doctools/fop/fop -fo ~/temp.fo -pdf ~/testfile.pdf 

# remove temporary .fo file
rm pdf/temp.fo
