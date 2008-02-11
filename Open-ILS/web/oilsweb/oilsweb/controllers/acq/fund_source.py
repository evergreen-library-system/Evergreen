from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.acq.fund
import osrf.net_obj
import oils.org, oils.event, oils.const


class FundSourceController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)
        r.ctx.core.org_tree = oils.org.OrgUtil.fetch_org_tree()

        source = ses.request(
            'open-ils.acq.funding_source.retrieve', 
            r.ctx.core.authtoken, kwargs.get('id'), {"flesh_summary":1}).recv().content()
        oils.event.Event.parse_and_raise(source)

        source.owner(oils.org.OrgUtil.get_org_unit(source.owner())) # flesh the owner
        r.ctx.acq.fund_source = source
        return r.render('acq/financial/view_fund_source.html')

    def list(self):
        r = RequestMgr()
        ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)

        sources = ses.request(
            'open-ils.acq.funding_source.org.retrieve', 
            r.ctx.core.authtoken, None, {"flesh_summary":1}).recv().content()

        oils.event.Event.parse_and_raise(sources)
        r.ctx.acq.fund_source_list = sources

        for source in sources:
            source.owner(oils.org.OrgUtil.get_org_unit(source.owner()))
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

        r.ctx.core.perm_tree['CREATE_FUNDING_SOURCE'] = oils.org.OrgUtil.get_union_tree(perm_orgs)
        r.ctx.core.high_perm_orgs['CREATE_FUNDING_SOURCE'] = perm_orgs
        r.ctx.acq.currency_types = fund_mgr.fetch_currency_types()
        return r.render('acq/financial/create_fund_source.html')



