import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {ItemRoutingModule} from './routing.module';
import {HoldingsModule} from '@eg/staff/share/holdings/holdings.module';
import {PatronModule} from '@eg/staff/share/patron/patron.module';
import {MarkItemMissingPiecesComponent} from './missing-pieces.component';

@NgModule({
    declarations: [
        MarkItemMissingPiecesComponent
    ],
    imports: [
        StaffCommonModule,
        CommonWidgetsModule,
        ItemRoutingModule,
        HoldingsModule,
        PatronModule
    ],
    providers: [
    ]
})

export class ItemModule {}
