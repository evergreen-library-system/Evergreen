import {Component} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

/* Support barcode completion for barcoded asset/actor data.
 *
 * When multiple barcodes match, the user is presented with a selection
 * dialog to chose the desired barcode.
 *
 * <eg-barcode-select #barcodeSelect></eg-barcode-select>
 *
 * @ViewChild('barcodeSelect') private barcodeSelect: BarcodeSelectComponent;
 *
 * this.barcodeSelect.getBarcode(value)
 *   .then(barcode => console.log('found barcode', barcode));
 */

export interface BarcodeSelectResult {

    // Will be the originally requested barcode when no match is found.
    barcode: string;

    // Will be null when no match is found.
    id: number;
}

@Component({
    selector: 'eg-barcode-select',
    templateUrl: './barcode-select.component.html',
})

export class BarcodeSelectComponent extends DialogComponent {

    matches: BarcodeSelectResult[];
    selected: BarcodeSelectResult;
    inputs: {[id: number]: boolean};

    constructor(
        private modal: NgbModal,
        private evt: EventService,
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService
    ) { super(modal); }

    selectionChanged() {
        const id = Object.keys(this.inputs).map(i => Number(i))
            .filter(i => this.inputs[i] === true)[0];

        if (id) {
            this.selected = this.matches.filter(match => match.id === id)[0];

        } else {
            this.selected = null;
        }
    }

    // Returns promise of barcode
    // When multiple barcodes match, the user is asked to select one.
    // Returns promise of null if no match is found or the user cancels
    // the selection process.
    getBarcode(class_: 'asset' | 'actor',
        barcode: string): Promise<BarcodeSelectResult> {

        this.matches = [];
        this.inputs = {};

        const result: BarcodeSelectResult = {
            barcode: barcode,
            id: null
        };

        let promise = this.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            this.auth.token(), this.auth.user().ws_ou(),
            class_, barcode.trim()
        ).toPromise();

        promise = promise.then(results => {

            if (!results) { return result; }

            results.forEach(res => {
                if (!this.evt.parse(res)) {
                    this.matches.push(res);
                }
            });

            if (this.matches.length === 0) {
                return result;

            } else if (this.matches.length === 1) {
                return this.matches[0];

            } else {
                return this.open().toPromise();
            }
        });

        return promise;
    }
}

