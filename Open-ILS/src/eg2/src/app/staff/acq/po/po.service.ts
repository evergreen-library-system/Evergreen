import {Injectable, EventEmitter} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FleshCacheParams} from '@eg/staff/acq/lineitem/lineitem.service';

export interface PoDupeCheckResults {
    dupeFound: boolean;
    dupePoId: number;
}

@Injectable()
export class PoService {

    currentPo: IdlObject;

    poRetrieved: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();

    constructor(
        private evt: EventService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private auth: AuthService
    ) {}

    getFleshedPo(id: number, params: FleshCacheParams = {}): Promise<IdlObject> {

        if (params.fromCache) {
            if (this.currentPo && id === this.currentPo.id()) {
                // Set poService.currentPo = null to bypass the cache
                return Promise.resolve(this.currentPo);
            }
        }

        const flesh = Object.assign({
            flesh_provider: true,
            flesh_notes: true,
            flesh_po_items: true,
            flesh_po_items_further: true,
            flesh_price_summary: true,
            flesh_lineitem_count: true
        }, params.fleshMore || {});

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.purchase_order.retrieve',
            this.auth.token(), id, flesh
        ).toPromise().then(po => {

            const evt = this.evt.parse(po);
            if (evt) { return Promise.reject(evt + ''); }

            if (params.toCache) { this.currentPo = po; }

            this.poRetrieved.emit(po);
            return po;
        });
    }

    // Fetch the PO again (with less fleshing) and update the
    // order summary totals our main fully-fleshed PO.
    refreshOrderSummary(update_po_items = false): Promise<any> {

        const flesh = Object.assign({
            flesh_price_summary: true
        });
        if (update_po_items) {
            flesh['flesh_po_items'] = true;
            flesh['flesh_po_items_further'] = true;
        }
        return this.net.request('open-ils.acq',
            'open-ils.acq.purchase_order.retrieve.authoritative',
            this.auth.token(), this.currentPo.id(),
            flesh

        ).toPromise().then(po => {

            this.currentPo.amount_encumbered(po.amount_encumbered());
            this.currentPo.amount_spent(po.amount_spent());
            this.currentPo.amount_estimated(po.amount_estimated());
            if (update_po_items) {
                this.currentPo.po_items(po.po_items());
            }
        });
    }

    checkIfImportNeeded(): Promise<boolean> {
        return new Promise((resolve, reject) => {
            this.pcrud.search('jub',
                { purchase_order: this.currentPo.id(), eg_bib_id: null },
                { limit: 1 }, { idlist: true, atomic: true }
            ).toPromise().then(ids => {
                if (ids && ids.length) {
                    resolve(true);
                } else {
                    resolve(false);
                }
            });
        });
    }

    checkDuplicatePoName(orderAgency: number, poName: string, results: PoDupeCheckResults) {
        if (Boolean(orderAgency) && Boolean(poName)) {
            this.pcrud.search('acqpo',
                { name: poName, ordering_agency: this.org.descendants(orderAgency, true) },
                {}, { idlist: true, atomic: true }
            ).toPromise().then(ids => {
                if (ids && ids.length) {
                    results.dupeFound = true;
                    results.dupePoId = ids[0];
                } else {
                    results.dupeFound = false;
                }
            });
        } else {
            results.dupeFound = false;
        }
    }
}


