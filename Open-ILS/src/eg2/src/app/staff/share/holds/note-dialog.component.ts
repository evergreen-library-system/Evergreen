import { Component, Input, inject, viewChild } from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import { FormsModule } from '@angular/forms';
import { OpChangeComponent } from '../op-change/op-change.component';
import { lastValueFrom, switchMap } from 'rxjs';

/** New hold note dialog */

@Component({
    selector: 'eg-hold-note-dialog',
    templateUrl: 'note-dialog.component.html',
    imports: [
        FormsModule,
        OpChangeComponent
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
    opChange = viewChild.required<OpChangeComponent>('opChange');

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
            (err: string) => {
                if (err.includes('permissions')) {
                    this.opChange().open()
                        .pipe(switchMap(() => this.pcrud.create(note)))
                        .subscribe(elevatedResp => this.close(elevatedResp));
                } else {
                    console.error('Could not create note', err);
                }
            }
        );
    }
}


