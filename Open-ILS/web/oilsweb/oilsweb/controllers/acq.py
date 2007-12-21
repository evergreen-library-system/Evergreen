from oilsweb.lib.base import *

import logging
import pylons
import oilsweb.lib.context
import oilsweb.lib.util
import oilsweb.lib.acq.search
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
Context.applySubContext('acq', AcqContext)


class AcqController(BaseController):

    def index(self):
        c.oils = oilsweb.lib.context.Context.init(request)
        return render('oils/%s/acq/index.html' % c.oils.core.skin)

    def search(self):
        c.oils = Context.init(request)
        c.oils_z39_sources = oilsweb.lib.acq.search.fetch_z39_sources(c.oils)

        sc = {}
        for data in c.oils_z39_sources.values():
            for key, val in data['attrs'].iteritems():
                sc[key] = val.get('label') or key
        c.oils_search_classes = sc
            
        return render('oils/%s/acq/search.html' % c.oils.core.skin)
        

    def pl_builder(self):
        c.oils = oilsweb.lib.context.Context.init(request)
        # add logic to see where we are fetching bib data from

        if c.oils.acq.search_source:
            c.oils_acq_records, c.oils.acq.search_cache_key = self._build_z39_search(c.oils)

        c.oils.acq.extract_bib_field = oilsweb.lib.acq.search.extract_bib_field
        return render('oils/%s/acq/pl_builder.html' % c.oils.core.skin)


    def _build_z39_search(self, ctx):

        search = {
            'service' : [],
            'username' : [],
            'password' : [],
            'search' : {}
        }

        # collect the sources and credentials
        for src in c.oils.acq.search_source:
            search['service'].append(src)
            search['username'].append("") # XXX config values? in-db?
            search['password'].append("") # XXX config values? in-db?

        # collect the search classes
        for cls in c.oils.acq.search_class:
            if request.params[cls]:
                search['search'][cls] = request.params[cls]

        return oilsweb.lib.acq.search.multi_search(ctx, search)

    def rdetails(self):
        c.oils = oilsweb.lib.context.Context.init(request)
        rec_id = c.oils.acq.record_id
        cache_key = c.oils.acq.search_cache_key

        results = osrf.cache.CacheClient().get(cache_key)
        for res in results:
            for rec in res['records']:
                if str(rec['cache_id']) == str(rec_id):
                    c.oils.acq.record = rec
                    return render('oils/%s/acq/rdetails.html' % c.oils.core.skin)
        return 'exception -> no record'

        


