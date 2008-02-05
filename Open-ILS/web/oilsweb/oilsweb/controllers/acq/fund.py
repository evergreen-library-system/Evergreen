from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.acq.fund, oilsweb.lib.user
import osrf.net_obj
import oils.org

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
            fund = osrf.net_obj.NetworkObject.acqf()
            fund.name(r.ctx.acq.fund_name)
            fund.org(r.ctx.acq.fund_org)
            fund.year(r.ctx.acq.fund_year)
            fund_id = fund_mgr.create_fund(fund)
            return redirect_to(controller='acq/fund', action='view', id=fund_id)

        usermgr = oilsweb.lib.user.User(r.ctx.core)
        tree = usermgr.highest_work_perm_tree('CREATE_FUND')

        if tree is None:
            return _("Insufficient Permissions") # XXX Return a perm failure template

        return r.render('acq/financial/create_fund.html')


