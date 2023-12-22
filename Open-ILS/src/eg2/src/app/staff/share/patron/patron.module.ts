import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {GridModule} from '@eg/share/grid/grid.module';
import {PatronService} from './patron.service';
import {PatronSearchComponent} from './search.component';
import {PatronSearchDialogComponent} from './search-dialog.component';
import {ProfileSelectComponent} from './profile-select.component';
import {PatronNoteDialogComponent} from './note-dialog.component';
import {BarcodesModule} from '@eg/staff/share/barcodes/barcodes.module';
import {PatronMergeDialogComponent} from './merge-dialog.component';
import {PatronSummaryComponent} from './summary.component';

@NgModule({
    declarations: [
        PatronSearchComponent,
        PatronSearchDialogComponent,
        ProfileSelectComponent,
        PatronSummaryComponent,
        PatronMergeDialogComponent,
        PatronNoteDialogComponent
    ],
    imports: [
        StaffCommonModule,
        GridModule,
        BarcodesModule
    ],
    exports: [
        PatronSearchComponent,
        PatronSearchDialogComponent,
        ProfileSelectComponent,
        PatronSummaryComponent,
        PatronMergeDialogComponent,
        PatronNoteDialogComponent
    ],
    providers: [
        PatronService
    ]
})

export class PatronModule {}

