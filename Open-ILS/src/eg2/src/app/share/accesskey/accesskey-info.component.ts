/**
 */
import { Component, ViewEncapsulation, inject } from '@angular/core';
import {AccessKeyService} from '@eg/share/accesskey/accesskey.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { NgbModalOptions } from '@ng-bootstrap/ng-bootstrap';
import { BoolDisplayComponent } from '../util/bool.component';

@Component({
    selector: 'eg-accesskey-info',
    templateUrl: './accesskey-info.component.html',
    styleUrls: ['accesskey-info.component.css'],
    encapsulation: ViewEncapsulation.None,
    imports: [BoolDisplayComponent]
})
export class AccessKeyInfoComponent extends DialogComponent {
    private keyService = inject(AccessKeyService);
    protected assignments: ReturnType<AccessKeyService['infoIze']> = [];

    open(args?: NgbModalOptions): ReturnType<DialogComponent['open']> {
        this.assignments = this.keyService.infoIze();
        return super.open(args);
    }
}


