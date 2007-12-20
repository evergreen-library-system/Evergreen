import logging

from oilsweb.lib.base import *
import pylons, os
import oilsweb.lib.context
import oilsweb.lib.util
import oilsweb.lib.acq.search
from oilsweb.lib.context import Context, SubContext, ContextItem

log = logging.getLogger(__name__)

class AcqContext(SubContext):
    ''' Define the CGI params for this application '''
    def __init__(self):
        self.query = ContextItem(cgi_name='acq.q')
        self.search_class = ContextItem(cgi_name='acq.sc', multi=True)
        self.search_source = ContextItem(cgi_name='acq.ss', multi=True)
        self.picked_records = ContextItem(cgi_name='acq.sr', multi=True)

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
            c.oils_acq_records = self._build_z39_search(c.oils)

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
            search['username'].append("") # XXX
            search['password'].append("") # XXX

        # collect the search classes
        for cls in c.oils.acq.search_class:
            if request.params[cls]:
                search['search'][cls] = request.params[cls]

        return oilsweb.lib.acq.search.multi_search(ctx, search)



