/* eslint-disable eqeqeq, no-magic-numbers */
import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {PermService} from '@eg/core/perm.service';

@Component({
    selector: 'eg-distribution-formula-edit-dialog',
    templateUrl: './distribution-formula-edit-dialog.component.html'
})

export class DistributionFormulaEditDialogComponent
    extends DialogComponent implements OnInit {

    @Input() mode = 'create';
    @Input() formulaId: number;
    @Input() cloneSource: number;

    @ViewChild('defaultCloneLabel', { static: true }) defaultCloneLabel: StringComponent;
    formula: IdlObject;
    deadEntries: IdlObject[];
    clonedLabel = '';

    constructor(
        private idl: IdlService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private org: OrgService,
        private pcrud: PcrudService,
        private perm: PermService,
        private toast: ToastService,
        private modal: NgbModal
    ) {
        super(modal);
    }

    ngOnInit() {
        this.onOpen$.subscribe(() => this._initRecord());
    }

    private _initRecord() {
        this.formula = null;
        this.deadEntries = [];
        this.clonedLabel = '';
        if (this.mode === 'update') {
            this.pcrud.retrieve('acqdf', this.formulaId, {
                flesh: 1,
                flesh_fields: { acqdf: ['entries'] }
            }).subscribe(res => {
                this.formula = res;
                this._generateFormulaInputs();
            });
        } else if (this.mode === 'clone') {
            this.pcrud.retrieve('acqdf', this.cloneSource, {
                flesh: 1,
                flesh_fields: { acqdf: ['entries'] }
            }).subscribe(res => {
                this.clonedLabel = res.name();
                this.formula = this.idl.clone(res);
                this.formula.id(null);
                this.defaultCloneLabel.current().then(str => this.formula.name(str));
                this.formula.entries().forEach((e) => e.formula(null));
                this._generateFormulaInputs();
            });
        } else if (this.mode === 'create') {
            this.formula = this.idl.create('acqdf');
            this.formula.entries([]);
            this._generateFormulaInputs();
        }
    }

    _generateFormulaInputs() {
        this.formula.entries().sort((a, b) => a.position() < b.position() ? -1 : 1 );
        const entry = this.idl.create('acqdfe');
        entry.id(-9999); // magic placeholder for new record
        this.formula.entries().push(entry);
    }

    org_root(): number {
        return this.org.root().id();
    }

    addRow() {
        if (this.formula.entries().slice(-1)[0].id() === -9999) {
            this.formula.entries().slice(-1)[0].id(-1); // magic placheholder for new entry that we intend to keep
        }
        const entry = this.idl.create('acqdfe');
        entry.id(-9999); // magic placeholder for new record
        this.formula.entries().push(entry);
    }
    removeRow(idx: number) {
        this.deadEntries.push(this.formula.entries().splice(idx, 1)[0]);
    }
    moveUp(idx: number) {
        const temp = this.formula.entries()[idx - 1];
        this.formula.entries()[idx - 1] = this.formula.entries()[idx];
        this.formula.entries()[idx] = temp;
    }
    moveDown(idx: number) {
        const temp = this.formula.entries()[idx + 1];
        this.formula.entries()[idx + 1] = this.formula.entries()[idx];
        this.formula.entries()[idx] = temp;
    }


    save() {
        // grab a copy to preserve the list of entries
        const formulaCopy = this.idl.clone(this.formula);
        if (this.formula.id() === undefined || this.formula.id() === null) {
            this.formula.isnew(true);
            this.formula.owner(this.formula.owner().id());
        } else {
            this.formula.ischanged(true);
        }
        this.pcrud.autoApply([this.formula]).subscribe({ next: res => {
            const dfId = this.mode === 'update' ? res : res.id();
            const updates: IdlObject[] = [];
            if (this.mode === 'create' || this.mode === 'clone') {
                formulaCopy.entries().forEach((entry, idx) => {
                    if (entry.id() === -1) { entry.id(null); }
                    if (entry.id() === -9999) { entry.id(null); }
                    if (entry.item_count() == null) {
                        // we got nothing; ignore
                        return;
                    }
                    if (entry.owning_lib() == null &&
                        entry.fund() == null &&
                        entry.location() == null &&
                        entry.circ_modifier() == null &&
                        entry.collection_code() == null
                    ) {
                        // this is a pointless entry; ignore
                        return;
                    }

                    entry.formula(dfId);
                    if (entry.owning_lib()) { entry.owning_lib(entry.owning_lib().id()); }
                    entry.id(null);
                    entry.position(idx); // re-writing all the positions
                    entry.isnew(true);
                    updates.push(entry);
                });
            } else {
                // updating an existing set
                formulaCopy.entries().forEach((entry, idx) => {
                    if (entry.id() === -1) { entry.id(null); }
                    if (entry.id() === -9999) { entry.id(null); }
                    if (entry.id()) {
                        entry.formula(dfId);
                        entry.position(idx);
                        if (entry.owning_lib()) { entry.owning_lib(entry.owning_lib().id()); }
                        const delEntry = this.idl.clone(entry);
                        // have to delete and recreate because of the
                        // check constraint on formula, position
                        this.deadEntries.push(delEntry);
                        entry.isnew(true);
                        updates.push(entry);
                    } else {
                        if (entry.item_count() == null) {
                            // we got nothing; ignore
                            return;
                        }
                        if (entry.owning_lib() == null &&
                            entry.fund() == null &&
                            entry.location() == null &&
                            entry.circ_modifier() == null &&
                            entry.collection_code() == null
                        ) {
                            // this is a pointless entry; ignore
                            return;
                        }

                        entry.formula(dfId);
                        if (entry.owning_lib()) { entry.owning_lib(entry.owning_lib().id()); }
                        entry.position(idx); // re-writing all the positions
                        entry.isnew(true);
                        updates.push(entry);
                    }
                });
            }
            this.deadEntries.forEach((entry) => {
                if (entry.id()) {
                    entry.isdeleted(true);
                    updates.unshift(entry); // deletions have to be processed first
                }
            });
            // eslint-disable-next-line rxjs-x/no-nested-subscribe
            this.pcrud.autoApply(updates).subscribe(
                { next: ret => {}, error: (err: unknown) => this.close(err), complete: () => this.close(true) }
            );
        }, error: (err: unknown) => this.close(false) });
    }

}
