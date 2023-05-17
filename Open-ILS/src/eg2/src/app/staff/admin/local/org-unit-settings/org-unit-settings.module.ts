import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {TreeModule} from '@eg/share/tree/tree.module';
import {OrgUnitSettingsComponent} from './org-unit-settings.component';
import {EditOuSettingDialogComponent} from './edit-org-unit-setting-dialog.component';
import {OuSettingHistoryDialogComponent} from './org-unit-setting-history-dialog.component';
import {OrgUnitSettingsRoutingModule} from './org-unit-settings-routing.module';
import {OuSettingJsonDialogComponent} from './org-unit-setting-json-dialog.component';
import {ItemLocationSelectModule} from '@eg/share/item-location-select/item-location-select.module';
import { TimezoneSelectComponent } from './timezone-select/timezone-select.component';
import { Timezone } from '@eg/share/util/timezone';

@NgModule({
    declarations: [
        OrgUnitSettingsComponent,
        EditOuSettingDialogComponent,
        OuSettingHistoryDialogComponent,
        OuSettingJsonDialogComponent,
        TimezoneSelectComponent
    ],
    imports: [
        AdminCommonModule,
        ItemLocationSelectModule,
        OrgUnitSettingsRoutingModule,
        TreeModule
    ],
    exports: [
    ],
    providers: [
        Timezone
    ]
})

export class OrgUnitSettingsModule {
}
