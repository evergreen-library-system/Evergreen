import {Component, AfterViewInit, ViewChild} from '@angular/core';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {PrintService} from '@eg/share/print/print.service';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {EventService} from '@eg/core/event.service';
import {PatronNoteDialogComponent} from '@eg/staff/share/patron/note-dialog.component';

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
    itemProcessed = false;

    @ViewChild('noteDialog', {static: false})
        noteDialog: PatronNoteDialogComponent;

    constructor(
        private route: ActivatedRoute,
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
        this.selectInput();
    }

    getItemByBarcode(): Promise<any> {
        this.itemId = null;
        this.item = null;

        if (!this.itemBarcode) { return Promise.resolve(); }

        // Submitting a new barcode resets the form.
        const bc = this.itemBarcode;
        this.reset();
        this.itemBarcode = bc;

        return this.holdings.getItemIdFromBarcode(this.itemBarcode)
            .then(id => {
                this.noSuchItem = (id === null);
                this.itemId = id;
                return this.getItemById();
            });
    }

    selectInput() {
        setTimeout(() => {
            const node: HTMLInputElement =
                document.getElementById('item-barcode-input') as HTMLInputElement;
            if (node) { node.select(); }
        });
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
        this.letter = null;
        this.itemBarcode = null;
        this.circNotFound = false;
        this.itemProcessed = false;
    }

    processItem() {
        this.circNotFound = false;
        this.itemProcessed = false;

        if (!this.item) { return; }

        this.processing = true;

        this.net.request(
            'open-ils.circ',
            'open-ils.circ.mark_item_missing_pieces',
            this.auth.token(), this.itemId
        ).subscribe(resp => {
            const evt = this.evt.parse(resp); // always returns event
            this.processing = false;
            this.itemProcessed = true;

            if (evt.textcode === 'ACTION_CIRCULATION_NOT_FOUND') {
                this.circNotFound = true;
                this.selectInput();
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
                this.noteDialog.patronId = payload.circ.usr();
                // eslint-disable-next-line rxjs/no-nested-subscribe
                this.noteDialog.open().subscribe(
                    penId => console.debug('Applied note ', penId),
                    (err: unknown) => {},
                    () => this.selectInput()
                );
            } else {
                this.selectInput();
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
        // eslint-disable-next-line no-magic-numbers
        return this.letter ? this.letter.split(/\n/).length + 2 : 20;
    }
}



