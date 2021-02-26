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

    values = {
        dummy_title: null,
        dummy_author: null,
        dummy_isbn: null,
        circ_modifier: null
    };

    constructor(
        private perm: PermService,
        private modal: NgbModal) {
        super(modal);
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {

            this.values.dummy_title = null;
            this.values.dummy_author = null;
            this.values.dummy_isbn = null;
            this.values.circ_modifier = null;

            this.perm.hasWorkPermHere('CREATE_PRECAT')
            .then(perms => this.hasPerm = perms['CREATE_PRECAT']);

            setTimeout(() => {
                const node = document.getElementById('precat-title-input');
                if (node) { node.focus(); }
            });
        });
    }
}



