/**
 * Common code for mananging holdings
 */
import {Injectable, EventEmitter} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject} from '@eg/core/idl.service';
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
        private pcrud: PcrudService,
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

    // Using open-ils.actor.get_barcodes
    getItemIdFromBarcode(barcode: string): Promise<number> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            this.auth.token(), this.auth.user().ws_ou(), 'asset', barcode
        ).toPromise().then(resp => {
            if (this.evt.parse(resp)) {
                return Promise.reject(resp);
            } else if (resp.length === 0) {
                return null;
            } else {
                return resp[0].id;
            }
        });
    }
}

