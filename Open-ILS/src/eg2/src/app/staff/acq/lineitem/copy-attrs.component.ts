import {Component, OnInit, AfterViewInit, ViewChild, Input, Output, EventEmitter} from '@angular/core';
import {tap} from 'rxjs';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {LineitemService, COPY_ORDER_DISPOSITION} from './lineitem.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {ItemLocationService} from '@eg/share/item-location-select/item-location-select.service';
import {ItemLocationSelectComponent} from '@eg/share/item-location-select/item-location-select.component';
import {PermService} from '@eg/core/perm.service';

@Component({
    templateUrl: 'copy-attrs.component.html',
    styleUrls: ['copy-attrs.component.css'],
    selector: 'eg-lineitem-copy-attrs'
})
export class LineitemCopyAttrsComponent implements OnInit {

    @Input() lineitem: IdlObject;
    @Input() rowIndex: number;
    @Input() batchAdd = false;
    @Input() gatherParamsOnly = false;
    @Input() hideBarcode = false;

    @Output() becameDirty = new EventEmitter<Boolean>();
    @Output() templateCopy = new EventEmitter<IdlObject>();

    fundEntries: ComboboxEntry[];
    _fundBalanceCache: string[] = [];
    _inflight: Promise<string>[] = [];
    circModEntries: ComboboxEntry[];
    owners: number[] = [];

    private _copy: IdlObject;
    @Input() set copy(c: IdlObject) { // acqlid
        if (c === undefined) {
            return;
        } else if (c === null) {
            this._copy = null;
        } else {
            // Enture cbox entries are populated before the copy is
            // applied so the cbox has the minimal set of values it
            // needs at copy render time.
            this.setInitialOptions(c);
            this._copy = c;
        }
    }

    get copy(): IdlObject {
        return this._copy;
    }

    // A row of batch edit inputs
    @Input() batchMode = false;

    // One of several rows embedded in the main LI list page.
    // Always read-only.
    @Input() embedded = false;

    @Input() showReceiver = false;
    @Input() showReceivedTime = false;

    // Emits an 'acqlid' object;
    @Output() batchApplyRequested: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();
    @Output() deleteRequested: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();
    @Output() receiveRequested: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();
    @Output() unReceiveRequested: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();
    @Output() cancelRequested: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();

    @ViewChild('locationSelector') locationSelector: ItemLocationSelectComponent;
    @ViewChild('circModSelector') circModSelector: ComboboxComponent;
    @ViewChild('fundSelector') fundSelector: ComboboxComponent;

    constructor(
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private org: OrgService,
        private loc: ItemLocationService,
        private liService: LineitemService,
        private perm: PermService
    ) {}

    ngOnInit() {

        this.perm.hasWorkPermAt(['MANAGE_FUND','CREATE_PURCHASE_ORDER','CREATE_PICKLIST'],true).then((perm) => {
            this.owners.concat(perm['MANAGE_FUND']);

            perm['CREATE_PURCHASE_ORDER'].forEach(ou => {
                if(!this.owners.includes(ou)) {
                    this.owners.push(ou);
                }
            });

            perm['CREATE_PICKLIST'].forEach(ou => {
                if(!this.owners.includes(ou)) {
                    this.owners.push(ou);
                }
            });
        });


        if (this.gatherParamsOnly) {
            this.batchMode = false;
            this.batchAdd = false;
        }

        if (this.batchMode || this.gatherParamsOnly) { // stub batch copy
            this.copy = this.idl.create('acqlid');
            this.copy.isnew(true);
            this.templateCopy.emit(this.copy);
        } else {

            // When a batch selector value changes, duplicate the selected
            // value into our selector entries, so if/when the value is
            // chosen we (and our pile of siblings) are not required to
            // re-fetch them from the server.
            this.liService.batchOptionWanted.subscribe(option => {
                const field = Object.keys(option)[0];
                if (field === 'location') {
                    this.locationSelector.comboBox.addAsyncEntry(option[field]);
                } else if (field === 'circ_modifier') {
                    this.circModSelector.addAsyncEntry(option[field]);
                } else if (field === 'fund') {
                    this.fundSelector.addAsyncEntry(option[field]);
                }
            });
        }
    }

