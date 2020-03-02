import {Component, Input, AfterViewInit, ViewChild, Renderer2} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {PrintService} from '@eg/share/print/print.service';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {EventService} from '@eg/core/event.service';
import {PatronPenaltyDialogComponent} from '@eg/staff/share/patron/penalty-dialog.component';

@Component({
  templateUrl: 'missing-pieces.component.html'
})
export class MarkItemMissingPiecesComponent implements AfterViewInit {

    itemId: number;
    itemBarcode: string;
    item: IdlObject;
    letter: string;
    circNotFound = false;
    processing = false;
    noSuchItem = false;

    @ViewChild('penaltyDialog', {static: false})
    penaltyDialog: PatronPenaltyDialogComponent;

    constructor(
        private route: ActivatedRoute,
        private renderer: Renderer2,
        private net: NetService,
        private printer: PrintService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private evt: EventService,
        private holdings: HoldingsService
    ) {
        this.itemId = +this.route.snapshot.paramMap.get('id');
    }

    ngAfterViewInit() {
        if (this.itemId) { this.getItemById(); }
        this.renderer.selectRootElement('#item-barcode-input').focus();
    }

    getItemByBarcode(): Promise<any> {
        this.itemId = null;
        this.item = null;

        if (!this.itemBarcode) { return Promise.resolve(); }

        return this.holdings.getItemIdFromBarcode(this.itemBarcode)
        .then(id => {
            this.noSuchItem = (id === null);
            this.itemId = id;
            return this.getItemById();
        });
    }

    selectInput() {
        setTimeout(() =>
            this.renderer.selectRootElement('#item-barcode-input').select());
    }

    getItemById(): Promise<any> {
        this.circNotFound = false;

        if (!this.itemId) {
            this.selectInput();
            return Promise.resolve();
        }

        const flesh = {
            flesh: 3,
            flesh_fields: {
                acp: ['call_number'],
                acn: ['record'],
                bre: ['flat_display_entries']
            }
        };

        return this.pcrud.retrieve('acp', this.itemId, flesh)
        .toPromise().then(item => {
            this.item = item;
            this.itemId = item.id();
            this.itemBarcode = item.barcode();
            this.selectInput();
        });
    }

    display(field: string): string {
        if (!this.item) { return ''; }

        const entry = this.item.call_number().record()
            .flat_display_entries()
            .filter(fde => fde.name() === field)[0];

        return entry ? entry.value() : '';
    }

    reset() {
        this.item = null;
        this.itemId = null;
        this.itemBarcode = null;
        this.circNotFound = false;
    }

    processItem() {
        this.circNotFound = false;

        if (!this.item) { return; }

        this.processing = true;

        this.net.request(
            'open-ils.circ',
            'open-ils.circ.mark_item_missing_pieces',
            this.auth.token(), this.itemId
        ).subscribe(resp => {
            const evt = this.evt.parse(resp); // always returns event
            this.processing = false;

            if (evt.textcode === 'ACTION_CIRCULATION_NOT_FOUND') {
                this.circNotFound = true;
                return;
            }

            const payload = evt.payload;

            if (payload.letter) {
                this.letter = payload.letter.template_output().data();
            }

            if (payload.slip) {
                this.printer.print({
                    printContext: 'default',
                    contentType: 'text/html',
                    text: payload.slip.template_output().data()
                });
            }

            if (payload.circ) {
                this.penaltyDialog.patronId = payload.circ.usr();
                this.penaltyDialog.open().subscribe(
                    penId => console.debug('Applied penalty ', penId));
            }
        });
    }

    printLetter() {
        this.printer.print({
            printContext: 'default',
            contentType: 'text/plain',
            text: this.letter
        });
    }

    letterRowCount(): number {
        return this.letter ? this.letter.split(/\n/).length + 2 : 20;
    }
}



