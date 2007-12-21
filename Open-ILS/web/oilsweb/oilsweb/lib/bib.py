import os, re
import pylons
import osrf.ses
import oils.utils.csedit
import oilsweb.lib.util

def marc_to_html(marcxml):
    # create a path building utility function ....
    xslFile = os.path.join(os.getcwd(), pylons.config['oils_xsl_prefix'], pylons.config['oils_xsl_marc2html'])
    html = oilsweb.lib.util.apply_xsl(marcxml, xslFile)
    # XXX encoding problems need resolving...
    return html

def scrub_isbn(isbn):
    ''' removes trailing data from an ISBN '''
    if not isbn: return isbn
    return re.sub('\s.*','', isbn)

    
