from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.acq.fund
import osrf.net_obj
import oils.org

# XXX update to match new fund layout

class FundController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        r.ctx.core.org_tree = oils.org.OrgUtil.fetch_org_tree()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)
        fund = fund_mgr.retrieve(kwargs.get('id'))
        fund.owner(oils.org.OrgUtil.get_org_unit(fund.owner())) # flesh the owner
        r.ctx.acq.fund = fund
        return r.render('acq/financial/view_fund.html')

    def list(self):
        r = RequestMgr()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)
        r.ctx.acq.fund_list = fund_mgr.retrieve_org_funds()
        for f in r.ctx.acq.fund_list:
            f.owner(oils.org.OrgUtil.get_org_unit(f.owner()))
        return r.render('acq/financial/list_funds.html')
            

    def create(self):
        r = RequestMgr()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)

        if r.ctx.acq.fund_name:
            fund = osrf.net_obj.NetworkObject.acqfund()
            fund.name(r.ctx.acq.fund_name)
            fund.owner(r.ctx.acq.fund_owner)
            fund.currency_type(r.ctx.acq.fund_currency_type)
            fund_id = fund_mgr.create_fund(fund)
            return redirect_to(controller='acq/fund', action='view', id=fund_id)

        r.ctx.acq.currency_types = fund_mgr.fetch_currency_types()
        r.ctx.core.org_tree = oils.org.OrgUtil.fetch_org_tree()
        return r.render('acq/financial/create_fund.html')
