import {NgModule} from '@angular/core';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HoldsModule} from '@eg/staff/share/holds/holds.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {PatronModule} from '@eg/staff/share/patron/patron.module';
import {HoldsUiRoutingModule} from './routing.module';
import {HoldsPullListComponent} from './pull-list.component';
import { MakeBookableDialogComponent } from '@eg/staff/share/booking/make-bookable-dialog.component';

@NgModule({
    imports: [
        HoldsPullListComponent,
        StaffCommonModule,
        FmRecordEditorModule,
        HoldsModule,
        HoldingsModule,
        MakeBookableDialogComponent,
        PatronModule,
        HoldsUiRoutingModule
    ],
    providers: [
    ]
})

export class HoldsUiModule {}
