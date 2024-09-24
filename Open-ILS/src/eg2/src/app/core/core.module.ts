/**
 * Core objects.
 * Note that core services are generally defined with
 * @Injectable({providedIn: 'root'}) so they are globally available
 * and do not require entry in our 'providers' array.
 */
import {NgModule} from '@angular/core';
import {CommonModule, DatePipe, DecimalPipe} from '@angular/common';
import {FormatValuePipe, OrgDateInContextPipe, DueDatePipe,
    OrUnderscoresPipe, Js2JsonPipe, FundLabelPipe, UsrnameOrIdPipe} from './format.service';

@NgModule({
    declarations: [
        FormatValuePipe,
        OrgDateInContextPipe,
        DueDatePipe,
        OrUnderscoresPipe,
        Js2JsonPipe,
        FundLabelPipe,
        UsrnameOrIdPipe,
    ],
    imports: [
        CommonModule
    ],
    exports: [
        CommonModule,
        FormatValuePipe,
        OrgDateInContextPipe,
        DueDatePipe,
        OrUnderscoresPipe,
        Js2JsonPipe,
        FundLabelPipe,
        UsrnameOrIdPipe,
    ],
    providers: [
        DatePipe,
        DecimalPipe
    ]
})

export class EgCoreModule {}

