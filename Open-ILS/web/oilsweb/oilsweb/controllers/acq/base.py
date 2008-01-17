from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr

class BaseController(BaseController):
    def index(self):
        return RequestMgr().render('acq/index.html')
