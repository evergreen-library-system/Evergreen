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
from osrf.conf import osrfConfigValue
from osrf.net import osrfNetworkMessage, osrfGetNetworkHandle
from osrf.log import *
from osrf.const import *
import random, sys, os, time


# -----------------------------------------------------------------------
# Go ahead and register the common network objects
# -----------------------------------------------------------------------
osrfNetworkRegisterHint('osrfMessage', ['threadTrace', 'type', 'payload'], 'hash')
osrfNetworkRegisterHint('osrfMethod', ['method', 'params'], 'hash')
osrfNetworkRegisterHint('osrfResult', ['status', 'statusCode', 'content'], 'hash')
osrfNetworkRegisterHint('osrfConnectStatus', ['status','statusCode'], 'hash')
osrfNetworkRegisterHint('osrfMethodException', ['status', 'statusCode'], 'hash')


class osrfSession(object):
	"""Abstract session superclass."""

	def __init__(self):
		# by default, we're connected to no one
		self.state = OSRF_APP_SESSION_DISCONNECTED


	def wait(self, timeout=120):
		"""Wait up to <timeout> seconds for data to arrive on the network"""
		osrfLogInternal("osrfSession.wait(%d)" % timeout)
		handle = osrfGetNetworkHandle()
		handle.recv(timeout)

	def send(self, omessage):
		"""Sends an OpenSRF message"""
		netMessage = osrfNetworkMessage(
			to		= self.remoteId,
			body	= osrfObjectToJSON([omessage]),
			thread = self.thread )

		handle = osrfGetNetworkHandle()
		handle.send(netMessage)

	def cleanup(self):
		"""Removes the session from the global session cache."""
		del osrfClientSession.sessionCache[self.thread]

class osrfClientSession(osrfSession):
	"""Client session object.  Use this to make server requests."""

	def __init__(self, service):
		
		# call superclass constructor
		osrfSession.__init__(self)

		# the remote service we want to make requests of
		self.service = service

		# find the remote service handle <router>@<domain>/<service>
		domain = osrfConfigValue('domains.domain', 0)
		router = osrfConfigValue('router_name')
		self.remoteId = "%s@%s/%s" % (router, domain, service)
		self.origRemoteId = self.remoteId

		# generate a random message thread
		self.thread = "%s%s%s" % (os.getpid(), str(random.randint(100,100000)), str(time.time()))

		# how many requests this session has taken part in
		self.nextId = 0 

		# cache of request objects 
		self.requests = {}

		# cache this session in the global session cache
		osrfClientSession.sessionCache[self.thread] = self

	def resetRequestTimeout(self, rid):
		req = self.findRequest(rid)
		if req:
			req.resetTimeout = True
			

	def request2(self, method, arr):
		"""Creates a new request and sends the request to the server using a python array as the params."""
		return self.__request(method, arr)

	def request(self, method, *args):
		"""Creates a new request and sends the request to the server using a variable argument list as params"""
		arr = list(args)
		return self.__request(method, arr)

	def __request(self, method, arr):
		"""Builds the request object and sends it."""
		if self.state != OSRF_APP_SESSION_CONNECTED:
			self.resetRemoteId()

		osrfLogDebug("Sending request %s -> %s " % (self.service, method))
		req = osrfRequest(self, self.nextId, method, arr)
		self.requests[str(self.nextId)] = req
		self.nextId += 1
		req.send()
		return req


	def connect(self, timeout=10):
		"""Connects to a remote service"""

		if self.state == OSRF_APP_SESSION_CONNECTED:
			return True
		self.state == OSRF_APP_SESSION_CONNECTING

		# construct and send a CONNECT message
		self.send(
			osrfNetworkObject.osrfMessage( 
				{	'threadTrace' : 0,
					'type' : OSRF_MESSAGE_TYPE_CONNECT
				} 
			)
		)

		while timeout >= 0 and not self.state == OSRF_APP_SESSION_CONNECTED:
			start = time.time()
			self.wait(timeout)
			timeout -= time.time() - start
		
		if self.state != OSRF_APP_SESSION_CONNECTED:
			raise osrfServiceException("Unable to connect to " + self.service)
		
		return True

	def disconnect(self):
		"""Disconnects from a remote service"""

		if self.state == OSRF_APP_SESSION_DISCONNECTED:
			return True

		self.send(
			osrfNetworkObject.osrfMessage( 
				{	'threadTrace' : 0,
					'type' : OSRF_MESSAGE_TYPE_DISCONNECT
				} 
			)
		)

		self.state = OSRF_APP_SESSION_DISCONNECTED


		
	
	def setRemoteId(self, remoteid):
		self.remoteId = remoteid
		osrfLogInternal("Setting request remote ID to %s" % self.remoteId)

	def resetRemoteId(self):
		"""Recovers the original remote id"""
		self.remoteId = self.origRemoteId
		osrfLogInternal("Resetting remote ID to %s" % self.remoteId)

	def pushResponseQueue(self, message):
		"""Pushes the message payload onto the response queue 
			for the request associated with the message's ID."""
		osrfLogDebug("pushing %s" % message.payload())
		try:
			self.findRequest(message.threadTrace()).pushResponse(message.payload())
		except Exception, e: 
			osrfLogWarn("pushing respond to non-existent request %s : %s" % (message.threadTrace(), e))

	def findRequest(self, rid):
		"""Returns the original request matching this message's threadTrace."""
		try:
			return self.requests[str(rid)]
		except KeyError:
			osrfLogDebug('findRequest(): non-existent request %s' % str(rid))
			return None



