import { Component, inject, OnInit, signal, effect } from '@angular/core';
import { PcrudService } from '@eg/core/pcrud.service';
import { catchError, EMPTY } from 'rxjs';
import { IdlObject } from '@eg/core/idl.service';
import { PermService } from '@eg/core/perm.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { RecordDisplayAdminColumnComponent } from './record-display-admin-column/record-display-admin-column.component';
import { FormControl } from '@angular/forms';
import { BibRecordService, BibRecordSummary, InvalidRecordError } from '@eg/share/catalog/bib-record.service';
import { StaffRecordSummaryViewComponent } from '@eg/share/catalog/staff-record-summary-view/staff-record-summary-view.component';
import { BibFieldService } from '@eg/share/catalog/bib-field.service';
import { MetadataColumnComponent } from '../../../../share/catalog/metadata-column.component';

const HALF_SECOND = 500;

@Component({
    selector: 'eg-record-display-admin',
    standalone: true,
    imports: [
        StaffCommonModule, RecordDisplayAdminColumnComponent,
        StaffRecordSummaryViewComponent,
        MetadataColumnComponent
    ],
    templateUrl: './record-display-admin.component.html'
})
export class RecordDisplayAdminComponent implements OnInit {
    entries: IdlObject[]; // curde objects
    displayFields: IdlObject[]; // cdfm objects
    hasPermissions = false;
    interfaceToEdit = new FormControl<'search_result'|'staff_view'>(null);
    previewId = new FormControl('');
    summary: BibRecordSummary;
    previewError = signal(null);

    focusPreviewErrors = effect(() => {
        if(this.previewError()) {
            setTimeout(() => {
                document.getElementById('preview-error').focus();
            }, HALF_SECOND);
        }
    });

    bibField = inject(BibFieldService);
    bibService = inject(BibRecordService);
    pcrud = inject(PcrudService);
    permissions = inject(PermService);

    ngOnInit(): void {
        this.permissions.hasWorkPermAt(['ADMIN_RECORD_DISPLAY']).then(results => {
            this.hasPermissions = Boolean(results['ADMIN_RECORD_DISPLAY'].length);
        });
        this.interfaceToEdit.valueChanges.subscribe(() => this.reloadData());
        this.bibField.displayFields.subscribe((values) => this.displayFields = values);
    }

    protected reloadData(): void {
        if(this.interfaceToEdit.value) {
            this.bibField.recordDisplayEntries(this.interfaceToEdit.value)
                .subscribe(entries => this.entries = entries);
            this.loadSummary();
        }
    }

    protected loadSummary(): void {
        if (!this.previewId.value) { return; }
        this.bibService.getBibSummary(Number(this.previewId.value), null, null, {search_result: true, staff_view: true})
            .pipe(catchError(e => {
                if (e instanceof InvalidRecordError) {
                    this.previewError.set($localize`Record id ${this.previewId.value} is invalid, please try a different record.`);
                    // setTimeout(() => document.getElementById('preview-error').focus(), HALF_SECOND);
                }
                return EMPTY;
            }))
            .subscribe((summary) => {
                this.summary = summary;
                this.previewError.set(null);
            });
    }

    protected get firstColumn(): IdlObject[] {
        return this.entries?.filter(entry => entry.page_col() === 1) || [];
    }

    protected get secondColumn(): IdlObject[] {
        return this.entries?.filter(entry => entry.page_col() === 2) || [];
    }

    protected get thirdColumn(): IdlObject[] {
        // eslint-disable-next-line no-magic-numbers
        return this.entries?.filter(entry => entry.page_col() === 3) || [];
    }
}
