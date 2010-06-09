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
from oils.utils.idl import IDLParser
from osrf.ses import ClientSession
from oils.const import *
import re

ACTIONS = ['create', 'retrieve', 'batch_retrieve', 'update', 'delete', 'search']

class CSEditor(object):
    """
    Contains generated methods for accessing fieldmapper objects using the
    following syntax:
    
        <ret> = <instance>.<action>_<schema>_<table>(<args>)

      * <instance> = CSEditor class instance
      * <action>   = 
        * create 
          <args>   = object to create
          <ret>    = the numeric ID of the newly created object
        * retrieve 
          <args>   = numeric ID of the object to retrieve 
          <ret>    = object, instance of osrf.net_obj.NetworkObject
        * batch_retrieve
          <args>   = list of numeric ID's
          <ret>    = list of objects, instances of osrf.net_obj.NetworkObject
        * update
          <args>   = object to update
          <ret>    = 1 on success
        * delete
          <args>   = object to delete
          <ret>    = 1 on sucess
        * search
          <args>   = a cstore-compatible search dict.  e.g. {"id":1}.  
            See cstore docs for the full range of search options.
          <ret>    = a list of search results.  For standard searches, this
                   will be a list of objects.  idlist searches will return
                   a list of ID's.
      * <schema>   = the name of the schema that contains the table
      * <table>    = the name of the table

    Each generated object has accessor methods corresponding to the fieldmapper
    name attributes for a given field. The following example demonstrates how to
    instantiate the CSEditor and a given table object, and how to invoke an
    accessor method on that table object:

    >>> import oils.utils.csedit
    >>> import oils.utils.idl
    >>> import osrf.system
    >>> osrf.system.connect('/openils/conf/opensrf_core.xml', 'config.opensrf')
    >>> oils.utils.idl.oilsParseIDL()
    >>> oils.utils.csedit.oilsLoadCSEditor()
    >>> editor = oils.utils.csedit.CSEditor()
    >>> rec = editor.retrieve_biblio_record_entry(-1)
    >>> print rec.tcn_value()
    """

    def __init__(self, **args):
        ''' 
            Creates a new editor object.

            Support keyword arguments:
            authtoken - Authtoken string -- used to determine 
                the requestor if none is provided.
            requestor - existing user (au) object.  The requestor is 
                is the user performing the action.  This is important 
                for permission checks, logging, etc.
            connect - boolean.  If true, a connect call is sent to the opensrf
                service at session create time
            xact - boolean.  If true, a cstore transaction is created at 
                connect time.  xact implies connect.
        '''

        self.app = args.get('app', OILS_APP_CSTORE)
        self.authtoken = args.get('authtoken', args.get('auth'))
        self.requestor = args.get('requestor')
        self.connect = args.get('connect')
        self.xact = args.get('xact')
        self.__session = None

    def die_event(self):
        ''' Rolls back the existing transaction, disconnects our session, 
            and returns the last received event.
        '''
        pass

    def checkauth(self):
        ''' Checks the authtoken against open-ils.auth and uses the 
            retrieved user as the requestor
        '''
        pass


    # -------------------------------------------------------------------------
    # Creates a session if one does not already exist.  If necessary, connects
    # to the remote service and starts a transaction
    # -------------------------------------------------------------------------
    def session(self, ses=None):
        ''' Creates a session if one does not already exist.  If necessary, connects
            to the remote service and starts a transaction
        '''
        if not self.__session:
            self.__session = ClientSession(self.app)

        if self.connect or self.xact:
            self.log(log_debug,'connecting to ' + self.app)
            self.__session.connect() 

        if self.xact:
            self.log(log_info, "starting new db transaction")
            self.request(self.app + '.transaction.begin')

        return self.__session
   

    def log(self, func, string):
        ''' Logs string with some meta info '''

        s = "editor[";
        if self.xact: s += "1|"
        else: s += "0|"
        if self.requestor: s += str(self.requestor.id())
        else: s += "0"
        s += "]"
        func("%s %s" % (s, string))


    def rollback(self):
        ''' Rolls back the existing db transaction '''

        if self.__session and self.xact:
             self.log(log_info, "rolling back db transaction")
             self.request(self.app + '.transaction.rollback')
             self.disconnect()
             
    def commit(self):
        ''' Commits the existing db transaction and disconnects '''

        if self.__session and self.xact:
            self.log(log_info, "comitting db transaction")
            self.request(self.app + '.transaction.commit')
            self.disconnect()


    def disconnect(self):
        ''' Disconnects from the remote service '''
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
            method += '.atomic'

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
__editor_loaded = False
def oilsLoadCSEditor():
    global __editor_loaded
    if __editor_loaded:
        return
    __editor_loaded = True

    obj = IDLParser.get_parser().IDLObject

    for k, fm in obj.iteritems():
        for action in ACTIONS:

            fmname = fm.fieldmapper.replace('::', '_')
            type = fm.fieldmapper.replace('::', '.')
            name = "%s_%s" % (action, fmname)

            s = 'def %s(self, arg, **options):\n' % name
            s += '\treturn self.runMethod("%s", "%s", arg, dict(options))\n' % (action, type)
            s += 'setattr(CSEditor, "%s", %s)' % (name, name)

            exec(s)

