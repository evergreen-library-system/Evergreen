/* eslint-disable rxjs/no-nested-subscribe */
import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {from, of} from 'rxjs';
import {concatMap} from 'rxjs/operators';
import {Router, ActivatedRoute} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {AcqSearchService, AcqSearchTerm, AcqSearch} from './acq-search.service';
import {LineitemService} from '../lineitem/lineitem.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ExportAttributesDialogComponent} from '../lineitem/export-attributes-dialog.component';
import {AcqSearchFormComponent} from './acq-search-form.component';
import {StringComponent} from '@eg/share/string/string.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {ClaimPolicyDialogComponent} from '../lineitem/claim-policy-dialog.component';
import {CancelDialogComponent} from '../lineitem/cancel-dialog.component';
import {AddToPoDialogComponent} from '../lineitem/add-to-po-dialog.component';
import {DeleteLineitemsDialogComponent} from '../lineitem/delete-lineitems-dialog.component';
import {LinkInvoiceDialogComponent} from '../lineitem/link-invoice-dialog.component';
import {LineitemAlertDialogComponent} from '../lineitem/lineitem-alert-dialog.component';

@Component({
    selector: 'eg-lineitem-results',
    templateUrl: 'lineitem-results.component.html'
})
export class LineitemResultsComponent implements OnInit {

    @Input() initialSearchTerms: AcqSearchTerm[] = [];

    gridSource: GridDataSource;
    @ViewChild('acqSearchForm', { static: true}) acqSearchForm: AcqSearchFormComponent;
    @ViewChild('acqSearchLineitemsGrid', { static: true }) lineitemResultsGrid: GridComponent;
    @ViewChild('exportAttributesDialog') exportAttributesDialog: ExportAttributesDialogComponent;
    @ViewChild('claimPolicyDialog') claimPolicyDialog: ClaimPolicyDialogComponent;
    @ViewChild('cancelDialog') cancelDialog: CancelDialogComponent;
    @ViewChild('addToPoDialog') addToPoDialog: AddToPoDialogComponent;
    @ViewChild('deleteLineitemsDialog') deleteLineitemsDialog: DeleteLineitemsDialogComponent;
    @ViewChild('linkInvoiceDialog') linkInvoiceDialog: LinkInvoiceDialogComponent;
    @ViewChild('claimPolicyAppliedString', { static: false }) claimPolicyAppliedString: StringComponent;
    @ViewChild('lineItemsReceivedString', { static: false }) lineItemsReceivedString: StringComponent;
    @ViewChild('lineItemsUnReceivedString', { static: false }) lineItemsUnReceivedString: StringComponent;
    @ViewChild('lineItemsCancelledString', { static: false }) lineItemsCancelledString: StringComponent;
    @ViewChild('lineItemsAddedToPoString', { static: false }) lineItemsAddedToPoString: StringComponent;
    @ViewChild('lineItemsDeletedString', { static: false }) lineItemsDeletedString: StringComponent;
    @ViewChild('lineItemsUpdatedString', { static: false }) lineItemsUpdatedString: StringComponent;
    @ViewChild('noActionableLIs', { static: true }) private noActionableLIs: AlertDialogComponent;
    @ViewChild('selectorReadyConfirmDialog', { static: true }) selectorReadyConfirmDialog: ConfirmDialogComponent;
    @ViewChild('orderReadyConfirmDialog', { static: true }) orderReadyConfirmDialog: ConfirmDialogComponent;
    @ViewChild('confirmAlertsDialog') confirmAlertsDialog: LineitemAlertDialogComponent;

    noSelectedRows: (rows: IdlObject[]) => boolean;

