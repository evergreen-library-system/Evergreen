import {NightwatchBrowser} from 'nightwatch';

module.exports = {
    before: (browser: NightwatchBrowser) => {
        browser.page.login().loginToWebClient(browser, 'admin', 'demo123');
    },

    after: (browser: NightwatchBrowser) => {
        browser.end();
    },

    'Can double click on a row to open the item editor': (browser: NightwatchBrowser) => {
        browser.resizeWindow(1400, 1000); // Make sure the browser window is big enough
        browser.navigateTo('eg2/en-US/staff/catalog/record/117/holdings');
        const firstBarcode = 'FRE400001052';
        browser.click('#eg-grid-toolbar-cb1');
        browser.doubleClick('.holdings-copy-row');

        browser.waitUntil(async () => {
            return new Promise((resolve) => {
                browser.windowHandles((result) => {
                    const tabs = <Array<any>>result.value;
                    resolve(tabs.length === 2);
                });
            });
        });

        browser.windowHandles((result) => {
            const tabs = <Array<any>>result.value;
            browser.switchToWindow(tabs[1]);
        });

        browser.assert.urlContains('/cat/volcopy/attrs/session');
        browser.assert.textContains('eg-batch-item-attr[label=Barcode]', firstBarcode);
    }
}