osrfSession.sessionCache = {}
def osrfFindSession(thread):
	"""Finds a session in the global cache."""
	try:
		return osrfClientSession.sessionCache[thread]
	except: return None

class osrfRequest(object):
	"""Represents a single OpenSRF request.
		A request is made and any resulting respones are 
		collected for the client."""

	def __init__(self, session, id, method=None, params=[]):

		self.session = session # my session handle
		self.id		= id # my unique request ID
		self.method = method # method name
		self.params = params # my method params
		self.queue	= [] # response queue
		self.resetTimeout = False # resets the recv timeout?
		self.complete = False # has the server told us this request is done?
		self.sendTime = 0 # local time the request was put on the wire
		self.completeTime =  0 # time the server told us the request was completed
		self.firstResponseTime = 0 # time it took for our first reponse to be received

	def send(self):
		"""Sends a request message"""

		# construct the method object message with params and method name
		method = osrfNetworkObject.osrfMethod( {
			'method' : self.method,
			'params' : self.params
		} )

		# construct the osrf message with our method message embedded
		message = osrfNetworkObject.osrfMessage( {
			'threadTrace' : self.id,
			'type' : OSRF_MESSAGE_TYPE_REQUEST,
			'payload' : method
		} )

		self.sendTime = time.time()
		self.session.send(message)

	def recv(self, timeout=120):
		"""Waits up to <timeout> seconds for a response to this request.
		
			If a message is received in time, the response message is returned.
			Returns None otherwise."""

		self.session.wait(0)

		origTimeout = timeout
		while not self.complete and timeout >= 0 and len(self.queue) == 0:
			s = time.time()
			self.session.wait(timeout)
			timeout -= time.time() - s
			if self.resetTimeout:
				self.resetTimeout = False
				timeout = origTimeout

		now = time.time()

		# -----------------------------------------------------------------
		# log some statistics 
		if len(self.queue) > 0:
			if not self.firstResponseTime:
				self.firstResponseTime = now
				osrfLogDebug("time elapsed before first response: %f" \
					% (self.firstResponseTime - self.sendTime))

		if self.complete:
			if not self.completeTime:
				self.completeTime = now
				osrfLogDebug("time elapsed before complete: %f" \
					% (self.completeTime - self.sendTime))
		# -----------------------------------------------------------------


		if len(self.queue) > 0:
			# we have a reponse, return it
			return self.queue.pop(0)

		return None

	def pushResponse(self, content):
		"""Pushes a method response onto this requests response queue."""
		self.queue.append(content)

	def cleanup(self):
		"""Cleans up request data from the cache. 

			Do this when you are done with a request to prevent "leaked" cache memory."""
		del self.session.requests[str(self.id)]

	def setComplete(self):
		"""Sets me as complete.  This means the server has sent a 'request complete' message"""
		self.complete = True


class osrfServerSession(osrfSession):
	"""Implements a server-side session"""
	pass


def osrfAtomicRequest(service, method, *args):
	ses = osrfClientSession(service)
	req = ses.request2('open-ils.cstore.direct.actor.user.retrieve', list(args)) # grab user with ID 1
	resp = req.recv()
	data = resp.content()
	req.cleanup()
	ses.cleanup()
	return data



