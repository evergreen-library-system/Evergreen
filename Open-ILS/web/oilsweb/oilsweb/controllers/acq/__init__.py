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

        # -------------------------------------------------------------
        # shared objects and data
        self.prefix = ContextItem()
        self.z39_sources = ContextItem()
        self.search_classes = ContextItem()
        self.search_classes_sorted = ContextItem()

        self.picklist = ContextItem() # picklist object
        self.picklist_list = ContextItem() # list of picklist objects
        self.picklist_id_list = ContextItem(cgi_name='acq.pli') # list of picklist IDs
        self.picklist_entry = ContextItem() # picklist_entry object
        self.picklist_name = ContextItem(cgi_name='acq.pln')

        self.currency_types = ContextItem()

        self.fund = ContextItem()
        self.fund_id = ContextItem(cgi_name='acq.fi')
        self.fund_list = ContextItem()
        self.fund_name = ContextItem(cgi_name='acq.fn')
        self.fund_year = ContextItem(cgi_name='acq.fc')
        self.fund_org = ContextItem(cgi_name='acq.fo')
        self.fund_currency_type = ContextItem(cgi_name='acq.fc')
        self.fund_summary = ContextItem()

        self.fund_source = ContextItem()
        self.fund_source_list = ContextItem()
        self.fund_source_name = ContextItem(cgi_name='acq.fsn')
        self.fund_source_currency_type = ContextItem(cgi_name='acq.fsc')
        self.fund_source_owner = ContextItem(cgi_name='acq.fso')


        self.fund_allocation = ContextItem()
        self.fund_allocation_list = ContextItem()
        self.fund_allocation_source= ContextItem(cgi_name='acq.fas')
        self.fund_allocation_fund = ContextItem(cgi_name='acq.faf')
        self.fund_allocation_amount = ContextItem(cgi_name='acq.faa')
        self.fund_allocation_percent = ContextItem(cgi_name='acq.fap')
        self.fund_allocation_note = ContextItem(cgi_name='acq.fan')


        # -------------------------------------------------------------
        # utility functions
        self.find_entry_attr = ContextItem(
            default_value=oilsweb.lib.acq.picklist.PicklistMgr.find_entry_attr)

        self.picklist_entry_marc_html = ContextItem()

    def postinit(self):
        self.prefix = "%s/acq" % Context.get_context().core.prefix

Context.apply_sub_context('acq', AcqContext)

