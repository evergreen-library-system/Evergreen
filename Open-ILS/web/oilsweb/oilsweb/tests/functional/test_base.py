from oilsweb.tests import *

class TestBaseController(TestController):

    def test_index(self):
        response = self.app.get(url_for(controller='base'))
        # Test response...
