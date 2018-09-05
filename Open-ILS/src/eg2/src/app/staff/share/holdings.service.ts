/**
 * Common code for mananging holdings
 */
import {Injectable, EventEmitter} from '@angular/core';
import {NetService} from '@eg/core/net.service';

interface NewVolumeData {
    owner: number;
    label?: string;
}

@Injectable()
export class HoldingsService {

    constructor(private net: NetService) {}

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

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'edit-these-copies', {
                record_id: recordId,
                raw: raw,
                hide_vols : false,
                hide_copies : false
            }
        ).subscribe(
            key => {
                if (!key) {
                    console.error('Could not create holds cache key!');
                    return;
                }
                setTimeout(() => {
                    const url = `/eg/staff/cat/volcopy/${key}`;
                    window.open(url, '_blank');
                });
            }
        );
    }

}

