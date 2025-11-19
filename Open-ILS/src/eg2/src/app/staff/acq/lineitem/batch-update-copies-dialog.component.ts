import {Component, Input} from '@angular/core';
import {Observable} from 'rxjs';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {LineitemCopyAttrsComponent} from './copy-attrs.component';

@Component({
    selector: 'eg-acq-batch-update-copies-dialog',
    templateUrl: './batch-update-copies-dialog.component.html'
})

export class BatchUpdateCopiesDialogComponent extends DialogComponent {

    @Input() ids: number[];

    copyCount = '';
    selectedFormula: ComboboxEntry;
    formulaFilter = {owner: []};
    templateCopy: IdlObject;

    constructor(
        private modal: NgbModal,
        private org: OrgService,
        private auth: AuthService
    ) {
        super(modal);
    }

    open(args?: NgbModalOptions): Observable<any> {
        if (!args) {
            args = {};
        }

        this.copyCount = '';
        this.selectedFormula = null;
        this.formulaFilter.owner =
            this.org.fullPath(this.auth.user().ws_ou(), true);

        return super.open(args);
    }

    canApply(): boolean {
        if (!this.templateCopy) { return false; }

        const _copyCount = parseInt(this.copyCount, 10);
        if ((_copyCount && _copyCount > 0) ||
            this.selectedFormula?.id ||
            this.templateCopy.owning_lib() ||
            this.templateCopy.location() ||
            this.templateCopy.collection_code() ||
            this.templateCopy.fund() ||
            this.templateCopy.circ_modifier() ||
            this.templateCopy.note()) {
            return true;
        } else {
            return false;
        }
    }

    compileBatchChange(): any {
        const changes = {
            _dist_formula: this.selectedFormula?.id
        };
        const _copyCount = parseInt(this.copyCount, 10);
        if (_copyCount && _copyCount > 0) {
            changes['item_count'] = _copyCount;
        }
        if (this.templateCopy.owning_lib()) {
            changes['owning_lib'] = this.templateCopy.owning_lib();
        }
        if (this.templateCopy.location()) {
            changes['location'] = this.templateCopy.location();
        }
        if (this.templateCopy.collection_code()) {
            changes['collection_code'] = this.templateCopy.collection_code();
        }
        if (this.templateCopy.fund()) {
            changes['fund'] = this.templateCopy.fund();
        }
        if (this.templateCopy.circ_modifier()) {
            changes['circ_modifier'] = this.templateCopy.circ_modifier();
        }
        if (this.templateCopy.note()) {
            changes['note'] = this.templateCopy.note();
        }
        return changes;
    }

}


