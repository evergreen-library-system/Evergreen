from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.acq.fund, oilsweb.lib.user
import osrf.net_obj, osrf.ses
import oils.org, oils.const, oils.event

class FundController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        r.ctx.core.org_tree = oils.org.OrgUtil.fetch_org_tree()
        fund_id = kwargs['id']

        ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)
        fund_req = ses.request('open-ils.acq.fund.retrieve', r.ctx.core.authtoken, fund_id)
        fund_summary_req = ses.request('open-ils.acq.fund.summary.retrieve', r.ctx.core.authtoken, fund_id)

        # grab the fund object
        fund = fund_req.recv().content()
        oils.event.Event.parse_and_raise(fund)
        fund.org(oils.org.OrgUtil.get_org_unit(fund.org())) # flesh the org
        r.ctx.acq.fund = fund

        # grab the fund summary
        fund_summary = fund_summary_req.recv().content()
        oils.event.Event.parse_and_raise(fund_summary)
        r.ctx.acq.fund_summary = fund_summary

        return r.render('acq/financial/view_fund.html')

    def list(self):
        r = RequestMgr()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)
        r.ctx.acq.fund_list = fund_mgr.retrieve_org_funds()
        for f in r.ctx.acq.fund_list:
            f.org(oils.org.OrgUtil.get_org_unit(f.org()))
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

    def allocate(self):
        r = RequestMgr()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)

        if r.ctx.acq.fund_allocation_source:
            alloc = osrf.net_obj.NetworkObject.acqfa()
            alloc.funding_source(r.ctx.acq.fund_allocation_source)
            alloc.fund(r.ctx.acq.fund_allocation_fund)
            if r.ctx.acq.fund_allocation_amount:
                alloc.amount(r.ctx.acq.fund_allocation_amount)
            else:
                alloc.percent(r.ctx.acq.fund_allocation_percent)
            alloc.note(r.ctx.acq.fund_allocation_note)
            fund_mgr.create_allocation(alloc)
            return redirect_to(controller='acq/fund', action='view', id=r.ctx.acq.fund_allocation_fund)

        fund = fund_mgr.retrieve(r.ctx.acq.fund_id)
        fund.org(oils.org.OrgUtil.get_org_unit(fund.org())) # flesh the org
        r.ctx.acq.fund = fund
        r.ctx.acq.fund_source_list = fund_mgr.retrieve_org_fund_sources('MANAGE_FUNDING_SOURCE')
        return r.render('acq/financial/create_fund_allocation.html')



