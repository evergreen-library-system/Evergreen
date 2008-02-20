#!/usr/bin/python
import sys
import oils.system, oils.utils.utils
import osrf.net_obj, osrf.ses

# ---------------------------------------------------------------
# Usage: python acq_fund_source.py <user> <password> <workstation> 
# ---------------------------------------------------------------

oils.system.System.connect(config_file='/openils/conf/opensrf_core.xml', config_context='config.opensrf')
auth_info = oils.utils.utils.login(sys.argv[1], sys.argv[2], 'staff', sys.argv[3])
authtoken = auth_info['payload']['authtoken']

ses = osrf.ses.ClientSession('open-ils.acq')
ses.connect() # not required, but faster for batches of request

# XXX This loop assumes the existence of orgs with IDs 1-6 and a USD currency
ids = []
for i in range(0,5):
    fund_source = osrf.net_obj.NetworkObject.acqfs()
    fund_source.name("test-fund_source-%d" % i)
    fund_source.owner(i+1)
    fund_source.currency_type('USD')
    req = ses.request('open-ils.acq.funding_source.create', authtoken, fund_source)
    id = req.recv().content()
    print 'created fund_source ' + str(id)
    ids.append(id)

req = ses.request('open-ils.acq.funding_source.org.retrieve', authtoken, 1, {"children":1})
resp = req.recv().content()
for fund_source in resp:
    print 'fetched fund_source ' + str(fund_source.name())

for i in ids:
    req = ses.request('open-ils.acq.funding_source.delete', authtoken, i)
    print 'delete returned ' + str(req.recv().content())


ses.disconnect() # only required if a connect() call was made


