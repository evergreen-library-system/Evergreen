import oils.const
from oils.event import Event
from osrf.ses import ClientSession

def retrieve(r, id):
    ses = ClientSession(oils.const.OILS_APP_ACQ)
    provider = ses.request('open-ils.acq.provider.retrieve', 
                           r.ctx.core.authtoken.value, id).recv().content()
    Event.parse_and_raise(provider)
    return provider

def list(r):
    ses = ClientSession(oils.const.OILS_APP_ACQ)
    providers = ses.request('open-ils.acq.provider.org.retrieve.atomic', 
                            r.ctx.core.authtoken.value, None,
                            {"flesh_summary":1}).recv().content()
    Event.parse_and_raise(providers)
    return providers
