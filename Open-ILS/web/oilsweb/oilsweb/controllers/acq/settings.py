from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr
import oilsweb.lib.user
import osrf.net_obj
import oils.const
from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil

class SettingsController(BaseController):
    def li_attr(self, **kwargs):
        return RequestMgr().render('acq/settings/li_attr.html')
