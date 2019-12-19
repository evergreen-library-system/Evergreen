import {Component, Input, Output, OnInit, EventEmitter} from '@angular/core';
import {Observable} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalRef, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {MarcEditContext} from './editor-context';


/**
 * Spawn a MARC editor within a dialog.
 */

@Component({
  selector: 'eg-marc-editor-dialog',
  templateUrl: './editor-dialog.component.html'
})

export class MarcEditorDialogComponent
    extends DialogComponent implements OnInit {

    @Input() context: MarcEditContext;
    @Input() recordXml: string;
    @Input() recordType: 'biblio' | 'authority' = 'biblio';

    constructor(
        private modal: NgbModal,
        private auth: AuthService,
        private org: OrgService,
        private pcrud: PcrudService,
        private net: NetService) {
        super(modal);
    }

    ngOnInit() {}

    handleRecordSaved(saved) {
        this.close(saved);
    }
}


