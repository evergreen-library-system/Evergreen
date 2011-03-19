"""
Grab-bag of general utility functions
"""

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

import hashlib
import osrf.log, osrf.ses

def md5sum(string):
    """
    Return an MD5 message digest for a given input string
    """

    md5 = hashlib.md5()
    md5.update(string)
    return md5.hexdigest()

def unique(arr):
    """
    Unique-ify a list.  only works if list items are hashable
    """

    o = {}
    for x in arr:
        o[x] = 1
    return o.keys()

def is_db_true(data):
    """
    Returns PostgreSQL's definition of "truth" for the supplied data, roughly.
    """

    if not data or data == 'f' or str(data) == '0':
        return False
    return True

def login(username, password, login_type=None, workstation=None):
    """
    Login to the server and get back an authentication token

    @param username: user name
    @param password: password
    @param login_type: one of 'opac', 'temp', or 'staff' (default: 'staff')
    @param workstation: name of the workstation to associate with this login

    @rtype: string
    @return: a string containing an authentication token to pass as
        a required parameter of many OpenSRF service calls
    """

    osrf.log.log_info("attempting login with user " + username)

    seed = osrf.ses.ClientSession.atomic_request(
        'open-ils.auth', 
        'open-ils.auth.authenticate.init', username)

    # generate the hashed password
    password = md5sum(seed + md5sum(password))

    return osrf.ses.ClientSession.atomic_request(
        'open-ils.auth',
        'open-ils.auth.authenticate.complete',
        {   'workstation' : workstation,
            'username' : username,
            'password' : password,
            'type' : login_type
        }
    )

