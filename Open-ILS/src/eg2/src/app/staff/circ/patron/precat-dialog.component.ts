import {Component, OnInit, Input} from '@angular/core';
import {Observable} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {PermService} from '@eg/core/perm.service';

/**
 * Precat checkout dialog
 */

@Component({
  selector: 'eg-precat-checkout-dialog',
  templateUrl: 'precat-dialog.component.html'
})

export class PrecatCheckoutDialogComponent extends DialogComponent implements OnInit {

    @Input() barcode = '';

    circModifier: ComboboxEntry;
    hasPerm = false;

    constructor(
        private perm: PermService,
        private modal: NgbModal) {
        super(modal);
    }

    ngOnInit() {
        this.perm.hasWorkPermHere('CREATE_PRECAT')
        .then(perms => this.hasPerm = perms['CREATE_PRECAT']);
    }
}



