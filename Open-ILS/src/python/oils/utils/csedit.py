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
from oils.utils.utils import replace
from oils.utils.idl import oilsGetIDLParser
from osrf.ses import osrfClientSession, osrfAtomicRequest
from oils.const import *
import re

ACTIONS = ['create', 'retrieve', 'update', 'delete', 'search']

class CSEditor(object):

   def __init__(self, **args):

      self.app = args.get('app', OILS_APP_CSTORE)
      self.authtoken = args.get('authtoken', args.get('auth'))
      self.requestor = args.get('requestor')
      self.connect = args.get('connect')
      self.xact = args.get('xact')
      self.substream = False;
      self.__session = None

   # -------------------------------------------------------------------------
   # rolls back the existing transaction and returns the last event
   # -------------------------------------------------------------------------
   def die_event(self):
      self.rollback()
      return self.event

   # -------------------------------------------------------------------------
   # Verifies the session is valid sets the 'requestor' to the user retrieved
   # by the session lookup
   # -------------------------------------------------------------------------
   def checkauth(self):
      usr = osrfAtomicRequest( OILS_APP_AUTH, 'open-ils.auth.session.retrieve', self.authtoken ) 
      if oilsIsEvent(usr):
         self.event = usr
         return False
      self.requestor = usr
      return True


   # -------------------------------------------------------------------------
   # Creates a session if one does not already exist.  If necessary, connects
   # to the remote service and starts a transaction
   # -------------------------------------------------------------------------
   def session(self, ses=None):
      if not self.__session:
         self.__session = osrfClientSession(self.app)

         if self.connect or self.xact:
            self.log(osrfLogDebug,'connecting to ' + self.app)
            self.__session.connect() 

         if self.xact:
            self.log(osrfLogInfo, "starting new db transaction")
            self.request(self.app + '.transaction.begin')

      return self.__session
   

   # -------------------------------------------------------------------------
   # Logs the given string with some meta info
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
         self.log(osrfLogInfo, "rolling back db transaction")
         self.request(self.app + '.transaction.rollback')
         self.disconnect()
         
   # -------------------------------------------------------------------------
   # Commits the existing db transaction
   # -------------------------------------------------------------------------
   def commit(self):
      if self.__session and self.xact:
         self.log(osrfLogInfo, "comitting db transaction")
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

      if self.xact and self.session().state != OSRF_APP_SESSION_CONNECTED:
         self.log(osrfLogErr, "csedit lost it's connection!")

      self.log(osrfLogInfo, "request %s %s" % (method, self.__args_to_str(params)))

      val = None
      try:
         req =  self.session().request2(method, params)

         # -------------------------------------------------------------------------
         # substream requests gather the requests as they come in
         # -------------------------------------------------------------------------
         if self.substream:
            val = []
            while True:
               resp = req.recv()
               if not resp: 
                  break
               val.append(resp.content())
         else:
            val = req.recv().content()

      except Exception, e:
         self.log(osrfLogErr, "request error: %s" % str(e))
         raise e

      return val


   # -------------------------------------------------------------------------
   # turns an array of parms into a readable argument string for logging
   # -------------------------------------------------------------------------
   def __args_to_str(self, arg):
      s = ''
      for i in range(len(arg)):
         obj = arg[i]
         if i > 0: s += ', '
         if isinstance(obj, osrfNetworkObject):
            if obj.id() != None:
               s += str(obj.id())
            else: s += '<new object: %s>' % obj.__class__.__name__
         else: s += osrfObjectToJSON(obj)
      return s


   # -------------------------------------------------------------------------
   # Returns true if our requestor is allowed to perform the request action
   # 'org' defaults to the requestors ws_ou
   # -------------------------------------------------------------------------
   def allowed(self, perm, org=None):
      pass


   def runMethod(self, action, type, arg, options={}):

      # make sure we're in a transaction if performing any writes
      if action in ['create', 'update', 'delete'] and not self.xact:
         raise oilsCSEditException('attempt to update DB outside of a transaction') 

      # clear the previous event
      self.event = None

      # construct the method name
      method = "%s.direct.%s.%s" % (self.app, type, action)

      # do we only want a list of IDs?
      if options.get('idlist'):
         method = replace(method, 'search', 'id_list')
         del options['idlist']
      
      # are we streaming or atomic?
      if action == 'search':
         if options.get('substream'):
            self.substream = True
            del options['substream']
         else:
            method = replace(method, '$', '.atomic')

      params = [arg];
      if len(options.keys()):
         params.append(options)

      val = self.request( method, params )

      return val



# -------------------------------------------------------------------------
# Creates a class method for each action on each type of fieldmapper object
# -------------------------------------------------------------------------
def oilsLoadCSEditor():
   obj = oilsGetIDLParser().IDLObject

   for k, fm in obj.iteritems():
      for action in ACTIONS:

         fmname = replace(fm['fieldmapper'], '::', '_')
         type = replace(fm['fieldmapper'], '::', '.')
         name = "%s_%s" % (action, fmname)

         str = 'def %s(self, arg, **options):\n' % name
         str += '\treturn self.runMethod("%s", "%s", arg, dict(options))\n' % (action, type)
         str += 'setattr(CSEditor, "%s", %s)' % (name, name)

         exec(str)

