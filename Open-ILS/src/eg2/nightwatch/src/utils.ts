import {NightwatchBrowser} from 'nightwatch';
import {uriJoin} from 'nightwatch/lib/utils';
import * as path from 'path';

export function randomString(): string {
    return (Math.random() * 1e32).toString(36);
}

export function egUrl(urlPath: string, browser: NightwatchBrowser): string {
    return uriJoin(browser.baseUrl, urlPath);
}

export function navigateToEgUrl(urlPath: string, browser: NightwatchBrowser): void {
    browser.url(egUrl(urlPath, browser));
}

export function fmEditorFieldSelector(fieldName: string) {
    return 'input[placeholder="' + fieldName + '..."]';
}

export function fixtureFile(fileName: string) {
    return path.resolve(__dirname, '..', 'fixtures', fileName);
}

export function scrollToTopOfPage(browser: NightwatchBrowser) {
    browser.execute(() => { window.scrollTo(0, 0); });
}

export function waitForTabCount(count: number, browser: NightwatchBrowser): void {
    browser.waitUntil(async () => {
        return new Promise((resolve) => {
            browser.windowHandles((result) => {
                const tabs = <Array<any>>result.value;
                resolve(tabs.length === count);
            });
        });
    });
}

export function openTab(index: number, browser: NightwatchBrowser): void {
    browser.windowHandles((result) => {
        const tabs = <Array<any>>result.value;
        browser.switchToWindow(tabs[index]);
    });
}
