/**
 */
import { Component, ViewEncapsulation, inject } from '@angular/core';
import {AccessKeyService} from '@eg/share/accesskey/accesskey.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import { BoolDisplayComponent } from '../util/bool.component';

@Component({
    selector: 'eg-accesskey-info',
    templateUrl: './accesskey-info.component.html',
    styleUrls: ['accesskey-info.component.css'],
    encapsulation: ViewEncapsulation.None,
    imports: [BoolDisplayComponent]
})
export class AccessKeyInfoComponent extends DialogComponent {
    private modal: NgbModal;
    private keyService = inject(AccessKeyService);


    constructor() {
        const modal = inject(NgbModal);

        super(modal);

        this.modal = modal;
    }

    assignments(): any[] {
        return this.keyService.infoIze();
    }
}


