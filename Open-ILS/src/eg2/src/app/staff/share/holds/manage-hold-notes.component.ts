import { Component, inject, input, signal } from '@angular/core';
import { HoldNotesService } from './hold-notes.service';
import { rxResource } from '@angular/core/rxjs-interop';
import { DialogComponent } from '@eg/share/dialog/dialog.component';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { ToastService } from '@eg/share/toast/toast.service';

@Component({
    imports: [ReactiveFormsModule],
    selector: 'eg-manage-hold-notes',
    templateUrl: './manage-hold-notes.component.html',
})
export class ManageHoldNotesComponent extends DialogComponent {
    holdId = input<number>();
    newNoteForm = new FormGroup({
        pub: new FormControl(false),
        slip: new FormControl(false),
        title: new FormControl(''),
        body: new FormControl('')
    });

    showCreateForm = signal(false);

    protected notes = rxResource({
        stream: ({params}) => this.notesService.getNotes(params.holdId),
        params: () => {return {holdId: this.holdId()};}
    });

    private idlService = inject(IdlService);
    private notesService = inject(HoldNotesService);
    private toastService = inject(ToastService);

    protected create() {
        const note = this.idlService.create('ahrn');
        note.hold(this.holdId());
        note.staff('T');
        note.pub(this.newNoteForm.get('pub').value ? 'T' : 'F');
        note.slip(this.newNoteForm.get('slip').value ? 'T' : 'F');
        note.title(this.newNoteForm.get('title').value);
        note.body(this.newNoteForm.get('body').value);
        this.notesService.addNote(note).subscribe(() => {
            this.toastService.success($localize`Created note`);
            this.notes.reload();
        });
        this.showCreateForm.set(false);
        this.newNoteForm.reset();
    }

    protected delete(note: IdlObject) {
        this.notesService.deleteNote(note).subscribe(() => {
            this.toastService.success($localize`Removed note`);
            this.notes.reload();
        });
    }
}
