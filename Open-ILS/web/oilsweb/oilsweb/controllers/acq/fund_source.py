from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.acq.fund
import osrf.net_obj
import oils.org


class FundSourceController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        r.ctx.core.org_tree = oils.org.OrgUtil.fetch_org_tree()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)
        source = fund_mgr.retrieve_fund_source(kwargs.get('id'))
        source.owner(oils.org.OrgUtil.get_org_unit(source.owner())) # flesh the owner
        r.ctx.acq.fund_source = source
        return r.render('acq/financial/view_fund_source.html')

    def list(self):
        r = RequestMgr()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)
        r.ctx.acq.fund_source_list = fund_mgr.retrieve_org_fund_sources()
        for f in r.ctx.acq.fund_source_list:
            f.owner(oils.org.OrgUtil.get_org_unit(f.owner()))
        return r.render('acq/financial/list_fund_sources.html')
            

    def create(self):
        r = RequestMgr()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)

        if r.ctx.acq.fund_source_name:
            source = osrf.net_obj.NetworkObject.acqfs()
            source.name(r.ctx.acq.fund_source_name)
            source.owner(r.ctx.acq.fund_source_owner)
            source.currency_type(r.ctx.acq.fund_source_currency_type)
            source_id = fund_mgr.create_fund_source(source)
            return redirect_to(controller='acq/fund_source', action='view', id=source_id)

        perm_orgs = osrf.ses.ClientSession.atomic_request(
            'open-ils.actor',
            'open-ils.actor.user.work_perm.highest_org_set',
            r.ctx.core.authtoken, 'CREATE_FUNDING_SOURCE');

        if len(perm_orgs) == 0:
            return _("Insufficient Permissions") # XXX Return a perm failure template

        r.ctx.core.org_tree = oils.org.OrgUtil.fetch_org_tree()
        r.ctx.core.perm_tree['CREATE_FUNDING_SOURCE'] = oils.org.OrgUtil.get_union_tree(perm_orgs)
        r.ctx.core.high_perm_orgs['CREATE_FUNDING_SOURCE'] = perm_orgs
        r.ctx.acq.currency_types = fund_mgr.fetch_currency_types()
        return r.render('acq/financial/create_fund_source.html')



