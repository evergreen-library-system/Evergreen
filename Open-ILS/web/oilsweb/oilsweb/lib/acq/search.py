import os, md5, time
import pylons.config
import osrf.ses, osrf.net_obj
import oils.const, oilsweb.lib.acq.picklist

EG_Z39_SOURCES = 'open-ils.search.z3950.retrieve_services'
EG_Z39_SEARCH = 'open-ils.search.z3950.search_class'
_z_sources = None

def fetch_z39_sources(ctx):
    global _z_sources
    if _z_sources:
        return _z_sources
    _z_sources = osrf.ses.ClientSession.atomic_request(
        oils.const.OILS_APP_SEARCH, EG_Z39_SOURCES, ctx.core.authtoken)
    return _z_sources

def multi_search(request_mgr, search):
    ses = osrf.ses.ClientSession(oils.const.OILS_APP_SEARCH)
    req = ses.request(EG_Z39_SEARCH, request_mgr.ctx.core.authtoken, search)

    pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(request_mgr)
    picklist_id = pl_manager.create_or_replace("__search_tmp__")

    while not req.complete:
        resp = req.recv()
        if not resp: 
            break

        res = resp.content()
        for record in res['records']:
            entry = osrf.net_obj.NetworkObject.acqple()
            entry.picklist(picklist_id)
            entry.source_label(res['service'])
            entry.marc(record['marcxml'])
            entry.eg_bib_id(record.get('bibid'))
            pl_manager.create_entry(entry)

    return picklist_id

def compile_multi_search(request_mgr):

    search = {
        'service' : [],
        'username' : [],
        'password' : [],
        'search' : {},
        'limit' : request_mgr.ctx.acq.limit,
        'offset' : request_mgr.ctx.acq.offset
    }

    # collect the sources and credentials
    for src in request_mgr.ctx.acq.search_source:
        search['service'].append(src)
        search['username'].append("") # XXX config values? in-db?
        search['password'].append("") # XXX config values? in-db?

    # collect the search classes
    for cls in request_mgr.ctx.acq.search_class:
        if request_mgr.request.params[cls]:
            search['search'][cls] = request_mgr.request.params[cls]

    return search

