import { NightwatchBrowser } from 'nightwatch';
import { navigateToEgUrl } from '../../utils';

module.exports = {
  before: (browser: NightwatchBrowser) => {
    browser.page.login().loginToWebClient(browser, 'br1breid', 'barbarar1234');
  },

  after: (browser: NightwatchBrowser) => {
    browser.end();
  },

  'Can navigate to provider screen': (browser: NightwatchBrowser) => {
    browser.page.navbar().click('@acqMenu')
                         .click('a[href="/eg2/en-US/staff/acq/provider"]')
                         .assert.textContains('div.lead.alert', 'Providers');
  },
  'Can navigate via tabs': (browser: NightwatchBrowser) => {
    const tabIds = ['purchase_orders', 'invoices', 'details'];
    navigateToEgUrl('eg2/en-US/staff/acq/provider/4/details', browser);
    for (const tabId of tabIds) {
      const selector = '#' + tabId;
      browser.click(selector)
             .waitForElementVisible(selector + '-panel')
             .assert.hasClass(selector, 'active')
             .assert.attributeEquals(selector, 'aria-selected', 'true');
    }
  },
  'Warning displayed when moving to a different tab, but holdings tab has unsaved changes':
    (browser: NightwatchBrowser) => {
      navigateToEgUrl('eg2/en-US/staff/acq/provider/4/holdings', browser);
      browser.setValue('#holdings-tag', '981')
             .click('#details')
             .assert.textMatches('h4.modal-title', 'Unsaved Changes Warning');
  }
};
