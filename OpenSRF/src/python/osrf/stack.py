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

from osrf.json import *
from osrf.log import *
from osrf.ex import *
from osrf.ses import osrfFindSession, osrfClientSession, osrfServerSession
from osrf.const import *
from time import time


def osrfPushStack(netMessage):
   ses = osrfFindSession(netMessage.thread)

   if not ses:
      # This is an incoming request from a client, create a new server session
      pass

   ses.setRemoteId(netMessage.sender)

   oMessages = osrfJSONToObject(netMessage.body)

   osrfLogInternal("osrfPushStack(): received %d messages" % len(oMessages))

   # Pass each bundled opensrf message to the message handler
   t = time()
   for m in oMessages:
      osrfHandleMessage(ses, m)
   t = time() - t

   if isinstance(ses, osrfServerSession):
      osrfLogInfo("Message processing duration %f" % t)

def osrfHandleMessage(session, message):

   osrfLogInternal("osrfHandleMessage(): processing message of type %s" % message.type())

   if isinstance(session, osrfClientSession):
      
      if message.type() == OSRF_MESSAGE_TYPE_RESULT:
         session.pushResponseQueue(message)
         return

      if message.type() == OSRF_MESSAGE_TYPE_STATUS:

         statusCode = int(message.payload().statusCode())
         statusText = message.payload().status()
         osrfLogInternal("osrfHandleMessage(): processing STATUS,  statusCode =  %d" % statusCode)

         if statusCode == OSRF_STATUS_COMPLETE:
            # The server has informed us that this request is complete
            req = session.findRequest(message.threadTrace())
            if req: 
               osrfLogInternal("marking request as complete: %d" % req.id)
               req.setComplete()
            return

         if statusCode == OSRF_STATUS_OK:
            # We have connected successfully
            osrfLogDebug("Successfully connected to " + session.service)
            session.state = OSRF_APP_SESSION_CONNECTED
            return

         if statusCode == OSRF_STATUS_CONTINUE:
            # server is telling us to reset our wait timeout and keep waiting for a response
            session.resetRequestTimeout(message.threadTrace())
            return;

         if statusCode == OSRF_STATUS_TIMEOUT:
            osrfLogDebug("The server did not receive a request from us in time...")
            session.state = OSRF_APP_SESSION_DISCONNECTED
            return

         if statusCode == OSRF_STATUS_NOTFOUND:
            osrfLogErr("Requested method was not found on the server: %s" % statusText)
            session.state = OSRF_APP_SESSION_DISCONNECTED
            raise osrfServiceException(statusText)

         raise osrfProtocolException("Unknown message status: %d" % statusCode)
      
         
   
   
