import { EresourceClickTrack } from "../../js/ui/default/opac/eresource_click_tracker.module.js";
import { JSDOM } from '../deps/node_modules/jsdom/lib/api.js';

describe("eresourceClickTrack", () => {
    it("sends a beacon on click", () => {
        global.window = new JSDOM(`<!DOCTYPE html><body><a href="https://my-database" data-record-id="12345" id="link">Click here</a></body>`).window;
        Object.defineProperty(global.window, 'navigator', {
            value: {sendBeacon: () => Promise.resolve()}
        })
        spyOn(global.window.navigator, 'sendBeacon');
        global.document = global.window.document;

        const expectedData = new FormData();
        expectedData.append('record_id', 12345);
        expectedData.append('url', 'https://my-database');

        new EresourceClickTrack().setup('#link');
        const clickEvent = new global.window.Event( 'click', { bubbles: true } )
        global.document.querySelector('#link').dispatchEvent(clickEvent);

        expect(global.window.navigator.sendBeacon).toHaveBeenCalledWith(
            '/opac/extras/eresource_link_click_track',
            expectedData
        );
    });
});
