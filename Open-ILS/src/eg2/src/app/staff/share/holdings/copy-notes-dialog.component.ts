import {Component, Input, ViewChild} from '@angular/core';
import {Observable, throwError, from, empty} from 'rxjs';
import {switchMap} from 'rxjs/operators';
import {NetService} from '@eg/core/net.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {StringComponent} from '@eg/share/string/string.component';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

/**
 * Dialog for managing copy notes.
 */

export interface CopyNotesChanges {
    newNotes: IdlObject[];
    delNotes: IdlObject[];
}

@Component({
    selector: 'eg-copy-notes-dialog',
    templateUrl: 'copy-notes-dialog.component.html'
})

export class CopyNotesDialogComponent
    extends DialogComponent {

    // If there are multiple copyIds, only new notes may be applied.
    // If there is only one copyId, then notes may be applied or removed.
    @Input() copyIds: number[] = [];

    mode: string; // create | manage | edit

    // If true, no attempt is made to save the new notes to the
    // database.  It's assumed this takes place in the calling code.
    @Input() inPlaceCreateMode = false;

    // In 'create' mode, we may be adding notes to multiple copies.
    copies: IdlObject[] = [];

    // In 'manage' mode we only handle a single copy.
    copy: IdlObject;

    curNote: string;
    curNoteTitle: string;
    curNotePublic = false;
    newNotes: IdlObject[] = [];
    delNotes: IdlObject[] = [];

    autoId = -1;

    idToEdit: number;

    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private org: OrgService,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    /**
     */
    open(args: NgbModalOptions): Observable<CopyNotesChanges> {
        this.copy = null;
        this.copies = [];
        this.newNotes = [];
        this.delNotes = [];

        if (this.copyIds.length === 0 && !this.inPlaceCreateMode) {
            return throwError('copy ID required');
        }

        // In manage mode, we can only manage a single copy.
        // But in create mode, we can add notes to multiple copies.
        // We can only manage copies that already exist in the database.
        if (this.copyIds.length === 1 && this.copyIds[0] > 0) {
            this.mode = 'manage';
        } else {
            this.mode = 'create';
        }

        // Observify data loading
        const obs = from(this.getCopies());

        // Return open() observable to caller
        return obs.pipe(switchMap(_ => super.open(args)));
    }

    getCopies(): Promise<any> {

        // Avoid fetch if we're only adding notes to isnew copies.
        const ids = this.copyIds.filter(id => id > 0);
        if (ids.length === 0) { return Promise.resolve(); }

        return this.pcrud.search('acp', {id: this.copyIds},
            {flesh: 1, flesh_fields: {acp: ['notes']}},
            {atomic: true}
        )
            .toPromise().then(copies => {
                this.copies = copies;
                if (copies.length === 1) {
                    this.copy = copies[0];
                }
            });
    }

    editNote(note: IdlObject) {
        this.idToEdit = note.id();
        this.mode = 'edit';
    }

    returnToManage() {
        this.getCopies().then(() => {
            this.idToEdit = null;
            this.mode = 'manage';
        });
    }

    removeNote(note: IdlObject) {
        this.newNotes = this.newNotes.filter(t => t.id() !== note.id());

        if (note.isnew() || this.mode === 'create') { return; }

        const existing = this.copy.notes().filter(n => n.id() === note.id())[0];
        if (!existing) { return; }

        existing.isdeleted(true);
        this.delNotes.push(existing);

        // Remove from copy for dialog display
        this.copy.notes(this.copy.notes().filter(n => n.id() !== note.id()));
    }

    addNew() {
        if (!this.curNoteTitle || !this.curNote) { return; }

        const note = this.idl.create('acpn');
        note.isnew(true);
        note.creator(this.auth.user().id());
        note.pub(this.curNotePublic ? 't' : 'f');
        note.title(this.curNoteTitle);
        note.value(this.curNote);
        note.id(this.autoId--);

        this.newNotes.push(note);

        this.curNote = '';
        this.curNoteTitle = '';
        this.curNotePublic = false;
    }

    applyChanges() {

        if (this.inPlaceCreateMode) {
            this.close({ newNotes: this.newNotes, delNotes: this.delNotes });
            return;
        }

        const notes = [];
        this.newNotes.forEach(note => {
            this.copies.forEach(copy => {
                const n = this.idl.clone(note);
                n.id(null); // remove temp ID, it will be duped
                n.owning_copy(copy.id());
                notes.push(n);
            });
        });

        this.pcrud.create(notes).toPromise()
            .then(_ => {
                if (this.delNotes.length) {
                    return this.pcrud.remove(this.delNotes).toPromise();
                }
            }).then(_ => {
                this.successMsg.current().then(msg => this.toast.success(msg));
                this.close({ newNotes: this.newNotes, delNotes: this.delNotes });
            });
    }
}

