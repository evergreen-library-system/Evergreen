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

import re, md5
from osrf.ses import AtomicRequest
from osrf.log import *



# -----------------------------------------------------------------------
# Grab-bag of general utility functions
# -----------------------------------------------------------------------

def isEvent(evt):
    return (evt and isinstance(evt, dict) and evt.get('ilsevent') != None)

def eventCode(evt):
    if isEvent(evt):
        return evt['ilsevent']
    return None

def eventText(evt):
    if isEvent(evt):
        return evt['textcode']
    return None

      
def md5sum(str):
    m = md5.new()
    m.update(str)
    return m.hexdigest()

def unique(arr):
    ''' Unique-ify a list.  only works if list items are hashable '''
    o = {}
    for x in arr:
        o[x] = 1
    return o.keys()

def is_db_true(data):
    ''' Returns true if the data provided matches what the database considers a true value '''
    if not data or data == 'f' or str(data) == '0':
        return False
    return True


def login(username, password, type=None, workstation=None):
    ''' Login to the server and get back an authtoken'''

    log_info("attempting login with user " + username)

    seed = AtomicRequest(
        'open-ils.auth', 
        'open-ils.auth.authenticate.init', username)

    # generate the hashed password
    password = md5sum(seed + md5sum(password))

    return AtomicRequest(
        'open-ils.auth',
        'open-ils.auth.authenticate.complete',
        {   'workstation' : workstation,
            'username' : username,
            'password' : password,
            'type' : type
        }
    )

