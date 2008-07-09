from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.user
import osrf.net_obj
import oils.const
from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil


class FundController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        r.ctx.acq.fund_id = kwargs['id']
        return r.render('acq/financial/view_fund.html')

    def list(self):
        return RequestMgr().render('acq/financial/list_funds.html')


