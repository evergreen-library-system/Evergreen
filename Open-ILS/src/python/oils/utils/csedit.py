# -----------------------------------------------------------------------
# Copyright (C) 2007  Georgia Public Library Service
# Bill Erickson <billserickson@gmail.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# -----------------------------------------------------------------------

from osrf.log import *
from osrf.json import *
from oils.utils.idl import oilsGetIDLParser
from osrf.ses import ClientSession
from oils.const import *
import re

ACTIONS = ['create', 'retrieve', 'batch_retrieve', 'update', 'delete', 'search']

class CSEditor(object):
    def __init__(self, **args):

        self.app = args.get('app', OILS_APP_CSTORE)
        self.authtoken = args.get('authtoken', args.get('auth'))
        self.requestor = args.get('requestor')
        self.connect = args.get('connect')
        self.xact = args.get('xact')
        self.__session = None

    def die_event(self):
        pass
    def checkauth(self):
        pass


    # -------------------------------------------------------------------------
    # Creates a session if one does not already exist.  If necessary, connects
    # to the remote service and starts a transaction
    # -------------------------------------------------------------------------
    def session(self, ses=None):
        if not self.__session:
            self.__session = ClientSession(self.app)

        if self.connect or self.xact:
            self.log(log_debug,'connecting to ' + self.app)
            self.__session.connect() 

        if self.xact:
            self.log(log_info, "starting new db transaction")
            self.request(self.app + '.transaction.begin')

        return self.__session
   

    # -------------------------------------------------------------------------
    # Logs string with some meta info
    # -------------------------------------------------------------------------
    def log(self, func, string):
        s = "editor[";
        if self.xact: s += "1|"
        else: s += "0|"
        if self.requestor: s += str(self.requestor.id())
        else: s += "0"
        s += "]"
        func("%s %s" % (s, string))


    # -------------------------------------------------------------------------
    # Rolls back the existing db transaction
    # -------------------------------------------------------------------------
    def rollback(self):
        if self.__session and self.xact:
             self.log(log_info, "rolling back db transaction")
             self.request(self.app + '.transaction.rollback')
             self.disconnect()
             
    # -------------------------------------------------------------------------
    # Commits the existing db transaction
    # -------------------------------------------------------------------------
    def commit(self):
        if self.__session and self.xact:
            self.log(log_info, "comitting db transaction")
            self.request(self.app + '.transaction.commit')
            self.disconnect()


    # -------------------------------------------------------------------------
    # Disconnects from the remote service
    # -------------------------------------------------------------------------
    def disconnect(self):
        if self.__session:
            self.__session.disconnect()
            self.__session = None


    # -------------------------------------------------------------------------
    # Sends a request
    # -------------------------------------------------------------------------
    def request(self, method, params=[]):

        # XXX improve param logging here

        self.log(log_info, "request %s %s" % (method, unicode(params)))

        if self.xact and self.session().state != OSRF_APP_SESSION_CONNECTED:
            self.log(log_error, "csedit lost its connection!")

        val = None

        try:
            req = self.session().request2(method, params)
            resp = req.recv()
            val = resp.content()

        except Exception, e:
            self.log(log_error, "request error: %s" % unicode(e))
            raise e

        return val


    # -------------------------------------------------------------------------
    # Returns true if our requestor is allowed to perform the request action
    # 'org' defaults to the requestors ws_ou
    # -------------------------------------------------------------------------
    def allowed(self, perm, org=None):
        pass # XXX


    def runMethod(self, action, type, arg, options={}):

        method = "%s.direct.%s.%s" % (self.app, type, action)

        if options.get('idlist'):
            method = method.replace('search', 'id_list')
            del options['idlist']

        if action == 'search':
            method = method.replace('$', '.atomic')

        if action == 'batch_retrieve':
            method = method.replace('batch_retrieve', 'search')
            method += '.atomic'
            arg = {'id' : arg}

        params = [arg];
        if len(options.keys()):
            params.append(options)

        val = self.request( method, params )

        return val

    def rawSearch(self, args):
        method = "%s.json_query.atomic" % self.app
        self.log(log_debug, "rawSearch args: %s" % unicode(args))
        return self.request(method, [args])

    def rawSearch2(self, hint, fields, where, from_=None):
        if not from_:   
            from_ = {'%s' % hint : {}}

        args = {
            'select' : { '%s' % hint : fields },
            'from' : from_,
            'where' : { "+%s" % hint : where }
        }
        return self.rawSearch(args)


    def fieldSearch(self, hint, fields, where):
        return self.rawSearch2(hint, fields, where)



# -------------------------------------------------------------------------
# Creates a class method for each action on each type of fieldmapper object
# -------------------------------------------------------------------------
def oilsLoadCSEditor():
    obj = oilsGetIDLParser().IDLObject

    for k, fm in obj.iteritems():
        for action in ACTIONS:

            fmname = fm['fieldmapper'].replace('::', '_')
            type = fm['fieldmapper'].replace('::', '.')
            name = "%s_%s" % (action, fmname)

            s = 'def %s(self, arg, **options):\n' % name
            s += '\treturn self.runMethod("%s", "%s", arg, dict(options))\n' % (action, type)
            s += 'setattr(CSEditor, "%s", %s)' % (name, name)

            exec(s)

