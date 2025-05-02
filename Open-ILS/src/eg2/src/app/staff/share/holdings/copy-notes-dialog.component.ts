/* eslint-disable max-len */
import { Component, Input } from '@angular/core';
import { IdlService, IdlObject } from '@eg/core/idl.service';
import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { ToastService } from '@eg/share/toast/toast.service';
import { AuthService } from '@eg/core/auth.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { OrgService } from '@eg/core/org.service';
import {VolCopyContext} from '@eg/staff/cat/volcopy/volcopy';
import {
    CopyThingsDialogComponent,
    IThingObject,
    IThingChanges,
    IThingConfig
} from './copy-things-dialog.component';
import {FormsModule, AbstractControl, NG_VALIDATORS, ValidationErrors, Validator, Validators, ValidatorFn} from '@angular/forms';

export interface ICopyNote extends IThingObject {
    title(val?: string): string;
    value(val?: string): string;
    pub(val?: boolean): boolean;
    creator(val?: number): number;
    create_date(val?: any): any;
    owning_copy(val?: number): number;
}

interface ProxyNote extends ICopyNote {
    originalNoteIds: number[];
}
export interface ICopyNoteChanges extends IThingChanges<ICopyNote> {
    newThings: ICopyNote[];
    changedThings: ICopyNote[];
    deletedThings: ICopyNote[];
}

