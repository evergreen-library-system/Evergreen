import {Injectable, EventEmitter} from '@angular/core';
import {Observable, from} from 'rxjs';
import {switchMap, map, tap, merge} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';

@Injectable()
export class PoService {

    currentPo: IdlObject;

    poRetrieved: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();

    constructor(
        private evt: EventService,
        private net: NetService,
        private auth: AuthService
    ) {}

    getFleshedPo(id: number, fleshMore?: any, noCache?: boolean): Promise<IdlObject> {

        if (!noCache) {
            if (this.currentPo && id === this.currentPo.id()) {
                // Set poService.currentPo = null to bypass the cache
                return Promise.resolve(this.currentPo);
            }
        }

        const flesh = Object.assign({
            flesh_provider: true,
            flesh_notes: true,
            flesh_po_items: true,
            flesh_price_summary: true,
            flesh_lineitem_count: true
        }, fleshMore || {});

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.purchase_order.retrieve',
            this.auth.token(), id, flesh
        ).toPromise().then(po => {

            const evt = this.evt.parse(po);
            if (evt) { return Promise.reject(evt + ''); }

            if (!noCache) { this.currentPo = po; }

            this.poRetrieved.emit(po);
            return po;
        });
    }

    // Fetch the PO again (with less fleshing) and update the
    // order summary totals our main fully-fleshed PO.
    refreshOrderSummary(): Promise<any> {

        return this.net.request('open-ils.acq',
            'open-ils.acq.purchase_order.retrieve.authoritative',
            this.auth.token(), this.currentPo.id(),
            {flesh_price_summary: true}

        ).toPromise().then(po => {

            this.currentPo.amount_encumbered(po.amount_encumbered());
            this.currentPo.amount_spent(po.amount_spent());
            this.currentPo.amount_estimated(po.amount_estimated());
        });
    }
}


