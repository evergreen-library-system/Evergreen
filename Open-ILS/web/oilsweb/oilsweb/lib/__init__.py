from oilsweb.lib.context import Context, SubContext, ContextItem
import osrf.ses, oils.utils.csedit, pylons.config, oils.utils.utils, oils.event
import oilsweb.lib.user
from gettext import gettext as _
import oils.org

class CoreContext(SubContext):
    # cache the authenticated user info
    def __init__(self):
        self.prefix = ContextItem() # web prefix
        self.media_prefix = ContextItem() # media prefix
        self.ac_prefix = ContextItem() # added content prefix
        self.skin = ContextItem() # web skin
        self.theme = ContextItem() # web theme
        self.authtoken = ContextItem(cgi_name='ses', session=True) # authtoken string
        self.user = ContextItem() # logged in user object
        self.workstation = ContextItem() # workstation object
        self.use_demo = ContextItem(cgi_name='demo') # use the demo login
        self.org_tree = ContextItem() # full org tree
        self.page = ContextItem() # the current page

        self.work_orgs = ContextItem()

        # place to store perm org sets for a given permission
        self.high_perm_orgs = ContextItem(default_value={})

        # place to store slim perm org trees
        self.perm_tree = ContextItem(default_value={})

    def postinit(self):
        self.prefix = pylons.config['oils_prefix']
        self.media_prefix = pylons.config['oils_media_prefix']
        self.ac_prefix = pylons.config['oils_added_content_prefix']
        self.skin = 'default' # XXX
        self.theme = 'default' # XXX
        usermgr = oilsweb.lib.user.User(self)
        usermgr.fetch_user()
        #self.work_orgs = usermgr.fetch_work_orgs()

Context.applySubContext('core', CoreContext)


class UtilContext(SubContext):
    ''' The UtilContext maintains a set of general use functions '''
    def __init__(self):
        import oilsweb.lib.bib
        self.scrub_isbn = ContextItem(default_value=oilsweb.lib.bib.scrub_isbn)
        self.get_org_type = ContextItem(default_value=oils.org.OrgUtil.get_org_type)
        self.get_min_org_depth = ContextItem(default_value=oils.org.OrgUtil.get_min_depth)

Context.applySubContext('util', UtilContext)