@Component({
    selector: 'eg-copy-notes-dialog',
    templateUrl: 'copy-notes-dialog.component.html',
    styleUrls: ['./copy-notes-dialog.component.css']
})
export class CopyNotesDialogComponent extends
    CopyThingsDialogComponent<ICopyNote, ICopyNoteChanges> {

    protected thingType = 'notes';
    protected successMessage = $localize`Successfully Modified Item Notes`;
    protected errorMessage = $localize`Failed To Modify Item Notes`;
    protected batchWarningMessage =
        $localize`Note that items in batch do not share notes directly. Displayed notes represent matching note groups.`;

    context: VolCopyContext;

    // Note-specific properties
    notesInCommon: ICopyNote[] = [];
    newNote: ICopyNote;

    notes: IdlObject[] = [];

    constructor(
        modal: NgbModal,
        toast: ToastService,
        idl: IdlService,
        pcrud: PcrudService,
        org: OrgService,
        auth: AuthService
    ) {
        const config: IThingConfig<ICopyNote> = {
            idlClass: 'acpn',
            thingField: 'notes',
            defaultValues: {
                creator: auth.user().id(),
                pub: false
            }
        };
        super(modal, toast, idl, pcrud, org, auth, config);
        this.newNote = this.createNewThing();
        this.context = new VolCopyContext();
        this.context.org = org; // inject
        this.context.idl = idl; // inject
    }

    public async initialize(): Promise<void> {
        if (!this.newNote) {
            this.newNote = this.createNewThing();
        }
        await super.initialize();
    }

    protected async getThings(): Promise<void> {
        if (this.copyIds.length === 0) { return; }
        if (this.notes.length > 0) {
            // console.debug('already have notes, trimming newThings from existing. newThings=', this.newThings);
            this.copies.forEach( c => {
                const newThingIds = this.newThings.map( aa => aa.id() );
                c.notes(
                    (c.notes() || []).filter( a => !newThingIds.includes(a.id()) )
                );
            });
            return;
        } // need to make sure this is cleared after a save. It is; the page reloads

        this.notes = await this.pcrud.search('acpn',
            { owning_copy: this.copyIds },
            {},
            { atomic: true }
        ).toPromise();

        this.copies.forEach(c => c.notes([]));
        this.notes.forEach(note => {
            const copy = this.copies.find(c => c.id() === note.owning_copy());
            copy.notes( copy.notes().concat(note) );
        });
    }

    protected async processCommonThings(): Promise<void> {
        if (!this.inBatch()) { return; }

        let potentialMatches = this.copies[0].notes();

        // Find notes that match across all copies
        this.copies.slice(1).forEach(copy => {
            potentialMatches = potentialMatches.filter(noteFromFirstCopy =>
                copy.notes().some(noteFromCurrentCopy =>
                    this.compositeMatch(noteFromFirstCopy, noteFromCurrentCopy)
                )
            );
        });

        this.notesInCommon = potentialMatches.map(match => {
            const proxy = this.cloneNoteForBatchProxy(match) as ProxyNote;
            // Collect IDs of all matching notes across all copies
            proxy.originalNoteIds = [];
            this.copies.forEach(copy => {
                copy.notes().forEach(note => {
                    if (this.compositeMatch(note, match)) {
                        proxy.originalNoteIds.push(note.id());
                    }
                });
            });
            return proxy;
        });
    }

    protected compositeMatch(a: ICopyNote, b: ICopyNote): boolean {
        return a.title() === b.title() &&
            a.value() === b.value() &&
            a.pub() === b.pub();
    }

    private cloneNoteForBatchProxy(source: ICopyNote): ICopyNote {
        const target = this.createNewThing();
        target.id(source.id());
        target.title(source.title());
        target.value(source.value());
        target.pub(source.pub());
        target.isnew(source.isnew());
        return target;
    }

    addNew(): void {
        if (!this.validate()) { return; }

        this.newNote.id(this.autoId--);
        this.newNote.isnew(true);
        this.newThings.push(this.newNote);
        this.newNote = this.createNewThing();
        const form = document.getElementById('new-note-form') as HTMLFormElement;
        // give createNewThing() a moment.
        /* eslint-disable no-magic-numbers */
        setTimeout(() => {
            form.reset();
            form.elements['new-note-title'].classList.remove('ng-invalid', 'ng-touched');
            form.elements['new-note-value'].classList.remove('ng-invalid', 'ng-touched');
            form.elements['new-note-title'].classList.add('ng-pristine', 'ng-untouched');
            form.elements['new-note-value'].classList.add('ng-pristine', 'ng-untouched');
        }, 5);
        /* eslint-enable no-magic-numbers */
    }

    undeleteNote(note: ICopyNote): void {
        note.isdeleted( note.isdeleted() ?? false );
        // console.debug('undeleteNote, note, note.isdeleted()', note, note.isdeleted());
        super.removeThing([note]); // it's a toggle
    }

    removeNote(note: ICopyNote): void {
        note.isdeleted( note.isdeleted() ?? false );
        // console.debug('removeNote, note, note.isdeleted()', note, note.isdeleted());
        super.removeThing([note]);
    }

    protected validate(): boolean {
        let valid = true;
        const form = document.getElementById('new-note-form') as HTMLFormElement;
        const title = document.getElementById('new-note-title') as HTMLFormElement;
        const value = document.getElementById('new-note-value') as HTMLFormElement;
        const titleError = document.getElementById('new-note-title-feedback') as HTMLElement;
        const valueError = document.getElementById('new-note-value-feedback') as HTMLElement;

        form.classList.add('form-validated');

        if (!this.newNote.title()) {
            title.classList.remove('ng-valid');
            title.classList.add('ng-invalid');
            titleError.removeAttribute('hidden');
            setTimeout(() => title.focus());
            // this.toast.danger($localize`Note title is required`);
            valid = false;
        }
        if (!this.newNote.value()) {
            value.classList.remove('ng-valid');
            value.classList.add('ng-invalid');
            valueError.removeAttribute('hidden');
            // if the title was valid but this is not...
            if (valid) {
                setTimeout(() => value.focus());
            }
            // this.toast.danger($localize`Note content is required`);
            valid = false;
        }
        if (!valid) {return false;}

        titleError.setAttribute('hidden', '');
        valueError.setAttribute('hidden', '');
        return true;
    }

    protected async applyChanges(): Promise<void> {
        try {
            // console.debug('CopyNotesDialog, applyChanges, changedThings prior to rebuild', this.changedThings.length, this.changedThings);
            // console.debug('CopyNotesDialog, applyChanges, deletedThings prior to rebuild', this.deletedThings.length, this.deletedThings);
            // console.debug('CopyNotesDialog, applyChanges, copies', this.copies);
            this.changedThings = [];
            this.deletedThings = [];

            // Find notes that have been modified
            if (this.inBatch()) {
                // For batch mode, look at notesInCommon for changes
                this.changedThings = this.notesInCommon.filter(note => note.ischanged() ?? false);
                this.deletedThings = this.notesInCommon.filter(note => note.isdeleted() ?? false);
                // console.debug('CopyNotesDialog, applyChanges, changedThings rebuilt in batch context', this.changedThings.length, this.changedThings);
                // console.debug('CopyNotesDialog, applyChanges, deletedThings rebuilt in batch context', this.deletedThings.length, this.deletedThings);
            } else if (this.copies.length) {
                // For single mode, look at the copy's alerts
                this.changedThings = this.copies[0].notes()
                    .filter(note => note.ischanged());
                this.deletedThings = this.copies[0].notes()
                    .filter(note => note.isdeleted());
                // console.debug('CopyNotesDialog, applyChanges, changedThings rebuilt in non-batch context', this.changedThings.length, this.changedThings);
                // console.debug('CopyNotesDialog, applyChanges, deletedThings rebuilt in non-batch context', this.deletedThings.length, this.deletedThings);
            } else {
                // console.debug('CopyNotesDialog, applyChanges, inBatch() == false and this.copies.length == false');
            }

            if (this.inPlaceCreateMode) {
                this.close(this.gatherChanges());
                return;
            }

            console.log('here', this);

            this.context.newNotes = this.newThings;
            this.context.changedNotes = this.changedThings;
            this.context.deletedNotes = this.deletedThings;

            this.copies.forEach( c => this.context.updateInMemoryCopyWithNotes(c) );

            // console.debug('copies', this.copies);

            // Handle persistence ourselves
            const result = await this.saveChanges();
            // console.debug('CopyNotesDialogComponent, saveChanges() result', result);
            if (result) {
                this.showSuccess();
                this.notes = []; this.copies = []; this.copyIds = [];
                this.close(this.gatherChanges());
            } else {
                this.showError('saveChanges failed');
            }
        } catch (err) {
            this.showError(err);
        }
    }
}
