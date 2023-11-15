import {Component, OnInit, Input, Output, ViewChild, EventEmitter} from '@angular/core';
import {Observable, Observer, of} from 'rxjs';
import {tap} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

/** New hold note dialog */

@Component({
    selector: 'eg-hold-note-dialog',
    templateUrl: 'note-dialog.component.html'
})
export class HoldNoteDialogComponent extends DialogComponent {
    pub = false;
    slip = false;
    title: string;
    body: string;

    @Input() holdId: number;

    constructor(
        private modal: NgbModal,
        private idl: IdlService,
        private pcrud: PcrudService
    ) { super(modal); }

    createNote() {
        const note = this.idl.create('ahrn');
        note.staff('t');
        note.hold(this.holdId);
        note.title(this.title);
        note.body(this.body);
        note.slip(this.slip ? 't' : 'f');
        note.pub(this.pub ? 't' : 'f');

        this.pcrud.create(note).toPromise().then(
            resp => this.close(resp), // new note object
            err => console.error('Could not create note', err)
        );
    }
}


