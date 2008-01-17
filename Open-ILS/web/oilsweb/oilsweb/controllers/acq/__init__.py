from oilsweb.lib.context import Context, SubContext, ContextItem
import oilsweb.lib.acq.search
import oilsweb.lib.acq.picklist

# ----------------------------------------------------------------
# Define the CGI params for this application 
# ----------------------------------------------------------------

class AcqContext(SubContext):
    def __init__(self):
        self.query = ContextItem(cgi_name='acq.q')
        self.search_class = ContextItem(cgi_name='acq.sc', multi=True)
        self.search_source = ContextItem(cgi_name='acq.ss', multi=True)
        self.picked_records = ContextItem(cgi_name='acq.sr', multi=True)
        self.search_cache_key = ContextItem(cgi_name='acq.sk')
        self.record_id = ContextItem(cgi_name='acq.ri')
        self.record = ContextItem(cgi_name='acq.r')
        self.picklist_item = ContextItem(cgi_name='acq.pi', multi=True)
        self.prefix = ContextItem()
        self.z39_sources = ContextItem()
        self.search_classes = ContextItem()
        self.search_classes_sorted = ContextItem()
        self.picklist_id = ContextItem(cgi_name='acq.pl')
        self.picklist = ContextItem()
        self.offset = ContextItem(cgi_name='acq.os')
        self.limit = ContextItem(cgi_name='acq.li')

        self.extract_bib_field = ContextItem(default_value=oilsweb.lib.acq.search.extract_bib_field)
        self.find_entry_attr = ContextItem(default_value=oilsweb.lib.acq.picklist.PicklistMgr.find_entry_attr)

    def postinit(self):
        self.prefix = "%s/acq" % Context.getContext().core.prefix

Context.applySubContext('acq', AcqContext)
