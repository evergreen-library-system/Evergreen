import {NightwatchAPI} from 'nightwatch';

const screenDimensions = [
    {width: 1920, height: 1080},
    {width: 375, height: 812}
];

module.exports = {
    before: (browser: NightwatchAPI) => {
        browser.page.login().loginToWebClient(browser, 'bm1cmartinez', 'carolynm1234');
    },

    after: (browser: NightwatchAPI) => {
        browser.end();
    },

    'Can select an org unit': (browser: NightwatchAPI) => {
        screenDimensions.forEach((currentSize) => {
            browser.window.resize(currentSize.width, currentSize.height);
            browser.navigateTo('eg2/en-US/staff/catalog/search');
            browser.element.findByLabelText('Search in Library').clear()
            browser.element.findByLabelText('Search in Library').setValue('B');
            browser.click('xpath', '//*[contains(text(),"BR2")]');
            browser.assert.valueContains('#search-org-selector', "BR2");
        });
    },

    'Can select a location group': (browser: NightwatchAPI) => {
        screenDimensions.forEach((currentSize) => {
            browser.window.resize(currentSize.width, currentSize.height);
            browser.navigateTo('eg2/en-US/staff/catalog/search');
            browser.element.findByLabelText('Search in Library').clear()
            browser.element.findByLabelText('Search in Library').setValue('juv');
            browser.click('xpath', '//eg-catalog-org-select//*[contains(text(),"Juvenile")]');
            browser.assert.valueContains('#search-org-selector', "Juvenile Collection");
        });
    },

    'Org select is accessible': (browser: NightwatchAPI) => {
        browser.axeInject().axeRun('#search-org-selector');
    }


};
