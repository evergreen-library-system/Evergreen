import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {MakeBookableDialogComponent} from './make-bookable-dialog.component';

@NgModule({
    declarations: [
        MakeBookableDialogComponent
    ],
    imports: [
        StaffCommonModule
    ],
    exports: [
        MakeBookableDialogComponent
    ],
    providers: [
    ]
})

export class BookingModule {}

