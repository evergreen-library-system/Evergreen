import {Component, OnInit, AfterViewInit, ViewChild, Input, Output, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {ItemLocationService} from '@eg/share/item-location-select/item-location-select.service';
import {ItemLocationSelectComponent} from '@eg/share/item-location-select/item-location-select.component';

@Component({
  templateUrl: 'copy-attrs.component.html',
  selector: 'eg-lineitem-copy-attrs'
})
export class LineitemCopyAttrsComponent implements OnInit {

    @Input() lineitem: IdlObject;
    fundEntries: ComboboxEntry[];
    circModEntries: ComboboxEntry[];

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
        private loc: ItemLocationService,
        private liService: LineitemService
    ) {}

    ngOnInit() {

        if (this.batchMode) { // stub batch copy
            this.copy = this.idl.create('acqlid');
            this.copy.isnew(true);

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

        switch (field) {

            case 'cn_label':
            case 'barcode':
            case 'collection_code':
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

    // Tell our inputs about the values we know we need
    // Values will be pre-cached in the liService
    setInitialOptions(copy: IdlObject) {

        if (copy.fund()) {
            const fund = this.liService.fundCache[copy.fund()];
            this.fundEntries = [{id: fund.id(), label: fund.code(), fm: fund}];
        }

        if (copy.circ_modifier()) {
            const mod = this.liService.circModCache[copy.circ_modifier()];
            this.circModEntries = [{id: mod.code(), label: mod.name(), fm: mod}];
        }
    }

    fieldIsDisabled(field: string) {
        if (this.batchMode) { return false; }

        if (this.embedded || // inline expandy view
            this.copy.isdeleted() ||
            this.disposition() !== 'pre-order') {
            return true;
        }

        return false;
    }

    disposition(): 'canceled' | 'delayed' | 'received' | 'on-order' | 'pre-order' {
        if (!this.copy || !this.lineitem) {
            return null;
        } else if (this.copy.cancel_reason()) {
            if (this.copy.cancel_reason().keep_debits() === 't') {
                return 'delayed';
            } else {
                return 'canceled';
            }
        } else if (this.copy.recv_time()) {
            return 'received';
        } else if (this.lineitem.state() === 'on-order') {
            return 'on-order';
        } else { return 'pre-order'; }
    }
}


