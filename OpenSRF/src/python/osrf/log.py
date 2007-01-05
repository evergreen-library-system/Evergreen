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

from syslog import *
import traceback, sys, os, re
from osrf.const import *

loglevel = 4

def osrfInitLog(level, facility=None, file=None):
	"""Initialize the logging subsystem."""
	global loglevel
	if facility: osrfInitSyslog(facility, level)
	loglevel = level
	syslog(LOG_DEBUG, "syslog initialized")


# -----------------------------------------------------------------------
# Define wrapper functions for the log levels
# -----------------------------------------------------------------------
def osrfLogInternal(s): __osrfLog(OSRF_LOG_INTERNAL,s)
def osrfLogDebug(s): __osrfLog(OSRF_LOG_DEBUG,s)
def osrfLogInfo(s): __osrfLog(OSRF_LOG_INFO,s)
def osrfLogWarn(s): __osrfLog(OSRF_LOG_WARN,s)
def osrfLogErr(s): __osrfLog(OSRF_LOG_ERR,s)


frgx = re.compile('/.*/')

def __osrfLog(level, msg):
	"""Builds the log message and passes the message off to the logger."""
	global loglevel
	if int(level) > int(loglevel): return

	# find the caller info for logging the file and line number
	tb = traceback.extract_stack(limit=3)
	tb = tb[0]
	lvl = 'DEBG'
	slvl = LOG_DEBUG

	if level == OSRF_LOG_INTERNAL: lvl = 'INT '; slvl=LOG_DEBUG
	if level == OSRF_LOG_INFO: lvl = 'INFO'; slvl=LOG_INFO
	if level == OSRF_LOG_WARN: lvl = 'WARN'; slvl=LOG_WARNING
	if level == OSRF_LOG_ERR:  lvl = 'ERR '; slvl=LOG_ERR

	file = frgx.sub('',tb[0])
	msg = '[%s:%d:%s:%s] %s' % (lvl, os.getpid(), file, tb[1], msg)
	syslog(slvl, msg)

	if level == OSRF_LOG_ERR:
		sys.stderr.write(msg + '\n')


def osrfInitSyslog(facility, level):
	"""Connect to syslog and set the logmask based on the level provided."""

	level = int(level)

	if facility == 'local0': facility = LOG_LOCAL0
	if facility == 'local1': facility = LOG_LOCAL1
	if facility == 'local2': facility = LOG_LOCAL2
	if facility == 'local3': facility = LOG_LOCAL3
	if facility == 'local4': facility = LOG_LOCAL4
	if facility == 'local5': facility = LOG_LOCAL5
	if facility == 'local6': facility = LOG_LOCAL6
	# XXX add other facility maps if necessary
	openlog(sys.argv[0], 0, facility)

	# this is redundant...
	mask = LOG_UPTO(LOG_ERR)
	if level >= 1: mask |= LOG_MASK(LOG_WARNING)
	if level >= 2: mask |= LOG_MASK(LOG_NOTICE)
	if level >= 3: mask |= LOG_MASK(LOG_INFO)
	if level >= 4: mask |= LOG_MASK(LOG_DEBUG)
	setlogmask(mask)

