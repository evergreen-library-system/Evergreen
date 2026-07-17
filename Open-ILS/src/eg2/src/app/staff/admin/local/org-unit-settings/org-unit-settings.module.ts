import {NgModule} from '@angular/core';
import {AdminCommonModule} from '@eg/staff/admin/common.module';
import {TreeModule} from '@eg/share/tree/tree.module';
import {OrgUnitSettingsComponent} from './org-unit-settings.component';
import {EditOuSettingDialogComponent} from './edit-org-unit-setting-dialog.component';
import {OuSettingHistoryDialogComponent} from './org-unit-setting-history-dialog.component';
import {OrgUnitSettingsRoutingModule} from './org-unit-settings-routing.module';
import {OuSettingJsonDialogComponent} from './org-unit-setting-json-dialog.component';
import { TimezoneSelectComponent } from './timezone-select/timezone-select.component';
import { Timezone } from '@eg/share/util/timezone';
import { ItemLocationSelectComponent } from '@eg/share/item-location-select/item-location-select.component';

@NgModule({
    imports: [
        AdminCommonModule,
        ItemLocationSelectComponent,
        OrgUnitSettingsRoutingModule,
        OrgUnitSettingsComponent,
        EditOuSettingDialogComponent,
        OuSettingHistoryDialogComponent,
        OuSettingJsonDialogComponent,
        TimezoneSelectComponent,
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
