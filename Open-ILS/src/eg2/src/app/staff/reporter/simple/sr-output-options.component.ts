import {Component, Input} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {ReporterService, SRTemplate} from '../share/reporter.service';
import * as moment from 'moment-timezone';

@Component({
    selector: 'eg-sr-output-options',
    templateUrl: './sr-output-options.component.html'
})

export class SROutputOptionsComponent {

    @Input() templ: SRTemplate;
    @Input() readyToSchedule: () => boolean;
    @Input() saveTemplate: (args: any) => void;

    constructor(
        private idl: IdlService,
        private srSvc: ReporterService
    ) { }

    defaultTime() {
        // When changing to Later for the first time default minutes to the quarter hour
        if (this.templ.runNow === 'later' && this.templ.runTime === null) {
            const now = moment();
            // eslint-disable-next-line no-magic-numbers
            const nextQ = now.add(15 - (now.minutes() % 15), 'minutes');
            this.templ.runTime = nextQ;
        }
    }

}
