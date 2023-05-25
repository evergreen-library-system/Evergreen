import {Component, OnInit, AfterViewInit} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {IdlService} from '@eg/core/idl.service';
import {PrintService} from '@eg/share/print/print.service';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {InvoiceService} from './invoice.service';
import {LineitemService} from '../lineitem/lineitem.service';
import {firstValueFrom} from 'rxjs';

const DEFAULT_SORT_ORDER = 'li_id_asc';
const SORT_ORDERS = [
    'li_id_asc',
    'li_id_desc',
    'title_asc',
    'title_desc',
    'author_asc',
    'author_desc',
    'publisher_asc',
    'publisher_desc',
    'order_ident_asc',
    'order_ident_desc'
];

@Component({
    selector: 'eg-acq-invoice-print',
    templateUrl: 'print.component.html'
})
export class PrintComponent implements OnInit, AfterViewInit {

    outlet: Element;
    printing: boolean;
    closing: boolean;
    initDone = false;

    constructor(
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private store: ServerStoreService,
        private invoiceService: InvoiceService,
        private liService: LineitemService,
        private broadcaster: BroadcastService,
        private printer: PrintService) {
    }

    ngOnInit() {
        console.debug('PrintComponent, this', this);
        this.load();
    }

    ngAfterViewInit() {
        this.outlet = document.getElementById('print-outlet');
    }

    load() {
        this.populatePreview();
        this.initDone = true;
    }

    async sortLineItems(): Promise<any> {
        let sortOrder = await this.store.getItem('acq.lineitem.sort_order');
        if (!sortOrder || !SORT_ORDERS.includes(sortOrder)) {
            sortOrder = DEFAULT_SORT_ORDER;
        }
        const liService = this.liService;
        function _compareLIs(ea:any, eb:any) {
            const a = ea.lineitem();
            const b = eb.lineitem();
            const direction = sortOrder.match(/_asc$/) ? 'asc' : 'desc';
            const field = sortOrder.replace(/_asc|_desc$/, '');
            const a_val = liService.getLISortKey(a, field);
            const b_val = liService.getLISortKey(b, field);

            if (direction === 'asc') {
                return  liService.nullableCompare(a_val, b_val);
            } else {
                return -liService.nullableCompare(a_val, b_val);
            }
        }
        this.invoiceService.currentInvoice.entries().sort(_compareLIs);
    }

    async populatePreview(): Promise<void> {
        const response = await firstValueFrom( this.net.request(
            'open-ils.acq',
            'open-ils.acq.invoice.print.html',
            this.auth.token(), this.invoiceService.currentInvoice.id()
        ) );
        this.outlet.innerHTML = response.template_output().data();
        return;
    }

    // TODO: add enough fleshing so that server-side print templates can be used
    /*
        return this.printer.compileRemoteTemplate({
            templateName: 'purchase_order',
            printContext: 'default',
            contextData: {po: this.po}

        }).then(response => {
            this.outlet.innerHTML = response.content;
        });
*/

    async addLiPrintNotes(): Promise<any> {

        const notes = [];
        this.invoiceService.currentInvoice.entries().map( (e: IdlObject) => e.lineitem).forEach((li: IdlObject) => {
            const note = this.idl.create('acqlin');
            note.isnew(true);
            note.lineitem(li.id());
            note.value('printed: ' + this.auth.user().usrname());
            notes.push(note);
        });

        await firstValueFrom( this.net.request('open-ils.acq',
            'open-ils.acq.lineitem_note.cud.batch', this.auth.token(), notes));

        this.broadcaster.broadcast(
            'eg.acq.lineitem.notes.update', {
                lineitems: notes.map(n => Number(n.lineitem()))
            });
    }

    printInvoice(closeTab?: boolean) {
        // this.addLiPrintNotes().then(_ => this.printInvoice2(closeTab));
        this.printInvoice2(closeTab);
    }

    async printInvoice2(closeTab?: boolean): Promise<null> {
        if (closeTab || this.closing) {
            const sub: any = this.printer.printJobQueued$.subscribe(req => {
                if (req.templateName === 'invoice') {
                    setTimeout(() => {
                        window.close();
                        sub.unsubscribe();
                    }, 2000); // allow for a time cushion past queueing.
                }
            });
        }

        const response = await firstValueFrom( this.net.request(
            'open-ils.acq',
            'open-ils.acq.invoice.print.html',
            this.auth.token(), this.invoiceService.currentInvoice.id()
        ));

        this.printer.print({
            printContext: 'default',
            text: response.template_output().data()
        });

        return;
    }
    // TODO: add enough fleshing so that server-side print templates can be used
/*
        this.printer.print({
            templateName: 'purchase_order',
            printContext: 'default',
            contextData: {po: this.po}
        });
*/
}

