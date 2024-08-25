import { NightwatchBrowser } from 'nightwatch';
import { navigateToEgUrl } from '../../utils';

module.exports = {
  before: (browser: NightwatchBrowser) => {
    browser.page.login().loginToWebClient(browser, 'br1breid', 'demo123');
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
    navigateToEgUrl('eg2/en-US/staff/acq/provider/4/details', browser);
    browser.click('link text', 'POs')
           .assert.textContains('.tab-content', 'Purchase Order ID');
    browser.click('link text', 'Invoices')
           .assert.textContains('.tab-content', 'Invoice Type');
    browser.click('link text', 'Provider')
           .assert.textContains('.tab-content', 'SAN');
  },
  'Warning displayed when moving to a different tab, but holdings tab has unsaved changes':
    (browser: NightwatchBrowser) => {
      navigateToEgUrl('eg2/en-US/staff/acq/provider/4/holdings', browser);
      browser.setValue('#holdings-tag', '981')
             .click('link text', 'Provider')
             .assert.textMatches('h4.modal-title', 'Unsaved Changes Warning');
  },
  'Provider search screen passes axe accessibility checks': (browser: NightwatchBrowser) => {
    navigateToEgUrl('eg2/en-US/staff/acq/provider', browser);
    browser.waitForElementVisible('h1');
    browser.axeInject().axeRun('main');
  },
  'Individual provider screen passes axe accessibility checks': (browser: NightwatchBrowser) => {
    navigateToEgUrl('eg2/en-US/staff/acq/provider/4/details', browser);
    browser.waitForElementVisible('h1');
    browser.axeInject().axeRun('main');
  }
};
