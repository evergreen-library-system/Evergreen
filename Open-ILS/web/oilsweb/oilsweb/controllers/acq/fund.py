from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.acq.fund
import osrf.net_obj
import oils.org

class FundController(BaseController):

    def view(self, **kwargs):
        return 'view %s' % kwargs['id']

    def create(self):
        r = RequestMgr()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)

        if r.ctx.acq.fund_name:
            fund = osrf.net_obj.NetworkObject.acqfund()
            fund.name(r.ctx.acq.fund_name)
            fund.owner(r.ctx.acq.fund_owner)
            fund.currency_type(r.ctx.acq.fund_currency_type)
            fund_id = fund_mgr.create_fund(fund)
            redirect_to(controller='acq/fund', action='view', id=fund_id)

        r.ctx.acq.currency_types = fund_mgr.fetch_currency_types()
        r.ctx.core.org_tree = oils.org.OrgUtil.fetch_org_tree()
        return r.render('acq/financial/create_fund.html')

