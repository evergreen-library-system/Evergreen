import osrf.ses, osrf.net_obj
import oils.const, oils.utils.utils, oils.event

class FundMgr(object):
    ''' Fund utility class '''
    def __init__(self, request_mgr, **kwargs):
        self.request_mgr = request_mgr
        self.ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)
        
    def fetch_currency_types(self):
        types = self.ses.request(
            'open-ils.acq.currency_type.all.retrieve',
            self.request_mgr.ctx.core.authtoken).recv().content()
        oils.event.Event.parse_and_raise(types)
        return types

    def create_fund(self, fund):
        fund_id = self.ses.request(
            'open-ils.acq.fund.create', 
            self.request_mgr.ctx.core.authtoken, fund).recv().content()
        oils.event.Event.parse_and_raise(fund_id)
        return fund_id

    
