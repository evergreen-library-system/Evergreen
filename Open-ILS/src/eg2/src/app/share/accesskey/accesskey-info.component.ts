/**
 */
import {Component, Input, OnInit} from '@angular/core';
import {AccessKeyService} from '@eg/share/accesskey/accesskey.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

@Component({
  selector: 'eg-accesskey-info',
  templateUrl: './accesskey-info.component.html'
})
export class AccessKeyInfoComponent extends DialogComponent {

    constructor(
        private modal: NgbModal, // required for passing to parent
        private keyService: AccessKeyService) {
        super(modal);
    }

    assignments(): any[] {
        return this.keyService.infoIze();
    }
}


