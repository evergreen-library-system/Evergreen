import os, md5
import oilsweb.lib.context
import osrf.ses
import osrf.xml_obj
import oils.const
import osrf.log, osrf.cache, osrf.json
import pylons.config

EG_Z39_SOURCES = 'open-ils.search.z3950.retrieve_services'
EG_Z39_SEARCH = 'open-ils.search.z3950.search_class'
_z_sources = None

def fetch_z39_sources(ctx):
    global _z_sources
    if _z_sources:
        return _z_sources
    _z_sources = osrf.ses.AtomicRequest(
        'open-ils.search', EG_Z39_SOURCES, ctx.core.authtoken)
    return _z_sources

def flatten_record(marcxml):
    import pylons
    xslFile = os.path.join(os.getcwd(), pylons.config['oils_xsl_prefix'], pylons.config['oils_xsl_acq_bib'])
    xformed = oilsweb.lib.util.apply_xsl(marcxml, xslFile)
    return osrf.xml_obj.XMLFlattener(xformed, True).parse()

def multi_search(ctx, search):
    ses = osrf.ses.ClientSession(oils.const.OILS_APP_SEARCH)
    req = ses.request(EG_Z39_SEARCH, ctx.core.authtoken, search)

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

    return results, cache_search(search, results)

def cache_search(search, results):
    key = md5.new()
    key.update(unicode(search))
    key = key.hexdigest()
    osrf.cache.CacheClient().put(key, results, pylons.config.get('oils_bib_cache_time', 900))
    return key

def extract_bib_field(rec, field, all=False):
    f = rec['extracts'].get("bibdata." + field)
    if not f: return ""
    obj = osrf.json.to_object(f)
    if isinstance(obj, list):
        if all:
            return obj
        else:
            return obj[0]
    else:
        return obj

