from oilsweb.lib.base import *
import urllib2, urllib, httplib
import osrf.json
import pylons

class TranslatorController(BaseController):
    ''' This controller acts as a proxy for the OpenSRF http translator
        so that paster can handle opensrf AJAX requests. '''
    def proxy(self):
        try:
            headers = {}
            for k,v in request.headers.iteritems():
                headers[k] = v
            conn = httplib.HTTPConnection(pylons.config['osrf_http_translator_host'])
            conn.request("POST", pylons.config['osrf_http_translator_path'], 
                urllib.urlencode({'osrf-msg':request.params['osrf-msg']}), headers)
            resp = conn.getresponse()
            for h in resp.getheaders():
                response.headers[h[0]] = h[1]
            return resp.read()
        except Exception, e:
            import sys
            sys.stderr.write(unicode(e) + '\n')

