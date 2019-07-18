/**
 * Common code for mananging holdings
 */
import {Injectable, EventEmitter} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';

interface NewCallNumData {
    owner: number;
    label?: string;
}

@Injectable()
export class HoldingsService {

    constructor(
        private net: NetService,
        private auth: AuthService,
        private evt: EventService,
        private anonCache: AnonCacheService
    ) {}

    // Open the holdings editor UI in a new browser window/tab.
    spawnAddHoldingsUi(
        recordId: number,               // Bib record ID
        addToCallNums?: number[],           // Add copies to / modify existing CNs
        callNumData?: NewCallNumData[],   // Creating new call numbers
        hideCopies?: boolean) {         // Hide the copy edit pane

        const raw: any[] = [];

        if (addToCallNums) {
            addToCallNums.forEach(callNumId => raw.push({callnumber: callNumId}));
        } else if (callNumData) {
            callNumData.forEach(data => raw.push(data));
        }

        if (raw.length === 0) { raw.push({}); }

        this.anonCache.setItem(null, 'edit-these-copies', {
            record_id: recordId,
            raw: raw,
            hide_vols : false,
            hide_copies : hideCopies ? true : false
        }).then(key => {
            if (!key) {
                console.error('Could not create holds cache key!');
                return;
            }
            setTimeout(() => {
                const url = `/eg/staff/cat/volcopy/${key}`;
                window.open(url, '_blank');
            });
        });
    }
}

