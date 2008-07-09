from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import osrf.net_obj
import oils.const
from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil

class FundingSourceController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        r.ctx.acq.funding_source_id = kwargs['id']
        return r.render('acq/financial/view_funding_source.html')

    def list(self):
        return RequestMgr().render('acq/financial/list_funding_sources.html')

       
