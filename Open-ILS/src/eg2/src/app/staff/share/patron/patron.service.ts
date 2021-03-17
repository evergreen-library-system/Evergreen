import {Injectable} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {Observable} from 'rxjs';
import {BarcodeSelectComponent} from '@eg/staff/share/barcodes/barcode-select.component';


@Injectable()
export class PatronService {

    identTypes: IdlObject[];
    profileGroups: IdlObject[];

    constructor(
        private net: NetService,
        private org: OrgService,
        private evt: EventService,
        private pcrud: PcrudService,
        private auth: AuthService
    ) {}

    bcSearch(barcode: string): Observable<any> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            this.auth.token(), this.auth.user().ws_ou(),
           'actor', barcode.trim());
    }

    // XXX: This assumes the provided barcode only matches a single patron.
    // Use the <eg-barcode-select> component instead when the provided
    // barcode could match multiple patrons.
    //
    // Note pcrudOps should be constructed from the perspective
    // of a user ('au') retrieval, not a barcode ('ac') retrieval.
    getByBarcode(barcode: string, pcrudOps?: any): Promise<IdlObject> {
        return this.bcSearch(barcode).toPromise()
        .then(barcodes => {
            if (!barcodes) { return null; }

            // Use the first successful barcode response.
            // Use for-loop for early exit since we have async
            // action within the loop.
            for (let i = 0; i < barcodes.length; i++) {
                const bc = barcodes[i];
                if (!this.evt.parse(bc)) {
                    return this.getById(bc.id, pcrudOps);
                }
            }

            return null;
        });
    }

    getById(id: number, pcrudOps?: any): Promise<IdlObject> {
        return this.pcrud.retrieve('au', id, pcrudOps).toPromise();
    }

    // Returns a name part (e.g. family_name) with preference for
    // preferred name value where available.
    namePart(patron: IdlObject, part: string): string {
        if (!patron) { return ''; }
        return patron['pref_' + part]() || patron[part]();
    }


    // Returns promise of 'expired', 'soon', or null depending on the
    // expire date disposition of the provided patron.
    testExpire(patron: IdlObject): Promise<'expired' | 'soon'> {

        const expire = new Date(Date.parse(patron.expire_date()));
        if (expire < new Date()) {
            return Promise.resolve('expired');
        }

        return this.org.settings(['circ.patron_expires_soon_warning'])
        .then(setting => {
            const days = setting['circ.patron_expires_soon_warning'];

            if (Number(days)) {
                const preExpire = new Date();
                preExpire.setDate(preExpire.getDate() + Number(days));
                if (expire < preExpire) { return 'soon'; }
            }

            return null;
        });
    }

    getIdentTypes(): Promise<IdlObject[]> {
        if (this.identTypes) {
            return Promise.resolve(this.identTypes);
        }

        return this.pcrud.retrieveAll('cit',
            {order_by: {cit: ['name']}}, {atomic: true})
        .toPromise().then(types => this.identTypes = types);
    }

    getProfileGroups(): Promise<IdlObject[]> {
        if (this.profileGroups) {
            return Promise.resolve(this.profileGroups);
        }

        return this.pcrud.retrieveAll('pgt',
            {order_by: {cit: ['name']}}, {atomic: true})
        .toPromise().then(types => this.profileGroups = types);
    }
}

