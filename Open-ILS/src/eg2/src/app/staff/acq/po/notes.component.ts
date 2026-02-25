import { Component, AfterViewInit, Input, Output, EventEmitter, inject } from '@angular/core';
import {Observable} from 'rxjs';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

@Component({
    templateUrl: 'notes.component.html',
    selector: 'eg-po-notes',
    imports: [CommonModule, FormsModule]
})
export class PoNotesComponent implements AfterViewInit {
    private idl = inject(IdlService);
    private org = inject(OrgService);
    private auth = inject(AuthService);
    private net = inject(NetService);


    @Input() po: IdlObject;
    noteText: string;
    vendorPublic = false;

    @Output() closeRequested: EventEmitter<void> = new EventEmitter<void>();

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

    newNote() {
        const note = this.idl.create('acqpon');
        note.isnew(true);
        note.purchase_order(this.po.id());
        note.value(this.noteText || '');
        note.vendor_public(this.vendorPublic ? 't' : 'f');

        this.modifyNotes(note).subscribe(resp => {
            if (resp.note) {
                this.po.notes().unshift(resp.note);
            }
        });
    }

    deleteNote(note: IdlObject) {
        note.isdeleted(true);
        this.modifyNotes(note).toPromise().then(_ => {
            this.po.notes(
                this.po.notes().filter(n => n.id() !== note.id())
            );
        });
    }

    modifyNotes(notes: IdlObject | IdlObject[]): Observable<any> {
        notes = [].concat(notes);

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.po_note.cud.batch',
            this.auth.token(), notes);
    }
}

