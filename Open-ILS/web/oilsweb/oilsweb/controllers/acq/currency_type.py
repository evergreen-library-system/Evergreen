from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr

class CurrencyTypeController(BaseController):
    def list(self, **kwargs):
        r = RequestMgr()
        return r.render('acq/financial/list_currency_types.html')

