import {Component, OnInit, Output, Input, ViewChild, EventEmitter} from '@angular/core';
import {empty, of, from, Observable} from 'rxjs';
import {concatMap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {CircService} from './circ.service';
import {StringComponent} from '@eg/share/string/string.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {CheckinResult} from './circ.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AudioService} from '@eg/share/util/audio.service';
import {PrintService} from '@eg/share/print/print.service';

/** Route Item Dialog */

@Component({
  templateUrl: 'route-dialog.component.html',
  selector: 'eg-circ-route-dialog'
})
export class RouteDialogComponent extends DialogComponent {

    checkin: CheckinResult;
    noAutoPrint: {[template: string]: boolean} = {};
    slip: string;
    today = new Date();

    constructor(
        private modal: NgbModal,
        private pcrud: PcrudService,
        private org: OrgService,
        private circ: CircService,
        private audio: AudioService,
        private printer: PrintService,
        private serverStore: ServerStoreService) {
        super(modal);
    }

    open(ops?: NgbModalOptions): Observable<any> {
        // Depending on various settings, the dialog may never open.
        // But in some cases we still have to collect the data
        // for printing.

        return from(this.applySettings())

        .pipe(concatMap(exit => {
            if (exit) {
                return of(exit);
            } else {
                return from(this.collectData());
            }
        }))

        .pipe(concatMap(exit => {
            if (exit) {
                return of(exit);
            } else {
                return super.open(ops);
            }
        }));
    }

    collectData(): Promise<boolean> {
        let promise = Promise.resolve(null);
        const hold = this.checkin.hold;

        if (this.slip !== 'hold_shelf_slip') {

            // Always fetch the most recent transit for the copy,
            // regardless of what data the server returns in the payload.

            promise = promise.then(_ => this.circ.findCopyTransit(this.checkin))
            .then(transit => {
                this.checkin.transit = transit;
                this.checkin.destOrg = this.org.get(transit.dest());
                return this.circ.getOrgAddr(this.checkin.destOrg.id(), 'holds_address');
            })
            .then(addr => {
                this.checkin.destAddress = addr;
                return this.org.settings('lib.courier_code', this.checkin.destOrg.id())
            })

            .then(sets => this.checkin.destCourierCode = sets['lib.courier_code']);
        }

        if (hold) {
            promise = promise.then(_ => {
                return this.pcrud.retrieve('au', hold.usr(),
                    {flesh: 1, flesh_fields : {'au' : ['card']}}).toPromise()
                .then(patron => this.checkin.patron = patron);
            });
        }

        this.audio.play(hold ?
            'info.checkin.transit.hold' : 'info.checkin.transit');

        if (this.checkin.params.auto_print_hold_transits
            || this.circ.suppressCheckinPopups) {
            // Print and exit.
            return this.print().then(_ => true); // exit
        }

        return promise.then(_ => false); // keep going
    }

    applySettings(): Promise<boolean> {

        if (this.checkin.transit) {
            if (this.checkin.patron) {
                this.slip = 'hold_transit_slip';
            } else {
                this.slip = 'transit_slip';
            }
        } else {
            this.slip = 'hold_shelf_slip';
        }

        const autoPrintSet = 'circ.staff_client.do_not_auto_attempt_print';

        return this.serverStore.getItemBatch([autoPrintSet]).then(sets => {
            const autoPrintArr = sets[autoPrintSet];

            if (Array.isArray(autoPrintArr)) {
                this.noAutoPrint['hold_shelf_slip'] =
                    autoPrintArr.includes('Hold Slip');

                this.noAutoPrint['hold_transit_slip'] =
                    autoPrintArr.includes('Hold/Transit Slip');

                this.noAutoPrint['transit_slip'] =
                    autoPrintArr.includes('Transit Slip');
            }
        })
        .then(_ => this.noAutoPrint[this.slip]);
    }

    print(): Promise<any> {
        this.printer.print({
            templateName: this.slip,
            contextData: {checkin: this.checkin},
            printContext: 'default'
        });

        this.close();

        // TODO printer.print() should return a promise
        return Promise.resolve();
    }
}

