#!/usr/bin/python
import sys
import oils.system, oils.utils.utils
import osrf.net_obj, osrf.ses

# ---------------------------------------------------------------
# Usage: python acq_fund.py <user> <password> <workstation> 
# ---------------------------------------------------------------

oils.system.oilsConnect('/openils/conf/opensrf_core.xml', 'config.opensrf')
auth_info = oils.utils.utils.login(sys.argv[1], sys.argv[2], 'staff', sys.argv[3])
authtoken = auth_info['payload']['authtoken']

ses = osrf.ses.ClientSession('open-ils.acq')
ses.connect() # not required, but faster for batches of request

# XXX This loop assumes the existence of orgs with IDs 1-6 and a USD currency
ids = []
for i in range(0,5):
    fund = osrf.net_obj.NetworkObject.acqfund()
    fund.name("test-fund-%d" % i)
    fund.owner(i+1)
    fund.currency_type('USD')
    req = ses.request('open-ils.acq.fund.create', authtoken, fund)
    id = req.recv().content()
    print 'created fund ' + str(id)
    ids.append(id)

req = ses.request('open-ils.acq.fund.org.retrieve', authtoken, 1, {"children":1})
resp = req.recv().content()
for fund in resp:
    print 'fetched fund ' + str(fund.name())

for i in ids:
    req = ses.request('open-ils.acq.fund.delete', authtoken, i)
    print 'delete returned ' + str(req.recv().content())


ses.disconnect() # only required if a connect() call was made


