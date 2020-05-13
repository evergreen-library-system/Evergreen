/**
 * Common code for mananging holdings
 */
import {Injectable, EventEmitter} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';

interface NewCallNumData {
    owner?: number;
    label?: string;
    fast_add?: boolean;
    barcode?: string;
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
        recordId: number,                  // Bib record ID
        editExistingCallNums?: number[],   // Add copies to / modify existing CNs
        newCallNumData?: NewCallNumData[], // Creating new call numbers
        editCopyIds?: number[],            // Edit existing items
        hideCopies?: boolean,              // Hide the copy edit pane
        hideVols?: boolean) {

        const raw: any[] = [];

        if (editExistingCallNums) {
            editExistingCallNums.forEach(
                callNumId => raw.push({callnumber: callNumId}));
        } else if (newCallNumData) {
            newCallNumData.forEach(data => raw.push(data));
        }

        this.anonCache.setItem(null, 'edit-these-copies', {
            record_id: recordId,
            raw: raw,
            copies: editCopyIds,
            hide_vols : hideVols === true,
            hide_copies : hideCopies === true
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

