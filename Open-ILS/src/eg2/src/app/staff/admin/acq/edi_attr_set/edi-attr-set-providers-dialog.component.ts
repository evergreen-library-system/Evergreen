import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgForm} from '@angular/forms';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {PermService} from '@eg/core/perm.service';
import {EdiAttrSetProvidersComponent} from './edi-attr-set-providers.component';

@Component({
  selector: 'eg-edi-attr-set-providers-dialog',
  templateUrl: './edi-attr-set-providers-dialog.component.html'
})

export class EdiAttrSetProvidersDialogComponent
  extends DialogComponent implements OnInit {

    @Input() attrSetId: number;

    constructor(
        private idl: IdlService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private perm: PermService,
        private toast: ToastService,
        private modal: NgbModal
    ) {
        super(modal);
    }

    ngOnInit() { }

}
