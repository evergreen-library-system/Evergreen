import { NightwatchBrowser } from 'nightwatch';
import {randomString} from '../../../utils';

module.exports = {
  before: (browser: NightwatchBrowser) => {
    browser.page.login().loginToWebClient(browser, 'br1csmith', 'cathys1234');
  },

  after: (browser: NightwatchBrowser) => {
    browser.end();
  },

  'Can create new carousel': (browser: NightwatchBrowser) => {
    const carouselName = randomString();
    browser.navigateTo('eg2/en-US/staff/admin/local/container/carousel')
           .click('xpath', '//button[contains(text(),"New Carousels")]')
           // click the owner org-unit select to show the options
           .click('xpath', '//input[contains(@id, "owner")]')
           // then click the option we want from the dropdown
           .click('xpath', '//button[contains(./span/text(), "BR1")]')
           .setValue('xpath', '//input[contains(@id, "name")]', carouselName);

    // Click the Carousel Type combobox to open the dropdown
    browser.element.findByLabelText('Carousel Type').click();
    browser.click('xpath', '//button[@class = "dropdown-item" and contains(./span/text(), "Top Circulated Items")]')
           .setValue('xpath', '//input[contains(@id, "max_items")]', '25')
           .click('xpath', '//button[contains(text(), "Save")]')
           .assert.textContains('eg-grid', carouselName.slice(0, 5), 'Grid has refreshed and is now showing the first part of the carousel name');
  }
};
