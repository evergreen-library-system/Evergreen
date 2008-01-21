from oilsweb.lib.context import Context, SubContext, ContextItem
import oilsweb.lib.acq.search
import oilsweb.lib.acq.picklist

# ----------------------------------------------------------------
# Define the CGI params for this application 
# ----------------------------------------------------------------

class AcqContext(SubContext):
    def __init__(self):

        # -------------------------------------------------------------
        # URL params
        self.query = ContextItem(cgi_name='acq.q')
        self.search_class = ContextItem(cgi_name='acq.sc', multi=True)
        self.search_source = ContextItem(cgi_name='acq.ss', multi=True)
        self.picked_records = ContextItem(cgi_name='acq.sr', multi=True)
        self.offset = ContextItem(cgi_name='acq.os', default_value=0)
        self.limit = ContextItem(cgi_name='acq.li', default_value=10)

        #self.search_cache_key = ContextItem(cgi_name='acq.sk')
        #self.record_id = ContextItem(cgi_name='acq.ri')
        #self.record = ContextItem(cgi_name='acq.r')
        #self.picklist_item = ContextItem(cgi_name='acq.pi', multi=True)

        # -------------------------------------------------------------
        # shared objects and data
        self.prefix = ContextItem()
        self.z39_sources = ContextItem()
        self.search_classes = ContextItem()
        self.search_classes_sorted = ContextItem()

        self.picklist = ContextItem() # picklist object
        self.picklist_list = ContextItem() # list of picklist objects
        self.picklist_id_list = ContextItem() # list of picklist objects
        self.picklist_entry = ContextItem() # picklist_entry object

        # -------------------------------------------------------------
        # utility functions
        self.find_entry_attr = ContextItem(
            default_value=oilsweb.lib.acq.picklist.PicklistMgr.find_entry_attr)

        self.picklist_entry_marc_html = ContextItem()

    def postinit(self):
        self.prefix = "%s/acq" % Context.getContext().core.prefix

Context.applySubContext('acq', AcqContext)

