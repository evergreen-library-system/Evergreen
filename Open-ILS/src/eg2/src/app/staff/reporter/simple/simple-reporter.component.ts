import {Component} from '@angular/core';
import { StaffCommonModule } from '@eg/staff/common.module';
import { SRReportsComponent } from './sr-my-reports.component';
import { SROutputsComponent } from './sr-my-outputs.component';

@Component({
    templateUrl: './simple-reporter.component.html',
    imports: [
        SROutputsComponent,
        SRReportsComponent,
        StaffCommonModule
    ]
})

export class SimpleReporterComponent {}
