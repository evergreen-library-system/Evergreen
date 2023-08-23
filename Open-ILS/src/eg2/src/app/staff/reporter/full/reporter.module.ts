import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {OrgFamilySelectModule} from '@eg/share/org-family-select/org-family-select.module';
import {FolderShareOrgDialogComponent} from './folder-share-org-dialog.component';
import {ChangeFolderDialogComponent} from './change-folder-dialog.component';
import {FullReporterComponent} from './reporter.component';
import {ReportTemplatesComponent} from './my-templates.component';
import {ReportReportsComponent} from './my-reports.component';
import {FullReporterOutputsComponent} from './my-outputs.component';
import {FullReporterEditorComponent} from './editor.component';
import {FullReporterDefinitionComponent} from './definition.component';
import {ReporterFieldChooserComponent} from './reporter-field-chooser.component';
import {ReporterSortOrderComponent} from './reporter-sort-order.component';
import {ReporterOutputOptionsComponent} from './reporter-output-options.component';
import {ReporterFieldComponent} from './reporter-field.component';
import {FullReporterRoutingModule} from './routing.module';
import {TreeModule} from '@eg/share/tree/tree.module';

@NgModule({
    declarations: [
        FullReporterComponent,
        FullReporterOutputsComponent,
        ReporterFieldChooserComponent,
        ReporterSortOrderComponent,
        ReporterOutputOptionsComponent,
        ReporterFieldComponent,
        FullReporterEditorComponent,
        FullReporterDefinitionComponent,
        ReportTemplatesComponent,
        ReportReportsComponent,
        ChangeFolderDialogComponent,
        FolderShareOrgDialogComponent
    ],
    imports: [
        TreeModule,
        StaffCommonModule,
        FullReporterRoutingModule,
        OrgFamilySelectModule
    ]
})

export class FullReporterModule {
}

