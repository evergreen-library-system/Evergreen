from oilsweb.lib.context import Context, SubContext, ContextItem

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
        self.picklist_id_list = ContextItem(cgi_name='acq.plil', multi=True) # list of picklist IDs
        self.picklist_name = ContextItem(cgi_name='acq.pln')
        self.picklist_action = ContextItem(cgi_name='acq.pla')
        self.picklist_source_id = ContextItem(cgi_name='acq.plsi')
        self.picklist_dest_id = ContextItem(cgi_name='acq.pldi')

        self.lineitem = ContextItem() # lineitem object
        self.lineitem_id = ContextItem(cgi_name='acq.liid')
        self.lineitem_item_count = ContextItem(cgi_name='acq.pllic')
        self.lineitem_id_list = ContextItem(cgi_name='acq.pleil', multi=True)
        self.lineitem_detail_id = ContextItem(cgi_name='acq.lidid')

        self.currency_types = ContextItem()

        self.fund = ContextItem()
        self.fund_id = ContextItem(cgi_name='acq.fi')
        self.fund_list = ContextItem(cgi_name='acq.fl')
        self.fund_name = ContextItem(cgi_name='acq.fn')
        self.fund_year = ContextItem(cgi_name='acq.fc')
        self.fund_org = ContextItem(cgi_name='acq.fo')
        self.fund_currency_type = ContextItem(cgi_name='acq.fc')
        self.fund_summary = ContextItem()

        self.funding_source = ContextItem()
        self.funding_source_id = ContextItem(cgi_name='acq.fsi')
        self.funding_source_list = ContextItem()
        self.funding_source_name = ContextItem(cgi_name='acq.fsn')
        self.funding_source_currency_type = ContextItem(cgi_name='acq.fsc')
        self.funding_source_owner = ContextItem(cgi_name='acq.fso')
        self.funding_source_credit_amount = ContextItem(cgi_name='acq.fsca')
        self.funding_source_credit_note = ContextItem(cgi_name='acq.fscn')

        self.fund_allocation = ContextItem()
        self.fund_allocation_list = ContextItem()
        self.fund_allocation_source= ContextItem(cgi_name='acq.fas')
        self.fund_allocation_fund = ContextItem(cgi_name='acq.faf')
        self.fund_allocation_amount = ContextItem(cgi_name='acq.faa')
        self.fund_allocation_percent = ContextItem(cgi_name='acq.fap')
        self.fund_allocation_note = ContextItem(cgi_name='acq.fan')

        self.provider = ContextItem()
        self.provider_id = ContextItem(cgi_name='acq.proid')
        self.provider_list = ContextItem()
        self.provider_name = ContextItem(cgi_name='acq.pn')
        self.provider_currency_type = ContextItem(cgi_name='acq.pct')
        self.provider_owner = ContextItem(cgi_name='acq.po')

        self.po = ContextItem()
        self.po_list = ContextItem()
        self.po_id = ContextItem(cgi_name='acq.poid')
        self.po_li_id_list = ContextItem(cgi_name='acq.poliil', multi=True)
        self.po_li = ContextItem()
        self.po_li_sum = ContextItem()

        self.lineitem_marc_html = ContextItem()

    def postinit(self):
        self.prefix.value = "%s/acq" % Context.get_context().core.prefix.value

Context.apply_sub_context('acq', AcqContext)

