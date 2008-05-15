import pylons.config, pylons.templating
import libxml2, libxslt

def childInit():
    ''' Global child-init handler.  

        1. Connects to the OpenSRF network.
        2. Parses the IDL file 
    '''

    import oils.system
    oils.system.System.remote_connect(
        config_file = pylons.config['osrf_config'],
        config_context = pylons.config['osrf_config_ctxt'],
        connect_cache = True)

_parsedSheets = {}
def apply_xsl(xmlStr, xslFile, xslParams={}):
    ''' Applies xslFile to xmlStr and returns the string result '''
    doc = libxml2.parseDoc(xmlStr)
    stylesheet = _parsedSheets.get(xslFile)

    if not stylesheet:
        styledoc = _parsedSheets.get(xslFile) or libxml2.parseFile(xslFile)
        stylesheet = libxslt.parseStylesheetDoc(styledoc)
        _parsedSheets[xslFile] = stylesheet

    result = stylesheet.applyStylesheet(doc, xslParams)
    return stylesheet.saveResultToString(result)


