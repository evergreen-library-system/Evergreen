import pylons.config, pylons.templating
import libxml2, libxslt
import oils.utils.utils

def childInit():
    ''' Global child-init handler.  

        1. Connects to the OpenSRF network.  Note that the OpenSRF 
        layer ensures that there is only one connection per thread.
        2. Parses the IDL file '''
    import osrf.system, osrf.set, oils.utils.idl, oils.utils.csedit, osrf.cache
    osrf.system.connect(pylons.config['osrf_config'], pylons.config['osrf_config_ctxt'])
    oils.utils.idl.oilsParseIDL()
    oils.utils.csedit.oilsLoadCSEditor()

    # live in opensrf somewhere
    servers = osrf.set.get('cache.global.servers.server')
    if not isinstance(servers, list):
        servers = [servers]
    if not osrf.cache.CacheClient.get_client():
        osrf.cache.CacheClient.connect(servers)



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


