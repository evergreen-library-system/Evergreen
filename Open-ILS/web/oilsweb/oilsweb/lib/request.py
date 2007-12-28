import pylons
from oilsweb.lib.base import *
import oilsweb.lib.context

class RequestMgr(object):
    ''' This is container class for aggregating the various Pylons global
        variables, initializing the local and pylons context objects, and
        rendering templates based on the skin
        '''

    def __init__(self):
        # pylons request object
        self.request = request
        # pylons response object
        self.response = response
        # pylons session
        self.session = session
        # our local context object.
        self.ctx = oilsweb.lib.context.Context.init(request, response)
        # the global pylons context object
        self.pylons_context = c
        # true if we've saved the session/cookie data, etc.
        self.finalized = False

    def finalize(self):
        ''' Perform any last minute cleanup just prior to sending the result '''
        if not self.finalized:
            self.session.save()
            self.ctx.apply_cookies()
            self.pylons_context.oils = self.ctx
            self.finalized = True
        
    def render(self, tpath):
        ''' Renders the given template using the configured skin.
            @param tpath The path to the template.  The tpath should 
            only include the path to the template after the skin component.
            E.g. if the full path is /oils/myskin/base/dashboard.html, tpath
            would be 'base/dashboard.html'
            '''
        self.finalize()
        return pylons.templating.render('oils/%s/%s' % (self.ctx.core.skin, tpath))



