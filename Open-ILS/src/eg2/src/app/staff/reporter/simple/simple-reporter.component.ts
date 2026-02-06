import {Component} from '@angular/core';
import { StaffCommonModule } from '@eg/staff/common.module';
import { SRReportsComponent } from './sr-my-reports.component';

@Component({
    templateUrl: './simple-reporter.component.html',
    imports: [
        SRReportsComponent,
        StaffCommonModule
    ]
})

export class SimpleReporterComponent {}
