import {Component, OnInit, AfterViewInit, OnDestroy, Input, ViewChild} from '@angular/core';
import {NgForm} from '@angular/forms';
import {EMPTY, from, Subscription} from 'rxjs';
import {Router, ActivatedRoute} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ProviderRecordService} from './provider-record.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';


@Component({
    selector: 'eg-provider-holdings',
    templateUrl: 'provider-holdings.component.html',
})
export class ProviderHoldingsComponent implements OnInit, AfterViewInit, OnDestroy {

    @Input() providerId: any;
    holdings: any[] = [];

    gridSource: GridDataSource;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('acqProviderHoldingsGrid', { static: true }) providerHoldingsGrid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('successTagString', { static: true }) successTagString: StringComponent;
    @ViewChild('updateFailedTagString', { static: false }) updateFailedTagString: StringComponent;
    @ViewChild('holdingTagForm', { static: false}) holdingTagForm: NgForm;

    cellTextGenerator: GridCellTextGenerator;
    provider: IdlObject;

    canCreate: boolean;
    canDelete: boolean;
    deleteSelected: (rows: IdlObject[]) => void;

    permissions: {[name: string]: boolean};

    subscription: Subscription;

    // Size of create/edito dialog.  Uses large by default.
    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private idl: IdlService,
        private providerRecord: ProviderRecordService,
        private toast: ToastService) {

    }

    ngOnInit() {
        this.gridSource = this.getDataSource();
        this.cellTextGenerator = {
            name: row => row.name(),
        };
        this.deleteSelected = (idlThings: IdlObject[]) => {
            idlThings.forEach(idlThing => idlThing.isdeleted(true));
            this.providerRecord.batchUpdate(idlThings).subscribe(
                { next: val => {
                    console.debug('deleted: ' + val);
                    this.deleteSuccessString.current()
                        .then(str => this.toast.success(str));
                }, error: (err: unknown) => {
                    this.deleteFailedString.current()
                        .then(str => this.toast.danger(str));
                }, complete: ()  => {
                    this.providerRecord.refreshCurrent().then(
                        () => this.providerHoldingsGrid.reload()
                    );
                } }
            );
        };
        this.providerHoldingsGrid.onRowActivate.subscribe(
            (idlThing: IdlObject) => this.showEditDialog(idlThing)
        );
        this.subscription = this.providerRecord.providerUpdated$.subscribe(
            id => {
                this.providerHoldingsGrid.reload();
            }
        );
    }

    ngAfterViewInit() {
        if (this.providerRecord.current()) {
            // sometimes needs to force a refresh in case we updated that tag,
            // navigated away (and confirmed that we wanted to abandon the change),
            // then navigated back
            this.providerRecord.current()['_holding_tag'] = this.providerRecord.current().holding_tag();
        }
    }

    ngOnDestroy() {
        this.subscription.unsubscribe();
    }

    updateProvider(providerId: any) {
        this.provider.holding_tag(this.provider._holding_tag);
        this.provider.ischanged(true);
        this.providerRecord.batchUpdate([this.provider]).subscribe(
            { next: val => {
                this.successTagString.current()
                    .then(str => this.toast.success(str));
            }, error: (err: unknown) => {
                this.updateFailedTagString.current()
                    .then(str => this.toast.danger(str));
            }, complete: ()  => {
                this.providerRecord.refreshCurrent().then(
                    () => { this.provider = this.providerRecord.current(); }
                );
            } }
        );
    }

    getDataSource(): GridDataSource {
        const gridSource = new GridDataSource();

        gridSource.getRows = (pager: Pager, sort: any[]) => {
            this.provider = this.providerRecord.current();
            if (!this.provider) {
                return EMPTY;
            }
            let holdings = this.provider.holdings_subfields();

            if (sort.length > 0) {
                holdings = holdings.sort((a, b) => {
                    for (let i = 0; i < sort.length; i++) {
                        let lt = -1;
                        const sfield = sort[i].name;
                        if (sort[i].dir.substring(0, 1).toLowerCase() === 'd') {
                            lt *= -1;
                        }
                        if (a[sfield]() < b[sfield]()) { return lt; }
                        if (a[sfield]() > b[sfield]()) { return lt * -1; }
                    }
                    return 0;
                });

            }

            return from(holdings.slice(pager.offset, pager.offset + pager.limit));
        };
        return gridSource;
    }

    showEditDialog(providerHolding: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = providerHolding['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
                { next: result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.providerRecord.refreshCurrent().then(
                        () => this.providerHoldingsGrid.reload()
                    );
                    resolve(result);
                }, error: (error: unknown) => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                } }
            );
        });
    }

    editSelected(providerHoldingsFields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (providerHoldings: IdlObject) => {
            if (!providerHoldings) { return; }

            this.showEditDialog(providerHoldings).then(
                () => editOneThing(providerHoldingsFields.shift()));
        };

        editOneThing(providerHoldingsFields.shift());
    }

    createNew() {
        this.editDialog.mode = 'create';
        const holdings = this.idl.create('acqphsm');
        holdings.provider(this.provider.id());
        this.editDialog.record = holdings;
        this.editDialog.recordId = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
            { next: ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.providerRecord.refreshCurrent().then(
                    () => this.providerHoldingsGrid.reload()
                );
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            } }
        );
    }

    isDirty(): boolean {
        return (this.providerRecord.current()['_holding_tag'] === this.providerRecord.current().holding_tag()) ? false :
            (this.holdingTagForm && this.holdingTagForm.dirty) ? this.holdingTagForm.dirty : false;
    }
}
