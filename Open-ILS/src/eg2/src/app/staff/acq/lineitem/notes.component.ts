import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter} from '@angular/core';
import {Observable} from 'rxjs';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    templateUrl: 'notes.component.html',
    selector: 'eg-lineitem-notes'
})
export class LineitemNotesComponent implements OnInit, AfterViewInit {

    @Input() lineitem: IdlObject;
    noteText: string;
    alertComments: string;
    vendorPublic = false;
    alertEntry: ComboboxEntry;
    owners: number[];

    @Output() closeRequested: EventEmitter<void> = new EventEmitter<void>();

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private net: NetService
    ) {}

    ngOnInit() {
        this.owners = this.org.ancestors(this.auth.user().ws_ou(), true);
    }

    ngAfterViewInit() {
        const node = document.getElementById('note-text-input');
        if (node) { node.focus(); }
    }

    orgSn(id: number): string {
        return this.org.get(id).shortname();
    }

    close() {
        this.closeRequested.emit();
    }

    newNote(isAlert?: boolean) {
        const note = this.idl.create('acqlin');
        note.isnew(true);
        note.lineitem(this.lineitem.id());
        if (isAlert) {
            note.value(this.alertComments || '');
            note.alert_text(this.alertEntry.id);
        } else {
            note.value(this.noteText || '');
            note.vendor_public(this.vendorPublic ? 't' : 'f');
        }

        this.modifyNotes(note).subscribe(resp => {
            if (resp.note) {
                this.lineitem.lineitem_notes().unshift(resp.note);
            }
        });
    }

    deleteNote(note: IdlObject) {
        note.isdeleted(true);
        this.modifyNotes(note).toPromise().then(_ => {
            this.lineitem.lineitem_notes(
                this.lineitem.lineitem_notes().filter(n => n.id() !== note.id())
            );
        });
    }

    modifyNotes(notes: IdlObject | IdlObject[]): Observable<any> {
        notes = [].concat(notes);

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem_note.cud.batch',
            this.auth.token(), notes);
    }
}

