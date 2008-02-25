from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr
from oilsweb.lib.acq import provider_mgr;
import oilsweb.lib.user
import osrf.net_obj
import oils.const
from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil
import mx.DateTime.ISO
import oilsweb.lib.acq.po_manager

# open-ils.acq.purchase_order.retrieve "2f9697131c80e49fb9f2515781102f6a",
# 8, {"flesh_lineitems":1,"clear_marc":1}


class PoController(BaseController):

    # Render list of Purchase Orders
    def list(self, **kwargs):
        r = RequestMgr()
        po_mgr = oilsweb.lib.acq.po_manager.PO_Manager(r)
        po_list = po_mgr.retrieve_po_list()
        provider_map = dict()
        for po in po_list:
            if not (po.provider() in provider_map):
                provider_map[po.provider()] = provider_mgr.retrieve(r, po.provider()).name()
            po.provider(provider_map[po.provider()])
        r.ctx.acq.po_list.value = po_list
        return r.render('acq/po/view_po_list.html')

    # Render display of individual PO: list of line items
    def view(self, **kwargs):
        r = RequestMgr()
        po_mgr = oilsweb.lib.acq.po_manager.PO_Manager(r, poid=kwargs['id'])
        po_mgr.retrieve()
        r.ctx.acq.po.value = po_mgr.po
        r.ctx.acq.provider.value = provider_mgr.retrieve(r, po_mgr.po.provider())
        return r.render('acq/po/view_po.html')

    # Render individual line item: list of detail info
    def view_lineitem(self, **kwargs):
        r = RequestMgr()
        po_mgr = oilsweb.lib.acq.po_manager.PO_Manager(r, liid=kwargs['id'])
        po_mgr.retrieve_lineitem()
        r.ctx.acq.po_li.value = po_mgr.li

        summary = dict()
        for det in po_mgr.li.lineitem_details():
            fund = det.fund().name()
            try:
                summary[fund] += 1
            except LookupError:
                summary[fund] = 1
        r.ctx.acq.po_li_sum.value = summary

        po_mgr.id = po_mgr.li.purchase_order()
        po_mgr.retrieve(flesh_lineitems=0)
        r.ctx.acq.po.value = po_mgr.po

        return r.render('acq/po/view_lineitem.html')
