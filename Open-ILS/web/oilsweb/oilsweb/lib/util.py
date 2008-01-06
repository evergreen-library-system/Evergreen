import pylons.config, pylons.templating
import libxml2, libxslt
#import oils.utils.utils

def childInit():
    ''' Global child-init handler.  

        1. Connects to the OpenSRF network.
        2. Parses the IDL file 
    '''

    import oils.system, osrf.system
    oils.system.oilsConnect(pylons.config['osrf_config'], pylons.config['osrf_config_ctxt'])
    osrf.system.connect_cache()

_parsedSheets = {}
def apply_xsl(xmlStr, xslFile, xslParams={}):
    doc = libxml2.parseDoc(xmlStr)
    stylesheet = _parsedSheets.get(xslFile)

    if not stylesheet:
        styledoc = _parsedSheets.get(xslFile) or libxml2.parseFile(xslFile)
        stylesheet = libxslt.parseStylesheetDoc(styledoc)
        _parsedSheets[xslFile] = stylesheet

    result = stylesheet.applyStylesheet(doc, xslParams)
    return stylesheet.saveResultToString(result)


