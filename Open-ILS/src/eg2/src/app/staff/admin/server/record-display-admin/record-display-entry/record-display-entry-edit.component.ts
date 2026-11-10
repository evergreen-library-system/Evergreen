import { Component, effect, EventEmitter, inject, input, OnInit, Output, TemplateRef, ViewChild } from '@angular/core';
import { AbstractControl, FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { CommonWidgetsModule } from '@eg/share/common-widgets.module';
import { DialogComponent } from '@eg/share/dialog/dialog.component';
import { IdlObject, IdlService } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { map } from 'rxjs';
import { ComboboxEntry } from '@eg/share/combobox/combobox.component';
import { BibFieldService } from '@eg/share/catalog/bib-field.service';
import { contentTypeLabel, DisplayEntryContentType } from './content-type';


@Component({
    selector: 'eg-record-display-entry-edit',
    standalone: true,
    imports: [ReactiveFormsModule, CommonWidgetsModule],
    templateUrl: './record-display-entry-edit.component.html'
})
export class RecordDisplayEntryEditComponent extends DialogComponent implements OnInit {
    protected columnIndex = input.required<number>();
    protected maxRow = input<number>();
    protected mode = input.required<'create'|'edit'>();
    protected type = input.required<'search_result'|'staff_view'>();
    protected data = input<IdlObject>();

    @Output() formSubmit = new EventEmitter<any>();
    @ViewChild('dialogContent') dialogContent: TemplateRef<any>;

    bibField = inject(BibFieldService);
    idl = inject(IdlService);
    pcrud = inject(PcrudService);

    fieldEntries: ComboboxEntry[];

    recordDisplayEntryEditForm = new FormGroup({
        contentType: new FormControl(null, Validators.required),
        field: new FormControl(null),
        valueLimit: new FormControl(null),
        characterLimit: new FormControl(null),
        displayAsLink: new FormControl(null),
    }, {
        validators: (form) => {
            const contentType = form.get('contentType');
            const field = form.get('field');
            if (contentType?.value === 'field' && !field.value) {
                return {noFieldSelected: true};
            }
            return null;
        }
    });

    // If the data changes, reapply the default values from the fresh data
    _ = effect(() => {if (this.data()) { this.applyDefaults();} });

    ngOnInit(): void {
        this.applyDefaults();
        this.fetchComboboxEntries();
    }

    applyDefaults() {
        if (this.data()) {
            this.contentType.patchValue(this.data().content_type());
            this.recordDisplayEntryEditForm.get('field').patchValue({id: this.fieldId});
            this.recordDisplayEntryEditForm.get('valueLimit').patchValue(this.data().value_limit());
            this.recordDisplayEntryEditForm.get('characterLimit').patchValue(this.data().character_limit());
            this.recordDisplayEntryEditForm.get('displayAsLink').patchValue(this.data().display_as_link() === 't');
        }
    }

    override close() {
        this.recordDisplayEntryEditForm.reset();
        super.close();
    }

    protected save() {
        if (this.mode() === 'edit') {
            this.update();
        } else {
            this.create();
        }
    }

    protected delete() {
        this.pcrud.remove(this.data()).subscribe({complete: () => {
            this.formSubmit.emit(null);
            this.close();
        }});
    }

    protected contentTypeLabel(type: DisplayEntryContentType): string {
        return contentTypeLabel(type);
    }

    protected get canSelectField(): boolean {
        return this.contentType.value === 'field';
    }

    protected get canLimitCharacters(): boolean {
        return ['field'].includes(this.contentType.value);
    }

    protected get canLimitValues(): boolean {
        return ['field'].includes(this.contentType.value);
    }

    protected get canDisplayAsLink(): boolean {
        return ['field'].includes(this.contentType.value);
    }

    protected get fieldId(): number {
        if (!this.data) { return null; }
        if (this.data().field()?.id) { return this.data().field().id(); }
        return this.data().field();
    }

    private get contentType(): AbstractControl {
        return this.recordDisplayEntryEditForm.get('contentType');
    }

    private create() {
        const entry = this.idl.create('curde');
        entry.col_pos(this.maxRow() + 1);
        entry.type(this.type());
        entry.page_col(this.columnIndex());
        entry.content_type(this.contentType.value);
        entry.field(this.recordDisplayEntryEditForm.get('field')?.value?.id);
        entry.value_limit(this.recordDisplayEntryEditForm.get('valueLimit').value);
        entry.character_limit(this.recordDisplayEntryEditForm.get('characterLimit').value);
        if ( this.canDisplayAsLink ) {
            entry.display_as_link(this.recordDisplayEntryEditForm.get('displayAsLink').value ? 't' : 'f');
        }
        this.pcrud.create(entry).subscribe({complete: () => {
            this.formSubmit.emit(null);
            this.close();
        }});
    }

    private update() {
        const entry = this.data();
        entry.field(this.recordDisplayEntryEditForm.get('field')?.value?.id);
        entry.value_limit(this.recordDisplayEntryEditForm.get('valueLimit').value);
        entry.character_limit(this.recordDisplayEntryEditForm.get('characterLimit').value);
        entry.display_as_link(this.recordDisplayEntryEditForm.get('displayAsLink').value ? 't' : 'f');
        this.pcrud.update(entry).subscribe({complete: () => {
            this.formSubmit.emit(null);
            this.close();
        }});
    }

    private fetchComboboxEntries(): void {
        this.bibField.displayFields.pipe(
            map(fields => fields.map((field:IdlObject) => {
                return {id: field.field().id(), label: field.field().label()};
            }).sort((a, b)=> a.label.localeCompare(b.label))),
        ).subscribe(fields => this.fieldEntries = fields);
    }
}
