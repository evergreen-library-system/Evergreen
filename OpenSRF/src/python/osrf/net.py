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


from pyxmpp.jabber.client import JabberClient
from pyxmpp.message import Message
from pyxmpp.jid import JID
from socket import gethostname
from osrf.log import *
import os, time
import logging

# - log jabber activity (for future reference)
#logger=logging.getLogger()
#logger.addHandler(logging.StreamHandler())
#logger.addHandler(logging.FileHandler('j.log'))
#logger.setLevel(logging.DEBUG)

__network = None
def osrfSetNetworkHandle(handle):
	"""Sets the global network connection handle."""
	global __network
	__network = handle

def osrfGetNetworkHandle():
	"""Returns the global network connection handle."""
	global __network
	return __network


class osrfNetworkMessage(object):
	"""Network message

	attributes:

	sender - message sender
	to - message recipient
	body - the body of the message
	thread - the message thread
	"""

	def __init__(self, message=None, **args):
		if message:
			self.body = message.get_body()
			self.thread = message.get_thread()
			self.to = message.get_to()
			if message.xmlnode.hasProp('router_from') and message.xmlnode.prop('router_from') != '':
				self.sender = message.xmlnode.prop('router_from')
			else: self.sender = message.get_from().as_utf8()
		else:
			if args.has_key('sender'): self.sender = args['sender']
			if args.has_key('to'): self.to = args['to']
			if args.has_key('body'): self.body = args['body']
			if args.has_key('thread'): self.thread = args['thread']


class osrfNetwork(JabberClient):
	def __init__(self, **args):
		self.isconnected = False

		# Create a unique jabber resource
		resource = 'osrf_client'
		if args.has_key('resource'):
			resource = args['resource']
		resource += '_' + gethostname()+':'+ str(os.getpid()) 
		self.jid = JID(args['username'], args['host'], resource)

		osrfLogDebug("initializing network with JID %s and host=%s, port=%s, username=%s" % 
			(self.jid.as_utf8(), args['host'], args['port'], args['username']))

		#initialize the superclass
		JabberClient.__init__(self, self.jid, args['password'], args['host'])
		self.queue = []

	def connect(self):
		JabberClient.connect(self)
		while not self.isconnected:
			stream = self.get_stream()
			act = stream.loop_iter(10)
			if not act: self.idle()

	def setRecvCallback(self, func):
		"""The callback provided is called when a message is received.
		
			The only argument to the function is the received message. """
		self.recvCallback = func

	def session_started(self):
		osrfLogInfo("Successfully connected to the opensrf network")
		self.authenticated()
		self.stream.set_message_handler("normal",self.message_received)
		self.isconnected = True

	def send(self, message):
		"""Sends the provided network message."""
		osrfLogInternal("jabber sending to %s: %s" % (message.to, message.body))
		msg = Message(None, None, message.to, None, None, None, message.body, message.thread)
		self.stream.send(msg)
	
	def message_received(self, stanza):
		"""Handler for received messages."""
		osrfLogInternal("jabber received a message of type %s" % stanza.get_type())
		if stanza.get_type()=="headline":
			return True
		# check for errors
		osrfLogInternal("jabber received message from %s : %s" 
			% (stanza.get_from().as_utf8(), stanza.get_body()))
		self.queue.append(osrfNetworkMessage(stanza))
		return True

	def recv(self, timeout=120):
		"""Attempts to receive a message from the network.

		timeout - max number of seconds to wait for a message.  
		If no message is received in 'timeout' seconds, None is returned. """

		msg = None
		if len(self.queue) == 0:
			while timeout >= 0 and len(self.queue) == 0:
				starttime = time.time()
				osrfLogInternal("going into stream loop at " + str(starttime))
				act = self.get_stream().loop_iter(timeout)
				endtime = time.time() - starttime
				timeout -= endtime
				osrfLogInternal("exiting stream loop after %s seconds" % str(endtime))
				osrfLogInternal("act = %s : queue length = %d" % (act, len(self.queue)) )
				if not act: self.idle()

		# if we've acquired a message, handle it
		if len(self.queue) > 0:
			self.recvCallback(self.queue.pop(0))
		return None



