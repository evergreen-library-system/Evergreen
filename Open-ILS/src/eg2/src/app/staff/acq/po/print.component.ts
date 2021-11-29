import {Component, OnInit, AfterViewInit} from '@angular/core';
import {Observable} from 'rxjs';
import {map, take} from 'rxjs/operators';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PrintService} from '@eg/share/print/print.service';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {PoService} from './po.service';
import {LineitemService} from '../lineitem/lineitem.service';

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
const ORDER_IDENT_ATTRS = [
    'isbn',
    'issn',
    'upc'
];

@Component({
  templateUrl: 'print.component.html'
})
export class PrintComponent implements OnInit, AfterViewInit {

    poId: number;
    outlet: Element;
    po: IdlObject;
    printing: boolean;
    closing: boolean;
    initDone = false;

    constructor(
        private route: ActivatedRoute,
        private idl: IdlService,
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private store: ServerStoreService,
        private pcrud: PcrudService,
        private poService: PoService,
        private liService: LineitemService,
        private broadcaster: BroadcastService,
        private printer: PrintService) {
    }

    ngOnInit() {
        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            const poId = +params.get('poId');
            if (poId !== this.poId) {
                this.poId = poId;
                if (poId && this.initDone) { this.load(); }
            }
        });

        this.load();
    }

    ngAfterViewInit() {
        this.outlet = document.getElementById('print-outlet');
    }

    load() {
        if (!this.poId) { return; }

        this.po = null;
        this.poService.getFleshedPo(this.poId, {
            fleshMore: {
                flesh_provider_addresses: true,
                flesh_lineitems: true,
                flesh_lineitem_attrs: true,
                flesh_lineitem_notes: true,
                flesh_lineitem_details: true,
                clear_marc: true,
                flesh_notes: true
            }
        })
        .then(po => this.po = po)
        .then(_ => this.sortLineItems())
        .then(_ => this.populatePreview())
        .then(_ => this.initDone = true);
    }

    sortLineItems(): Promise<any> {
        return this.store.getItem('acq.lineitem.sort_order').then(sortOrder => {
            if (!sortOrder || !SORT_ORDERS.includes(sortOrder)) {
                sortOrder = DEFAULT_SORT_ORDER;
            }
            const liService = this.liService;
            function _compareLIs(a, b) {
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
            this.po.lineitems().sort(_compareLIs);
        });
    }

    populatePreview(): Promise<any> {

        return this.printer.compileRemoteTemplate({
            templateName: 'purchase_order',
            printContext: 'default',
            contextData: {po: this.po}

        }).then(response => {
            this.outlet.innerHTML = response.content;
        });
    }

    addLiPrintNotes(): Promise<any> {

        const notes = [];
        this.po.lineitems().forEach(li => {
            const note = this.idl.create('acqlin');
            note.isnew(true);
            note.lineitem(li.id());
            note.value('printed: ' + this.auth.user().usrname());
            notes.push(note);
        });

        return this.net.request('open-ils.acq',
            'open-ils.acq.lineitem_note.cud.batch', this.auth.token(), notes)
        .toPromise().then(_ => {
            this.broadcaster.broadcast(
                'eg.acq.lineitem.notes.update', {
                lineitems: notes.map(n => Number(n.lineitem()))
            });
        });
    }

    printPo(closeTab?: boolean) {
        this.addLiPrintNotes().then(_ => this.printPo2(closeTab));
    }

    printPo2(closeTab?: boolean) {
        if (closeTab || this.closing) {
            const sub: any = this.printer.printJobQueued$.subscribe(req => {
                if (req.templateName === 'purchase_order') {
                    setTimeout(() => {
                        window.close();
                        sub.unsubscribe();
                    }, 2000); // allow for a time cushion past queueing.
                }
            });
        }

        this.printer.print({
            templateName: 'purchase_order',
            printContext: 'default',
            contextData: {po: this.po}
        });
    }
}

