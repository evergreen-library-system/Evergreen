from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.acq.fund, oilsweb.lib.user
import osrf.net_obj, osrf.ses
import oils.org, oils.const, oils.event

class FundController(BaseController):

    def _retrieve_fund(self, r, ses, fund_id):
        ''' Retrieves a fund object with summary and fleshse the org field '''
        fund = ses.request('open-ils.acq.fund.retrieve', 
            r.ctx.core.authtoken, fund_id, {"flesh_summary":1}).recv().content()
        oils.event.Event.parse_and_raise(fund)
        fund.org(oils.org.OrgUtil.get_org_unit(fund.org())) # flesh the org
        return fund


    def view(self, **kwargs):
        r = RequestMgr()
        r.ctx.core.org_tree = oils.org.OrgUtil.fetch_org_tree()
        fund_id = kwargs['id']
        ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)

        # grab the fund object
        fund = self._retrieve_fund(r, ses, fund_id)
        r.ctx.acq.fund = fund
        return r.render('acq/financial/view_fund.html')

    def list(self):
        r = RequestMgr()
        ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)
        funds = ses.request(
            'open-ils.acq.fund.org.retrieve', 
            r.ctx.core.authtoken, None, {"flesh_summary":1}).recv().content()
        oils.event.Event.parse_and_raise(funds)
        for f in funds:
            f.org(oils.org.OrgUtil.get_org_unit(f.org()))
        r.ctx.acq.fund_list = funds
        return r.render('acq/financial/list_funds.html')
            

    def create(self):
        r = RequestMgr()
        ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)

        if r.ctx.acq.fund_name: # create then display the fund

            fund = osrf.net_obj.NetworkObject.acqf()
            fund.name(r.ctx.acq.fund_name)
            fund.org(r.ctx.acq.fund_org)
            fund.year(r.ctx.acq.fund_year)

            fund_id = ses.request('open-ils.acq.fund.create', 
                r.ctx.core.authtoken, fund).recv().content()
            oils.event.Event.parse_and_raise(fund_id)

            return redirect_to(controller='acq/fund', action='view', id=fund_id)

        usermgr = oilsweb.lib.user.User(r.ctx.core)
        tree = usermgr.highest_work_perm_tree('CREATE_FUND')

        if tree is None:
            return _("Insufficient Permissions") # XXX Return a perm failure template

        return r.render('acq/financial/create_fund.html')

    def allocate(self):
        r = RequestMgr()
        ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)

        if r.ctx.acq.fund_allocation_source:
            return self._allocate(r, ses)

        fund = self._retrieve_fund(r, ses, fund_id)

        source_list = self.ses.request(
            'open-ils.acq.funding_source.org.retrieve', 
            self.request_mgr.ctx.core.authtoken, None, 'MANAGE_FUNDING_SOURCE').recv().content()
        oils.event.Event.parse_and_raise(sources)

        r.ctx.acq.fund = fund
        r.ctx.acq.fund_source_list = source_list
        return r.render('acq/financial/create_fund_allocation.html')

    def _allocate(self, r, ses):
        ''' Create a new fund_allocation '''

        alloc = osrf.net_obj.NetworkObject.acqfa()
        alloc.funding_source(r.ctx.acq.fund_allocation_source)
        alloc.fund(r.ctx.acq.fund_allocation_fund)

        if r.ctx.acq.fund_allocation_amount:
            alloc.amount(r.ctx.acq.fund_allocation_amount)
        else:
            alloc.percent(r.ctx.acq.fund_allocation_percent)
        alloc.note(r.ctx.acq.fund_allocation_note)

        alloc_id = ses.request(
            'open-ils.acq.fund_allocation.create', r.ctx.core.authtoken, alloc).recv().content()
        oils.event.Event.parse_and_raise(alloc_id)

        return redirect_to(controller='acq/fund', action='view', id=r.ctx.acq.fund_allocation_fund)