    cellTextGenerator: GridCellTextGenerator;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private toast: ToastService,
        private liService: LineitemService,
        private acqSearch: AcqSearchService) {
    }

    ngOnInit() {
        this.gridSource = this.acqSearch.getAcqSearchDataSource('lineitem');
        this.noSelectedRows = (rows: IdlObject[]) => (rows.length === 0);
        this.cellTextGenerator = {
            id: row => row.id(),
            title: row => {
                const filtered = row.attributes().filter(lia => lia.attr_name() === 'title');
                if (filtered.length > 0) {
                    return filtered[0].attr_value();
                } else {
                    return '';
                }
            },
            author: row => {
                const filtered = row.attributes().filter(lia => lia.attr_name() === 'author');
                if (filtered.length > 0) {
                    return filtered[0].attr_value();
                } else {
                    return '';
                }
            },
            provider: row => row.provider() ? row.provider().code() : '',
            _links: row => '',
            purchase_order: row => row.purchase_order() ? row.purchase_order().name() : '',
            picklist: row => row.picklist() ? row.picklist().name() : '',
        };
    }

    doSearch(search: AcqSearch) {
        setTimeout(() => {
            this.acqSearch.setSearch(search);
            this.lineitemResultsGrid.reload();
        });
    }

    showRow(row: any) {
        window.open('/eg2/staff/acq/po/' + row.purchase_order().id() +
                    '/lineitem/' + row.id() + '/worksheet', '_blank');
    }

    addSelectedToPurchaseOrder(rows: IdlObject[]) {
        // must not be already attached to a PO
        // and be in a pre-order state
        const lis = rows.filter(
            l => !l.purchase_order() &&
            ['new', 'selector-ready', 'order-ready', 'approved'].includes(l.state())
        );
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }
        const ids = lis.map(x => Number(x.id()));

        this.addToPoDialog.ids = ids;
        this.addToPoDialog.open().subscribe(poId => {
            this.net.request('open-ils.acq',
                'open-ils.acq.purchase_order.add_lineitem',
                this.auth.token(), poId, ids
            ).toPromise().then(resp => {
                window.open('/eg2/staff/acq/po/' + poId, '_blank');
                this.lineItemsAddedToPoString.current()
                    .then(str => this.toast.success(str));
                this.lineitemResultsGrid.reload();
            });
        });
    }

    applyClaimPolicy(rows: IdlObject[]) {
        // must be attached to a PO; while this is not
        // strictly necessary, seems to make sense that
        // a claim policy is relevant only once you know
        // who the vendor is
        const lis = rows.filter(l => l.purchase_order());
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }
        const ids = lis.map(x => Number(x.id()));

        this.claimPolicyDialog.ids = ids;
        this.claimPolicyDialog.open().subscribe(claimPolicy => {
            if (!claimPolicy) { return; }

            const lisToUpdate: IdlObject[] = [];
            this.liService.getFleshedLineitems(ids, { fromCache: true }).subscribe(
                liStruct => {
                    liStruct.lineitem.claim_policy(claimPolicy);
                    lisToUpdate.push(liStruct.lineitem);
                },
                (err: unknown) => { },
                () => {
                    this.net.request(
                        'open-ils.acq',
                        'open-ils.acq.lineitem.update',
                        this.auth.token(), lisToUpdate
                    ).toPromise().then(resp => {
                        this.claimPolicyAppliedString.current()
                            .then(str => this.toast.success(str));
                    });
                }
            );
        });
    }

    cancelLineitems(rows: IdlObject[]) {
        // must be attached to a PO and have a state of
        // either 'on-order' or 'cancelled'
        const lis = rows.filter(l =>
            l.purchase_order() && ['on-order', 'cancelled'].includes(l.state())
        );
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }
        const ids = lis.map(x => Number(x.id()));
        this.cancelDialog.open().subscribe(reason => {
            if (!reason) { return; }

            this.net.request('open-ils.acq',
                'open-ils.acq.lineitem.cancel.batch',
                this.auth.token(), ids, reason
            ).toPromise().then(resp => {
                this.lineItemsCancelledString.current()
                    .then(str => this.toast.success(str));
                this.lineitemResultsGrid.reload();
            });
        });
    }

    createInvoiceFromSelected(rows: IdlObject[]) {
        // must be attached to PO
        const lis = rows.filter(l => l.purchase_order());
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }
        const path = '/eg/staff/acq/legacy/invoice/view?create=1&' +
                     lis.map(x => 'attach_li=' + x.id()).join('&');
        window.location.href = path;
    }

    createPurchaseOrder(rows: IdlObject[]) {
        // must not be already attached to a PO
        const lis = rows.filter(l => !l.purchase_order());
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }
        const ids = lis.map(x => Number(x.id()));
        this.router.navigate(['/staff/acq/po/create'], {
            queryParams: {li: ids}
        });
    }

    deleteLineitems(rows: IdlObject[]) {
        const lis = rows.filter(l =>
            l.picklist() || (
                l.purchase_order() &&
                ['new', 'selector-ready', 'order-ready', 'approved', 'pending-order'].includes(l.state())
            )
        );
        // TODO - if the LI somehow has a claim attached to it, lineitem.delete
        //        current crashes
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }
        const ids = lis.map(x => Number(x.id()));
        this.deleteLineitemsDialog.ids = ids;
        this.deleteLineitemsDialog.open().subscribe(doIt => {
            if (!doIt) { return; }

            from(lis)
                .pipe(concatMap(li => {
                    const method = li.purchase_order() ?
                        'open-ils.acq.purchase_order.lineitem.delete' :
                        'open-ils.acq.picklist.lineitem.delete';

                    return this.net.request('open-ils.acq', method, this.auth.token(), li.id());
                // TODO: cap parallelism
                }))
                .pipe(concatMap(_ => of(true) ))
                .subscribe(r => {}, (err: unknown) => {}, () => {
                    this.lineItemsDeletedString.current()
                        .then(str => this.toast.success(str));
                    this.lineitemResultsGrid.reload();
                });
        });
    }

    exportSingleAttributeList(rows: IdlObject[]) {
        const ids = rows.map(x => Number(x.id()));
        this.exportAttributesDialog.ids = ids;
        this.exportAttributesDialog.open().subscribe(attr => {
            if (!attr) { return; }

            this.liService.doExportSingleAttributeList(ids, attr);
        });
    }

    linkInvoiceFromSelected(rows: IdlObject[]) {
        // must be attached to PO
        const lis = rows.filter(l => l.purchase_order());
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }

        this.linkInvoiceDialog.liIds = lis.map(i => Number(i.id()));
        this.linkInvoiceDialog.open().subscribe(invId => {
            if (!invId) { return; }

            const path = '/eg/staff/acq/legacy/invoice/view/' + invId + '?' +
                     lis.map(x => 'attach_li=' + x.id()).join('&');
            window.location.href = path;
        });
    }

    markOrderReady(rows: IdlObject[]) {
        const lis = rows.filter(l => l.state() === 'selector-ready' || l.state() === 'new');
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }
        const ids = lis.map(x => Number(x.id()));

        this.orderReadyConfirmDialog.open().subscribe(doIt => {
            if (!doIt) { return; }
            const lisToUpdate: IdlObject[] = [];
            this.liService.getFleshedLineitems(ids, { fromCache: true }).subscribe(
                liStruct => {
                    liStruct.lineitem.state('order-ready');
                    lisToUpdate.push(liStruct.lineitem);
                },
                (err: unknown) => { },
                () => {
                    this.net.request(
                        'open-ils.acq',
                        'open-ils.acq.lineitem.update',
                        this.auth.token(), lisToUpdate
                    ).toPromise().then(resp => {
                        this.lineItemsUpdatedString.current()
                            .then(str => this.toast.success(str));
                        this.lineitemResultsGrid.reload();
                    });
                }
            );
        });
    }

    markSelectorReady(rows: IdlObject[]) {
        const lis = rows.filter(l => l.state() === 'new');
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }
        const ids = lis.map(x => Number(x.id()));

        this.selectorReadyConfirmDialog.open().subscribe(doIt => {
            if (!doIt) { return; }
            const lisToUpdate: IdlObject[] = [];
            this.liService.getFleshedLineitems(ids, { fromCache: true }).subscribe(
                liStruct => {
                    liStruct.lineitem.state('selector-ready');
                    lisToUpdate.push(liStruct.lineitem);
                },
                (err: unknown) => { },
                () => {
                    this.net.request(
                        'open-ils.acq',
                        'open-ils.acq.lineitem.update',
                        this.auth.token(), lisToUpdate
                    ).toPromise().then(resp => {
                        this.lineItemsUpdatedString.current()
                            .then(str => this.toast.success(str));
                        this.lineitemResultsGrid.reload();
                    });
                }
            );
        });
    }

    markReceived(rows: IdlObject[]) {
        // must be on-order or cancelled
        const lis = rows.filter(l => l.state() === 'on-order' || l.state() === 'cancelled');
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }

        const ids = lis.map(x => Number(x.id()));

        this.liService.checkLiAlerts(lis, this.confirmAlertsDialog).then(ok => {
            this.net.request(
                'open-ils.acq',
                'open-ils.acq.lineitem.receive.batch',
                this.auth.token(), ids
            ).toPromise().then(resp => {
                this.lineItemsReceivedString.current()
                    .then(str => this.toast.success(str));
                this.lineitemResultsGrid.reload();
            });
        }, err => {}); // avoid console errors
    }

    markUnReceived(rows: IdlObject[]) {
        // must be received
        const lis = rows.filter(l => l.state() === 'received');
        if (lis.length === 0) {
            this.noActionableLIs.open();
            return;
        }

        const ids = lis.map(x => Number(x.id()));
        this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem.receive.rollback.batch',
            this.auth.token(), ids
        ).toPromise().then(resp => {
            this.lineItemsUnReceivedString.current()
                .then(str => this.toast.success(str));
            this.lineitemResultsGrid.reload();
        });
    }

}
