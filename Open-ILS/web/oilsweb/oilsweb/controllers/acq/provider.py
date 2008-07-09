from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr
from osrf.ses import ClientSession
from osrf.net_obj import NetworkObject
from oils.event import Event
from oils.org import OrgUtil
from oilsweb.lib.user import User
import oils.const

class ProviderController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        r.ctx.acq.provider_id = kwargs['id']
        return r.render('acq/financial/view_provider.html')

    def list(self):
        return RequestMgr().render('acq/financial/list_providers.html')


