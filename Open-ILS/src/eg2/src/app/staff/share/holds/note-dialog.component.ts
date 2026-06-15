import { Component, Input, inject } from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { FormsModule } from '@angular/forms';
import { lastValueFrom } from 'rxjs';

/** New hold note dialog */

@Component({
    selector: 'eg-hold-note-dialog',
    templateUrl: 'note-dialog.component.html',
    imports: [
        FormsModule,
    ]
})
export class HoldNoteDialogComponent extends DialogComponent {
    private idl = inject(IdlService);
    private pcrud = inject(PcrudService);

    pub = false;
    slip = false;
    title: string;
    body: string;

    @Input() holdId: number;

    createNote() {
        const note = this.idl.create('ahrn');
        note.staff('t');
        note.hold(this.holdId);
        note.title(this.title);
        note.body(this.body);
        note.slip(this.slip ? 't' : 'f');
        note.pub(this.pub ? 't' : 'f');

        lastValueFrom(this.pcrud.create(note)).then(
            resp => this.close(resp), // new note object
            err => console.error('Could not create note', err)
        );
    }
}


