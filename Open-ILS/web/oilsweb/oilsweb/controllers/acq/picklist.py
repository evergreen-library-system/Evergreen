from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr
import logging, pylons
import oilsweb.lib.context, oilsweb.lib.util
import oilsweb.lib.bib, oilsweb.lib.acq.search, oilsweb.lib.acq.picklist
import osrf.cache, osrf.json, osrf.ses
import oils.const, oils.utils.utils, oils.event


class PicklistController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r, picklist_id=kwargs['id'])
        pl_manager.retrieve()
        pl_manager.retrieve_entries(flesh_provider=True, offset=r.ctx.acq.offset, limit=r.ctx.acq.limit)
        r.ctx.acq.picklist = pl_manager.picklist
        return r.render('acq/picklist/view.html')

    def view_entry(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r)
        entry = pl_manager.retrieve_entry(kwargs.get('id'), flesh=1, flesh_provider=True)
        pl_manager.id = entry.picklist()
        picklist = pl_manager.retrieve()
        r.ctx.acq.picklist = pl_manager.picklist
        r.ctx.acq.picklist_entry = entry
        r.ctx.acq.picklist_entry_marc_html = oilsweb.lib.bib.marc_to_html(entry.marc())
        return r.render('acq/picklist/view_entry.html')

    def search(self):
        return 'search interface'


    '''
    def search(self):
        r = RequestMgr()
        r.ctx.acq.z39_sources = oilsweb.lib.acq.search.fetch_z39_sources(r.ctx)

        sc = {}
        for data in r.ctx.acq.z39_sources.values():
            for key, val in data['attrs'].iteritems():
                sc[key] = val.get('label') or key
        r.ctx.acq.search_classes = sc
        keys = sc.keys()
        keys.sort()
        r.ctx.acq.search_classes_sorted = keys
        log.debug("keys = %s" % unicode(r.ctx.acq.z39_sources))
            
        return r.render('acq/picklist/search.html')

    def pl_builder(self):
        r = RequestMgr()
        # add logic to see where we are fetching bib data from
        # XXX fix
        if r.ctx.acq.search_source:
            c.oils_acq_records, r.ctx.acq.search_cache_key = self._build_z39_search(r.ctx)

        return r.render('acq/picklist/pl_builder.html')


    def _build_z39_search(self, ctx):

        search = {
            'service' : [],
            'username' : [],
            'password' : [],
            'search' : {}
        }

        # collect the sources and credentials
        for src in ctx.acq.search_source:
            search['service'].append(src)
            search['username'].append("") # XXX config values? in-db?
            search['password'].append("") # XXX config values? in-db?

        # collect the search classes
        for cls in ctx.acq.search_class:
            if request.params[cls]:
                search['search'][cls] = request.params[cls]

        return oilsweb.lib.acq.search.multi_search(ctx, search)

    def rdetails(self):
        r = RequestMgr()
        rec_id = r.ctx.acq.record_id
        cache_key = r.ctx.acq.search_cache_key

        results = osrf.cache.CacheClient().get(cache_key)
        rec = self._find_cached_record(results, rec_id)
        if rec:
            r.ctx.acq.record = rec
            r.ctx.acq.record_html = oilsweb.lib.bib.marc_to_html(rec['marcxml'])
            return r.render('acq/picklist/rdetails.html')
        return 'exception -> no record'


    def view_picklist(self):
        r = RequestMgr()
        ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)
        picklist = osrf

        
    def create_picklist(self):  
        r = RequestMgr()
        if not isinstance(r.ctx.acq.picklist_item, list):
            r.ctx.acq.picklist_item = [r.ctx.acq.picklist_item]

        results = osrf.cache.CacheClient().get(r.ctx.acq.search_cache_key)

        records = []
        for cache_id in r.ctx.acq.picklist_item:
            rec = self._find_cached_record(results, cache_id)
            records.append(rec)

        c.oils_acq_records = records # XXX
        return r.render('acq/picklist/view.html')

    def _find_cached_record(self, results, cache_id):
        for res in results:
            for rec in res['records']:
                if str(rec['cache_id']) == str(cache_id):
                    return rec
'''
