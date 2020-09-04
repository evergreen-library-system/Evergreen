#!/usr/bin/env python
"""OpenSRF client example in Python"""
import osrf.system
import osrf.ses

def osrf_substring(session, text, sub):
    """substring: Accepts a string and a number as input, returns a string"""
    request = session.request('opensrf.simple-text.substring', text, sub)

    # Retrieve the response from the method
    # The timeout parameter is optional
    response = request.recv(timeout=2)

    request.cleanup()
    # The results are accessible via content()
    return response.content()

def osrf_split(session, text, delim):
    """split: Accepts two strings as input, returns an array of strings"""
    request = session.request('opensrf.simple-text.split', text, delim)
    response = request.recv()
    request.cleanup()
    return response.content()

def osrf_statistics(session, strings):
    """statistics: Accepts an array of strings as input, returns a hash"""
    request = session.request('opensrf.simple-text.statistics', strings)
    response = request.recv()
    request.cleanup()
    return response.content()


if __name__ == "__main__":
    file = '/openils/conf/opensrf_core.xml'

    # Pull connection settings from <config><opensrf> section of opensrf_core.xml
    osrf.system.System.connect(config_file=file, config_context='config.opensrf')

    # Set up a connection to the opensrf.settings service
    session = osrf.ses.ClientSession('opensrf.simple-text')

    result = osrf_substring(session, "foobar", 3)
    print(result)
    print

    result = osrf_split(session, "This is a test", " ")
    print("Received %d elements: [" % len(result)),
    print(', '.join(result)), ']'

    many_strings = (
        "First I think I'll have breakfast",
        "Then I think that lunch would be nice",
        "And then seventy desserts to finish off the day"
    )
    result = osrf_statistics(session, many_strings)
    print("Length: %d" % result["length"])
    print("Word count: %d" % result["word_count"])

    # Cleanup connection resources
    session.cleanup()
