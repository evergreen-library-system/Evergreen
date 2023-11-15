import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-acq-claim-policy-dialog',
    templateUrl: './claim-policy-dialog.component.html'
})

export class ClaimPolicyDialogComponent extends DialogComponent {
    @Input() ids: number[];
    claimPolicy: number;
    constructor(private modal: NgbModal) { super(modal); }
}
