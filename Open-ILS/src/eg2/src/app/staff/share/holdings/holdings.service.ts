/* eslint-disable no-magic-numbers */
/**
 * Common code for mananging holdings
 */
import {Injectable} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {tap} from 'rxjs/operators';
import {NetService} from '@eg/core/net.service';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';

export interface CallNumData {
    owner?: number;
    label?: string;
    fast_add?: boolean;
    barcode?: string;
    callnumber?: number;
}

@Injectable()
export class HoldingsService {

    copyStatuses: {[id: number]: IdlObject};

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
        newCallNumData?: CallNumData[],    // Creating new call numbers
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
                const tab = hideVols ? 'attrs' : 'holdings';
                let url = `/eg2/staff/cat/volcopy/${tab}/session/${key}`;
                if (recordId !== null) {url += `?record_id=${recordId}`;}
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

    /* TODO: make these more configurable per lp1616170 */
    getMagicCopyStatuses(): Promise<number[]> {
        return Promise.resolve([
            1,  // Checked out
            3,  // Lost
            6,  // In transit
            8,  // On holds shelf
            16, // Long overdue
            18  // Canceled Transit
        ]);
    }

    getCopyStatuses(): Promise<{[id: number]: IdlObject}> {
        if (this.copyStatuses) {
            return Promise.resolve(this.copyStatuses);
        }

        this.copyStatuses = {};
        return this.pcrud.retrieveAll('ccs', {order_by: {ccs: 'name'}})
            .pipe(tap(stat => this.copyStatuses[stat.id()] = stat))
            .toPromise().then(_ => this.copyStatuses);
    }
}