    valueChange(field: string, entry: ComboboxEntry) {

        const announce: any = {};
        this.copy.ischanged(true);
        if (!this.batchMode) {
            if (field !== 'owning_lib') {
                this.becameDirty.emit(true);
            } else {
                // FIXME eg-org-select current send needless change
                //       events, so we need to check
                if (entry && this.copy[field]() !== entry.id()) {
                    this.becameDirty.emit(true);
                }
            }
        }

        switch (field) {

            case 'cn_label':
            case 'barcode':
            case 'collection_code':
            case 'note':
                this.copy[field](entry);
                break;

            case 'owning_lib':
                this.copy[field](entry ? entry.id() : null);
                break;

            case 'location':
                this.copy[field](entry ? entry.id() : null);
                if (this.batchMode) {
                    announce[field] = entry;
                    this.liService.batchOptionWanted.emit(announce);
                }
                break;

            case 'circ_modifier':
            case 'fund':
                this.copy[field](entry ? entry.id : null);
                if (this.batchMode) {
                    announce[field] = entry;
                    this.liService.batchOptionWanted.emit(announce);
                }
                break;
        }
    }

    // copied from combobox to get the label right for funds
    getOrgShortname(ou: any) {
        if (typeof ou === 'object') {
            return ou.shortname();
        } else {
            return this.org.get(ou).shortname();
        }
    }

    // Tell our inputs about the values we know we need
    // Values will be pre-cached in the liService
    //
    // TODO: figure out a better way to do this so that we
    //       don't need to duplicate the code to format
    //       the display labels for funds correctly
    setInitialOptions(copy: IdlObject) {

        if (copy.fund()) {
            const fund = this.liService.fundCache[copy.fund()];
            this.fundEntries = [{
                id: fund.id(),
                label: fund.code() + ' (' + fund.year() + ')' +
                       ' (' + this.getOrgShortname(fund.org()) + ')',
                fm: fund,
                class: 'fund-balance-state-' + fund['_balance']
            }];
        }

        if (copy.circ_modifier()) {
            const mod = this.liService.circModCache[copy.circ_modifier()];
            this.circModEntries = [{id: mod.code(), label: mod.name(), fm: mod}];
        }
    }

    checkFundBalance(fundId: number): string {
        if (this.liService.fundCache[fundId] && this.liService.fundCache[fundId]._balance) {
            return this.liService.fundCache[fundId]._balance;
        }
        if (this._fundBalanceCache[fundId]) {
            return this._fundBalanceCache[fundId];
        }
        if (this._inflight[fundId]) {
            return 'ok';
        }
        this._inflight[fundId] = this.net.request(
            'open-ils.acq',
            'open-ils.acq.fund.check_balance_percentages',
            this.auth.token(), fundId
        ).toPromise().then(r => {
            if (r[0]) {
                this._fundBalanceCache[fundId] = 'stop';
            } else if (r[1]) {
                this._fundBalanceCache[fundId] = 'warning';
            } else {
                this._fundBalanceCache[fundId] = 'ok';
            }
            if (this.liService.fundCache[fundId]) {
                this.liService.fundCache[fundId]['_balance'] = this._fundBalanceCache[fundId];
            }
            delete this._inflight[fundId];
            return this._fundBalanceCache[fundId];
        });
    }

    fieldIsDisabled(field: string) {
        if (this.batchMode) { return false; }
        if (this.gatherParamsOnly) { return false; }

        // Ignore disposition for notes - can be edited even after ordering or receiving.
        // Notes still can't be edited while component is embedded because we don't have a save button
        if (field === 'note' && !this.embedded && !this.copy.isdeleted()) {
            return false;
        }

        if (this.embedded || // inline expandy view
            this.copy.isdeleted() ||
            this.disposition() !== 'pre-order') {
            return true;
        }

        return false;
    }

    disposition(): COPY_ORDER_DISPOSITION {
        return this.liService.copyDisposition(this.lineitem, this.copy);
    }
}


