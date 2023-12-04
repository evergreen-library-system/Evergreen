/**
 * Core objects.
 * Note that core services are generally defined with
 * @Injectable({providedIn: 'root'}) so they are globally available
 * and do not require entry in our 'providers' array.
 */
import {NgModule} from '@angular/core';
import {CommonModule, DatePipe, DecimalPipe} from '@angular/common';
import {FormatValuePipe, OrgDateInContextPipe, DueDatePipe} from './format.service';

@NgModule({
    declarations: [
        FormatValuePipe,
        OrgDateInContextPipe,
        DueDatePipe
    ],
    imports: [
        CommonModule
    ],
    exports: [
        CommonModule,
        FormatValuePipe,
        OrgDateInContextPipe,
        DueDatePipe
    ],
    providers: [
        DatePipe,
        DecimalPipe
    ]
})

export class EgCoreModule {}

