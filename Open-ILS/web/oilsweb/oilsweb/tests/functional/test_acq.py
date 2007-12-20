from oilsweb.tests import *

class TestAcqController(TestController):

    def test_index(self):
        response = self.app.get(url_for(controller='acq'))
        # Test response...
