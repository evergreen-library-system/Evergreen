import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {Location} from '@angular/common';
import {from, tap} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from '../lineitem/lineitem.service';
import {Pager} from '@eg/share/util/pager';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';

interface ReceiveResponse {
    progress: number;
    lineitems: any[];
    complete: boolean;
    po: number;
}

@Component({
    templateUrl: 'receive.component.html'
})
export class AsnReceiveComponent implements OnInit {

    barcode = '';
    receiving = false;
    dryRun = false;
    receiveOnScan = false;
    notFound = false;
    findingContainer = false;
    loadingContainer = false;
    liCache: {[id: number]: any} = {};

    // Technically possible for one container code to match across providers.
    container: IdlObject;
    entries: IdlObject[] = [];
    containers: IdlObject[] = [];
    receiveResponse: ReceiveResponse;

    @ViewChild('grid') private grid: GridComponent;
    @ViewChild('progress') private progress: ProgressInlineComponent;

    gridDataSource: GridDataSource = new GridDataSource();

    constructor(
        private route: ActivatedRoute,
        private router: Router,
        private ngLocation: Location,
        private pcrud: PcrudService,
        private net: NetService,
        private auth: AuthService,
        private li: LineitemService
    ) {}

    ngOnInit() {
        this.barcode = this.route.snapshot.paramMap.get('containerCode') || '';
        if (this.barcode) {
            this.findContainer();
        }

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return from(this.entries.map(e => this.gridifyEntry(e)));
        };

        setTimeout(() => this.focusInput());
    }

    gridifyEntry(entry: IdlObject): any {
        const li = entry.lineitem();
        const sum = li.order_summary();
        const display = {
            entry: entry,
            lineitem: li,
            title: this.li.getFirstAttributeValue(li, 'title'),
            author: this.li.getFirstAttributeValue(li, 'author'),
            isbn: this.li.getFirstAttributeValue(li, 'isbn'),
            issn: this.li.getFirstAttributeValue(li, 'issn'),
            upc: this.li.getFirstAttributeValue(li, 'upc'),
            recievable_count: sum.item_count() - (
                sum.recv_count() + sum.cancel_count()
            )
        };

        this.liCache[li.id()] = display;

        return display;
    }

    findContainer() {
        this.findingContainer = true;
        this.loadingContainer = true;
        this.notFound = false;
        this.receiving = false;
        this.container = null;
        this.containers = [];
        this.entries = [];
        this.liCache = {};

        this.gridDataSource.reset();

        this.pcrud.search('acqsn',
            {container_code: this.barcode},
            {flesh: 1, flesh_fields: {acqsn: ['entries', 'provider']}}
        ).subscribe(
            { next: sn => this.containers.push(sn), error: (_: unknown) => {}, complete: () => {
                this.findingContainer = false;

                // TODO handle multiple containers w/ same code
                if (this.containers.length === 1) {
                    this.container = this.containers[0];
                    this.loadContainer().then(_ => {
                        if (this.receiveOnScan) {
                            this.receiveAllItems();
                        }
                    });
                } else if (this.containers.length === 0) {
                    this.notFound = true;
                    this.loadingContainer = false;
                }

                this.focusInput();
            } }
        );
    }

    focusInput() {
        const node = document.getElementById('barcode-search-input');
        (node as HTMLInputElement).select();
    }

    loadContainer(): Promise<any> {
        if (!this.container) {
            this.loadingContainer = false;
            return Promise.resolve();
        }

        const entries = this.container.entries();

        if (entries.length === 0) {
            this.loadingContainer = false;
            return Promise.resolve();
        }

        return this.li.getFleshedLineitems(entries.map(e => e.lineitem()), {})
            .pipe(tap(li_struct => {
            // Flesh the lineitems directly in the shipment entry
                const entry = entries.filter(e => e.lineitem() === li_struct.id)[0];
                entry.lineitem(li_struct.lineitem);
            })).toPromise()
            .then(_ => {
                this.entries = entries;
                this.loadingContainer = false;
                if (this.grid) { // Hidden during receiveOnScan
                    this.grid.reload();
                }
            });
    }

    openLi(row: any) {
        let url = this.ngLocation.prepareExternalUrl(
            this.router.serializeUrl(
                this.router.createUrlTree(
                    ['/staff/acq/po/', row.lineitem.purchase_order().id()]
                )
            )
        );

        // this.router.createUrlTree() documents claim it supports
        // {fragment: row.lineitem.id()}, but it's not getting added to
        // the URL. Adding manually.
        url += '#' + row.lineitem.id();

        window.open(url);
    }

    affectedItemsCount(): number {
        if (this.entries.length === 0) { return 0; }
        return this.entries
            .map(e => e.item_count())
            .reduce((pv, cv) => pv + (cv || 0));
    }

    receiveAllItems(): Promise<any> {
        this.receiving = true;

        this.receiveResponse = {
            progress: 0,
            lineitems: [],
            complete: false,
            po: null
        };

        setTimeout(() => // Allow time to render
            this.progress.update({value: 0, max: this.affectedItemsCount()}));

        let method = 'open-ils.acq.shipment_notification.receive_items';
        if (this.dryRun) { method += '.dry_run'; }

        return this.net.request('open-ils.acq',
            method, this.auth.token(), this.container.id()
        ).pipe(tap(resp => {
            this.progress.update({value: resp.progress});
            console.debug('ASN Receive returned', resp);
            this.receiveResponse = resp;
        })).toPromise();
    }

    clearReceiving() {
        this.receiving = false;
        this.findContainer();
    }

    liWantedCount(liId: number): number {
        const entry = this.entries.filter(e => e.lineitem().id() === liId)[0];
        if (entry) { return entry.item_count(); }
        return 0;
    }
}

