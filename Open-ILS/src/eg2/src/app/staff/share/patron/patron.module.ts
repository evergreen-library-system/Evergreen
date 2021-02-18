import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {GridModule} from '@eg/share/grid/grid.module';
import {PatronService} from './patron.service';
import {PatronSearchComponent} from './search.component';
import {PatronSearchDialogComponent} from './search-dialog.component';
import {ProfileSelectComponent} from './profile-select.component';
import {PatronPenaltyDialogComponent} from './penalty-dialog.component';
import {BarcodesModule} from '@eg/staff/share/barcodes/barcodes.module';

@NgModule({
    declarations: [
        PatronSearchComponent,
        PatronSearchDialogComponent,
        ProfileSelectComponent,
        PatronPenaltyDialogComponent
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
        PatronPenaltyDialogComponent
    ],
    providers: [
        PatronService
    ]
})

export class PatronModule {}

