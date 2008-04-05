from oilsweb.lib.base import *
import pylons
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.acq.fund
import osrf.net_obj
import oils.const
from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil


class FundingSourceController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        ses = ClientSession(oils.const.OILS_APP_ACQ)
        r.ctx.core.org_tree.value = OrgUtil.fetch_org_tree()

        source = ses.request(
            'open-ils.acq.funding_source.retrieve', 
            r.ctx.core.authtoken.value, kwargs.get('id'), {"flesh_summary":1}).recv().content()
        Event.parse_and_raise(source)

        source.owner(OrgUtil.get_org_unit(source.owner())) # flesh the owner
        r.ctx.acq.funding_source.value = source
        return r.render('acq/financial/view_funding_source.html')

    def list(self):
        return RequestMgr().render('acq/financial/list_funding_sources.html')

    def create(self):
        r = RequestMgr()
        fund_mgr = oilsweb.lib.acq.fund.FundMgr(r)

        if r.ctx.acq.funding_source_name.value:
            source = osrf.net_obj.NetworkObject.acqfs()
            source.name(r.ctx.acq.funding_source_name.value)
            source.owner(r.ctx.acq.funding_source_owner.value)
            source.currency_type(r.ctx.acq.funding_source_currency_type.value)
            source_id = fund_mgr.create_funding_source(source)
            return redirect_to(controller='acq/funding_source', action='view', id=source_id)

        perm_orgs = ClientSession.atomic_request(
            'open-ils.actor',
            'open-ils.actor.user.work_perm.highest_org_set',
            r.ctx.core.authtoken.value, 'CREATE_FUNDING_SOURCE');

        if len(perm_orgs) == 0:
            return _("Insufficient Permissions") # XXX Return a perm failure template

        r.ctx.core.perm_tree.value['CREATE_FUNDING_SOURCE'] = OrgUtil.get_union_tree(perm_orgs)
        r.ctx.core.high_perm_orgs.value['CREATE_FUNDING_SOURCE'] = perm_orgs
        r.ctx.acq.currency_types.value = fund_mgr.fetch_currency_types()
        return r.render('acq/financial/create_funding_source.html')


    def create_credit(self):
        r = RequestMgr()
        ses = ClientSession(oils.const.OILS_APP_ACQ)

        if r.ctx.acq.funding_source_credit_amount.value:

            credit = osrf.net_obj.NetworkObject.acqfscred()
            credit.funding_source(r.ctx.acq.funding_source_id.value)
            credit.amount(r.ctx.acq.funding_source_credit_amount.value)
            credit.note(r.ctx.acq.funding_source_credit_note.value)

            status = ses.request(
                'open-ils.acq.funding_source_credit.create',
                r.ctx.core.authtoken.value, credit).recv().content()
            status = Event.parse_and_raise(status)
            return redirect_to(controller='acq/funding_source', action='view', id=r.ctx.acq.funding_source_id.value)

        source = ses.request('open-ils.acq.funding_source.retrieve',
            r.ctx.core.authtoken.value, r.ctx.acq.funding_source_id.value, {"flesh_summary":1}).recv().content()
        r.ctx.acq.funding_source.value = Event.parse_and_raise(source)
        source.owner(OrgUtil.get_org_unit(source.owner()))
        return r.render('acq/financial/create_funding_source_credit.html')

        
