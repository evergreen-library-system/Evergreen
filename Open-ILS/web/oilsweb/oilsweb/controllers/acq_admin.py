import logging

from oilsweb.lib.base import *
import pylons, os
import oilsweb.lib.context
import oilsweb.lib.util
import oilsweb.lib.acq.search
from oilsweb.lib.context import Context, SubContext, ContextItem

import oils.utils.csedit
import osrf.log
import osrf.system
from oils.utils.idl import oilsParseIDL
from oils.utils.csedit import oilsLoadCSEditor

def oilsConnect(config, configContext):
	"""Connects to the opensrf network,  parses the IDL file, and loads the CSEditor"""
	osrf.system.connect(config, configContext)
	oilsParseIDL()
	oilsLoadCSEditor()

log = logging.getLogger(__name__)

class AcqAdminController(BaseController):

    def index(self):
        """
        List the acquisition objects that we're allowed to administer
        """

        import pprint

        # Parse IDL and render as links for viewing the objects, perhaps?
        c.oils = oilsweb.lib.context.Context.init(request)
        c.request = request
        oilsConnect('/openils/conf/opensrf_core.xml', 'config.opensrf')
        c.idl = oils.utils.idl.oilsGetIDLParser()
        c.csedit = oils.utils.csedit.CSEditor()
        c.registry = osrf.net_obj.OBJECT_REGISTRY
        return render('oils/%s/acq/admin.html' % c.oils.core.skin)

