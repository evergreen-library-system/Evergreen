import {NightwatchBrowser} from 'nightwatch';
import {navigateToEgUrl, scrollToTopOfPage} from '../../utils'

module.exports = {
    before: (browser: NightwatchBrowser) => {
        browser.page.login().loginToWebClient(browser, 'bm1cmartinez', 'demo123');
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },

    'Can enable the exclude electronic checkbox': (browser: NightwatchBrowser) => {
        [1000, 2000].forEach((screenWidth) => {
            browser.resizeWindow(screenWidth, 800);
            navigateToEgUrl('eg2/en-US/staff/catalog/search', browser);
            browser.page.catalogSearch().setValue('#first-query-input', 'data')
                                        .click('#run-catalog-search')
                                        .assert.textContains('#staff-catalog-results-container',
                                                             'Search Results (3)',
                                                             'Can run standard search at screen width ' + screenWidth);
            browser.page.catalogSearch().click('@searchPreferencesButton')
                                        .click('#electronic-resources-pref')
                                        .click('#context-termSearch-excludeElectronic');
            scrollToTopOfPage(browser);
            browser.click('#run-catalog-search')
                    .assert.textContains('#staff-catalog-results-container',
                                         'Search Results (2)',
                                         'Can run exclude electronic search at screen width ' + screenWidth);
            // Turn off the preference after we are done testing it
            browser.page.catalogSearch().click('@searchPreferencesButton')
                                        .click('#electronic-resources-pref');
        });
    },


};
