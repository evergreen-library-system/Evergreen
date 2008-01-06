from oilsweb.lib.context import Context, SubContext, ContextItem
import osrf.ses, oils.utils.csedit, pylons.config
from gettext import gettext as _

class AuthException(Exception):
    def __init__(self, info=''):
        self.info = info
    def __str__(self):
        return "%s: %s" % (self.__class__.__name__, unicode(self.info))
        
    

class CoreContext(SubContext):
    def __init__(self):
        self.prefix = ContextItem() # web prefix
        self.media_prefix = ContextItem() # media prefix
        self.ac_prefix = ContextItem() # added content prefix
        self.skin = ContextItem() # web skin
        self.theme = ContextItem() # web theme
        self.authtoken = ContextItem(cgi_name='ses', session=True) # authtoken string
        self.user = ContextItem() # logged in user object
        self.workstation = ContextItem() # workstation object
        self.page = ContextItem() # the current page

    def postinit(self):
        import pylons.config
        self.prefix = pylons.config['oils_prefix']
        self.media_prefix = pylons.config['oils_media_prefix']
        self.ac_prefix = pylons.config['oils_added_content_prefix']

        self.skin = 'default' # XXX
        self.theme = 'default' # XXX

        self.fetchUser()

    _auth_cache = {}
    def fetchUser(self):
        ''' Grab the logged in user and their workstation '''
        if self.authtoken:

            if self.authtoken in CoreContext._auth_cache:
                self.user = CoreContext._auth_cache[self.authtoken]['user']
                self.workstation = CoreContext._auth_cache[self.authtoken]['workstation']
                return

            self.user = osrf.ses.AtomicRequest(
                'open-ils.auth', 
                'open-ils.auth.session.retrieve', self.authtoken)

            if not self.user:
                raise AuthException(_('No user found with authtoken %(self.authtoken)s'))
            self.workstation = oils.utils.csedit.CSEditor().retrieve_actor_workstation(self.user.wsid())

            if not self.workstation:
                raise AuthException(_('No workstation found'))

            # cache the auth data and destroy any old auth data
            CoreContext._auth_cache = {
                self.authtoken : {
                    'user' : self.user, 
                    'workstation' : self.workstation
                }
            }
        else:
            raise AuthException(_('No authentication token provided'))
        
Context.applySubContext('core', CoreContext)


class UtilContext(SubContext):
    ''' The UtilContext maintains a set of general use functions '''
    def __init__(self):
        import oilsweb.lib.bib
        self.scrub_isbn = ContextItem(default_value=oilsweb.lib.bib.scrub_isbn)

Context.applySubContext('util', UtilContext)

