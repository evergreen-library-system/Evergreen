from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr
from oilsweb.lib.acq import provider_mgr
import oilsweb.lib.user
import osrf.net_obj
import oils.const
from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil
import mx.DateTime.ISO
import oilsweb.lib.acq.po_manager
from oilsweb.lib.acq.picklist import PicklistMgr
from oilsweb.lib.acq.fund import FundMgr

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
        r.ctx.acq.po_id.value = kwargs['id']
        return r.render('acq/po/view_po.html')

    # Create PO from contents of picklist
    def create(self, **kwargs):
        r = RequestMgr()
        if not r.ctx.acq.picklist_source_id.value:
            plmgr = PicklistMgr(r,
                                picklist_id=r.ctx.acq.picklist_source_id.value)
            r.ctx.acq.picklist_list.value = plmgr.retrieve_list(r)

            r.ctx.acq.fund_list.value = FundMgr(r).retrieve_org_funds()
            provider_list = provider_mgr.list(r)
            for p in provider_list:
                p.owner(OrgUtil.get_org_unit(p.owner()))
            r.ctx.acq.provider_list.value = provider_list
            return r.render('acq/po/create.html')

        po = osrf.net_obj.NetworkObject.acqpo()
        po.owner(r.ctx.core.user.value.id())
        po.provider(r.ctx.acq.provider_id.value)
        po.default_fund(r.ctx.acq.fund_id.value)

        po_id = ClientSession.atomic_request(oils.const.OILS_APP_ACQ,
                                             'open-ils.acq.purchase_order.create',
                                             r.ctx.core.authtoken.value, po)
        Event.parse_and_raise(po_id)

        plmgr = oilsweb.lib.acq.picklist.PicklistMgr(r, picklist_id=r.ctx.acq.picklist_source_id.value)

        plmgr.retrieve()
        plmgr.retrieve_lineitems(idlist=1)

        for pl_item in plmgr.picklist.entries():
            po_lineitem = osrf.net_obj.NetworkObject.acqpoli()
            po_lineitem.purchase_order(po_id)
            po_lineitem_id = ClientSession.atomic_request(oils.const.OILS_APP_ACQ,
                                                          'open-ils.acq.po_lineitem.create',
                                                          r.ctx.core.authtoken.value,
                                                          po_lineitem,
                                                          { 'picklist_entry': pl_item})
            Event.parse_and_raise(po_lineitem_id)

        return redirect_to(controller='acq/po', action='view', id=po_id)

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

    def delete(self, **kwargs):
        r = RequestMgr()
        ClientSession.atomic_request(oils.const.OILS_APP_ACQ,
                                     'open-ils.acq.purchase_order.delete',
                                     r.ctx.core.authtoken.value, kwargs['id'])
        return r.render('acq/po/list')

    def search(self):
        r = RequestMgr()
        return r.render('acq/po/search.html')

    def marc_upload(self):
        '''
        Requires pymarc-1.5, elementree
        $ easy_install elementtree
        $ easy_install http://pypi.python.org/packages/source/p/pymarc/pymarc-1.5.tar.gz

        Takes a MARC file, converts it to marcxml, and creates a new PO 
        and lineitems from the data.
        '''

        import pymarc
        import pymarc.reader
        import pymarc.marcxml
        import pylons
        import oils.system

        r = RequestMgr()

        oils.system.System.connect(
            config_file = pylons.config['osrf_config'],
            config_context = pylons.config['osrf_config_ctxt'])

        if 'marc_file' in r.request.params:

            provider = r.request.params['provider']
            authtoken = r.request.params['authtoken']

            # first, create the PO
            po = osrf.net_obj.NetworkObject.acqpo()
            po.provider(provider)
            po_id = ClientSession.atomic_request('open-ils.acq', 
                'open-ils.acq.purchase_order.create', authtoken, po)
            oils.event.Event.parse_and_raise(po_id)

            # now, parse the MARC and create a lineitem per record
            marc_reader = pymarc.reader.MARCReader(r.request.params['marc_file'].file)
            for record in marc_reader:

                lineitem = osrf.net_obj.NetworkObject.jub()
                lineitem.marc(pymarc.marcxml.record_to_xml(record))
                lineitem.provider(provider)
                lineitem.purchase_order(po_id)

                stat = ClientSession.atomic_request('open-ils.acq', 
                    'open-ils.acq.lineitem.create', authtoken, lineitem)
                oils.event.Event.parse_and_raise(stat)
                return redirect_to(controller='acq/po', action='view', id=po_id)
                
        return r.render('acq/po/marc_upload.html')


