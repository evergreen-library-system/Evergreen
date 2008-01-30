import osrf.ses, osrf.net_obj
import oils.const, oils.utils.utils, oils.event, oils.org

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

    ''' XXX update to look like a fund 
    def retrieve(self, fund_id):
        fund = self.ses.request(
            'open-ils.acq.fund.retrieve', 
            self.request_mgr.ctx.core.authtoken, fund_id).recv().content()
        oils.event.Event.parse_and_raise(fund)
        return fund

    def retrieve_org_funds(self):
        funds = self.ses.request(
            'open-ils.acq.fund.org.retrieve', 
            self.request_mgr.ctx.core.authtoken, 
            self.request_mgr.ctx.core.workstation.owning_lib(),
            {"full_path":1}).recv().content()
        oils.event.Event.parse_and_raise(funds)
        return funds


    def create_fund(self, fund):
        fund_id = self.ses.request(
            'open-ils.acq.fund.create', 
            self.request_mgr.ctx.core.authtoken, fund).recv().content()
        oils.event.Event.parse_and_raise(fund_id)
        return fund_id
    '''

    
    def retrieve_fund_source(self, source_id):
        source = self.ses.request(
            'open-ils.acq.funding_source.retrieve', 
            self.request_mgr.ctx.core.authtoken, source_id).recv().content()
        oils.event.Event.parse_and_raise(source)
        return source

    def retrieve_org_fund_sources(self):
        sources = self.ses.request(
            'open-ils.acq.funding_source.org.retrieve', 
            self.request_mgr.ctx.core.authtoken, 
            self.request_mgr.ctx.core.workstation.owning_lib(),
            {"full_path":1}).recv().content()
        oils.event.Event.parse_and_raise(sources)
        return sources


    def create_fund_source(self, source):
        source_id = self.ses.request(
            'open-ils.acq.funding_source.create', 
            self.request_mgr.ctx.core.authtoken, source).recv().content()
        oils.event.Event.parse_and_raise(source_id)
        return source_id


