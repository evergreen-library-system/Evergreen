from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr

import logging, pylons
import oilsweb.lib.context
import oilsweb.lib.util
import oilsweb.lib.acq.search
import oilsweb.lib.bib
import osrf.cache, osrf.json
from oilsweb.lib.context import Context, SubContext, ContextItem

log = logging.getLogger(__name__)

class AcqContext(SubContext):
    ''' Define the CGI params for this application '''
    def __init__(self):
        self.query = ContextItem(cgi_name='acq.q')
        self.search_class = ContextItem(cgi_name='acq.sc', multi=True)
        self.search_source = ContextItem(cgi_name='acq.ss', multi=True)
        self.picked_records = ContextItem(cgi_name='acq.sr', multi=True)
        self.search_cache_key = ContextItem(cgi_name='acq.sk')
        self.record_id = ContextItem(cgi_name='acq.r')
        self.record = ContextItem(cgi_name='acq.r')
        self.picklist_item = ContextItem(cgi_name='acq.pi', multi=True)
        self.extract_bib_field = ContextItem(default_value=oilsweb.lib.acq.search.extract_bib_field)
        self.prefix = ContextItem()
        self.z39_sources = ContextItem()
        self.search_classes = ContextItem()
        self.search_classes_sorted = ContextItem()

    def postinit(self):
        self.prefix = "%s/acq" % Context.getContext().core.prefix

Context.applySubContext('acq', AcqContext)


class AcqController(BaseController):

    def index(self):
        return RequestMgr().render('acq/index.html')

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
            
        return r.render('acq/search.html')
        

    def pl_builder(self):
        r = RequestMgr()
        # add logic to see where we are fetching bib data from
        # XXX fix
        if r.ctx.acq.search_source:
            c.oils_acq_records, r.ctx.acq.search_cache_key = self._build_z39_search(r.ctx)

        return r.render('acq/pl_builder.html')


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
            #r.ctx.acq.record_html = oilsweb.lib.bib.marc_to_html(rec['marcxml'])
            return r.render('acq/rdetails.html')
        return 'exception -> no record'

        
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
        return r.render('acq/picklist.html')

    def _find_cached_record(self, results, cache_id):
        for res in results:
            for rec in res['records']:
                if str(rec['cache_id']) == str(cache_id):
                    return rec

