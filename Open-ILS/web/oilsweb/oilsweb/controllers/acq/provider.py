from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr
from oilsweb.lib.acq import provider_mgr
from osrf.ses import ClientSession
from osrf.net_obj import NetworkObject
from oils.event import Event
from oils.org import OrgUtil
from oilsweb.lib.user import User
import oils.const


class ProviderController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        provider = provider_mgr.retrieve(r, kwargs['id'])
        provider.owner(OrgUtil.get_org_unit(provider.owner()))
        r.ctx.acq.provider.value = provider
        return r.render('acq/financial/view_provider.html')


    def create(self):
        r = RequestMgr()
        ses = ClientSession(oils.const.OILS_APP_ACQ)

        if r.ctx.acq.provider_name.value: # create then display the provider

            provider = NetworkObject.acqpro()
            provider.name(r.ctx.acq.provider_name.value)
            provider.owner(r.ctx.acq.provider_owner.value)
            provider.currency_type(r.ctx.acq.provider_currency_type.value)

            provider_id = ses.request('open-ils.acq.provider.create', 
                r.ctx.core.authtoken.value, provider).recv().content()
            Event.parse_and_raise(provider_id)

            return redirect_to(controller='acq/provider', action='view', id=provider_id)

        usermgr = User(r.ctx.core)
        tree = usermgr.highest_work_perm_tree('ADMIN_PROVIDER')

        types = ses.request(
            'open-ils.acq.currency_type.all.retrieve',
            r.ctx.core.authtoken.value).recv().content()
        r.ctx.acq.currency_types.value = Event.parse_and_raise(types)


        if tree is None:
            return _("Insufficient Permissions") # XXX Return a perm failure template

        return r.render('acq/financial/create_provider.html')

    ''' Pure Python version
    def list(self):
        r = RequestMgr()
        providers = provider_mgr.list(r)
        for f in providers:
            f.owner(OrgUtil.get_org_unit(f.owner()))
        r.ctx.acq.provider_list.value = providers
        return r.render('acq/financial/list_providers.html')
    '''


    def list(self):
        return RequestMgr().render('acq/financial/list_providers.html')


