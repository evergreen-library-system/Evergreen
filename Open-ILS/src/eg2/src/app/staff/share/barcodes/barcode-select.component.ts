import {Component, Input, Output, OnInit, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {map, mergeMap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService, EgEvent} from '@eg/core/event.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

/* Suppor barcode completion for asset/actor/serial/booking data */

@Component({
  selector: 'eg-barcode-select',
  templateUrl: './barcode-select.component.html',
})

export class BarcodeSelectComponent
    extends DialogComponent implements OnInit {

    selectedBarcode: string;
    barcodes: string[];
    inputs: {[barcode: string]: boolean};

    constructor(
        private modal: NgbModal,
        private evt: EventService,
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService
    ) { super(modal); }

    ngOnInit() {
    }

    selectionChanged() {
        this.selectedBarcode = Object.keys(this.inputs)
            .filter(barcode => this.inputs[barcode] === true)[0];
    }

    // Returns promise of barcode
    // When multiple barcodes match, the user is asked to select one.
    // Returns promise of null if no match is found or the user cancels
    // the selection process.
    getBarcode(class_: 'asset' | 'actor', barcode: string): Promise<string> {
        this.barcodes = [];
        this.inputs = {};

       let promise = this.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            this.auth.token(), this.auth.user().ws_ou(),
            class_, barcode.trim()
        ).toPromise();

        promise = promise.then(results => {

            if (!results) { return null; }

            results.forEach(result => {
                if (!this.evt.parse(result)) {
                    this.barcodes.push(result.barcode);
                }
            });

            if (this.barcodes.length === 0) {
                return null;
            } else if (this.barcodes.length === 1) {
                return this.barcodes[0];
            } else {
                return this.open().toPromise();
            }
        });

        return promise;
    }
}

