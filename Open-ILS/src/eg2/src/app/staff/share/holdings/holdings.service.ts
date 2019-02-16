/**
 * Common code for mananging holdings
 */
import {Injectable, EventEmitter} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';

interface NewVolumeData {
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
        recordId: number,                   // Bib record ID
        addToVols: number[] = [],           // Add copies to existing volumes
        volumeData: NewVolumeData[] = []) { // Creating new volumes

        const raw: any[] = [];

        if (addToVols) {
            addToVols.forEach(volId => raw.push({callnumber: volId}));
        } else if (volumeData) {
            volumeData.forEach(data => raw.push(data));
        }

        if (raw.length === 0) { raw.push({}); }

        this.anonCache.setItem(null, 'edit-these-copies', {
            record_id: recordId,
            raw: raw,
            hide_vols : false,
            hide_copies : false
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

