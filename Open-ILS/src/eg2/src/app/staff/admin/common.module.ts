import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {LinkTableComponent, LinkTableLinkComponent} from '@eg/staff/share/link-table/link-table.component';
import {TranslateModule} from '@eg/share/translate/translate.module';
import {FmRecordEditorModule} from '@eg/share/fm-editor/fm-editor.module';
import {AdminPageModule} from '@eg/staff/share/admin-page/admin-page.module';
import {BasicAdminPageComponent} from '@eg/staff/admin/basic-admin-page.component';

@NgModule({
  declarations: [
    LinkTableComponent,
    LinkTableLinkComponent,
    BasicAdminPageComponent
  ],
  imports: [
    StaffCommonModule,
    TranslateModule,
    FmRecordEditorModule,
    AdminPageModule
  ],
  exports: [
    StaffCommonModule,
    TranslateModule,
    FmRecordEditorModule,
    AdminPageModule,
    LinkTableComponent,
    LinkTableLinkComponent,
    BasicAdminPageComponent
  ],
  providers: [
  ]
})

export class AdminCommonModule {
}


