import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {OrgFamilySelectModule} from '@eg/share/org-family-select/org-family-select.module';
import {SimpleReporterComponent} from './simple-reporter.component';
import {SROutputsComponent} from './sr-my-outputs.component';
import {SRReportsComponent} from './sr-my-reports.component';
import {SREditorComponent} from './sr-editor.component';
import {SRFieldChooserComponent} from './sr-field-chooser.component';
import {SRSortOrderComponent} from './sr-sort-order.component';
import {SROutputOptionsComponent} from './sr-output-options.component';
import {SRFieldComponent} from './sr-field.component';
import {SimpleReporterRoutingModule} from './routing.module';

@NgModule({
    declarations: [
        SimpleReporterComponent,
        SROutputsComponent,
        SRReportsComponent,
        SRFieldChooserComponent,
        SRSortOrderComponent,
        SROutputOptionsComponent,
        SRFieldComponent,
        SREditorComponent
    ],
    imports: [
        StaffCommonModule,
        SimpleReporterRoutingModule,
        OrgFamilySelectModule
    ]
})

export class SimpleReporterModule {
}

