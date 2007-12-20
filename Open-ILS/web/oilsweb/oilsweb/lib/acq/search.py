import os, md5
import oilsweb.lib.context
import osrf.ses
import osrf.xml_obj
import oils.const
import osrf.log, osrf.cache

EG_Z39_SEARCH = 'open-ils.search.z3950.search_class'
_z_sources = None

def fetch_z39_sources(ctx):
    global _z_sources
    if _z_sources:
        return _z_sources
    _z_sources = osrf.ses.AtomicRequest(
        'open-ils.search',
        'open-ils.search.z3950.retrieve_services', ctx.core.authtoken)
    return _z_sources

def flatten_record(marcxml):
    import pylons
    xslFile = os.path.join(os.getcwd(), pylons.config['oils_xsl_prefix'], pylons.config['oils_xsl_acq_bib'])
    xformed = oilsweb.lib.util.apply_xsl(marcxml, xslFile)
    return osrf.xml_obj.XMLFlattener(xformed).parse()

def multi_search(ctx, search):
    ses = osrf.ses.ClientSession(oils.const.OILS_APP_SEARCH)
    req = ses.request(EG_Z39_SEARCH, ctx.core.authtoken, search)
    osrf.log.log_debug("sending " + unicode(search))

    cache_id = 0
    results = []
    while not req.complete:
        resp = req.recv(60)
        if not resp: 
            break
        res = resp.content()
        for rec in res['records']:
            rec['extracts'] = flatten_record(rec['marcxml'])
            rec['cache_id'] = cache_id
            cache_id += 1

        results.append(res)

    osrf.log.log_debug("got " + unicode(results))
    return results, cache_search(search, results)

def cache_search(search, results):
    key = md5.new()
    key.update(unicode(search))
    key = key.hexdigest()
    osrf.cache.CacheClient().put(key, results)
    return key

