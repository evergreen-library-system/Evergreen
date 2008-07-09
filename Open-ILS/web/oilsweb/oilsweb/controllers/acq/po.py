from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.user
import osrf.net_obj
import oils.const
from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil
import mx.DateTime.ISO

class PoController(BaseController):

    # Render display of individual PO: list of line items
    def view(self, **kwargs):
        r = RequestMgr()
        r.ctx.acq.po_id.value = kwargs['id']
        return r.render('acq/po/view_po.html')

    def li_search(self):
        r = RequestMgr()
        return r.render('acq/po/li_search.html')

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

        oils.system.System.remote_connect(
            config_file = pylons.config['osrf_config'],
            config_context = pylons.config['osrf_config_ctxt'])

        if 'marc_file' in r.request.params:

            provider_id = r.request.params['provider']
            authtoken = r.request.params['authtoken']

            # first, create the PO
            po = osrf.net_obj.NetworkObject.acqpo()
            po.provider(provider_id)
            po.state('in-process')
            po_id = ClientSession.atomic_request(
                'open-ils.acq', 
                'open-ils.acq.purchase_order.create', authtoken, po)
            oils.event.Event.parse_and_raise(po_id)

            provider = ClientSession.atomic_request(
                'open-ils.acq', 
                'open-ils.acq.provider.retrieve', authtoken, provider_id)
            oils.event.Event.parse_and_raise(provider)

            # now, parse the MARC and create a lineitem per record
            marc_reader = pymarc.reader.MARCReader(r.request.params['marc_file'].file)
            for record in marc_reader:

                lineitem = osrf.net_obj.NetworkObject.jub()
                lineitem.marc(pymarc.marcxml.record_to_xml(record))
                lineitem.provider(provider_id)
                lineitem.purchase_order(po_id)
                lineitem.source_label(provider.code()) # XXX where should this really come from?
                lineitem.state('in-process')

                stat = ClientSession.atomic_request(
                    'open-ils.acq', 
                    'open-ils.acq.lineitem.create', authtoken, lineitem)
                oils.event.Event.parse_and_raise(stat)
            return redirect_to(controller='acq/po', action='view', id=po_id)
                
        return r.render('acq/po/marc_upload.html')
