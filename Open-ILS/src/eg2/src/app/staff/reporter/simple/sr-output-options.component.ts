import { Component, Input } from '@angular/core';
import {SRTemplate} from '../share/reporter.service';
import moment from 'moment-timezone';
import { StaffCommonModule } from '@eg/staff/common.module';
import { TreeModule } from '@eg/share/tree/tree.module';

@Component({
    selector: 'eg-sr-output-options',
    templateUrl: './sr-output-options.component.html',
    imports: [StaffCommonModule, TreeModule]
})

export class SROutputOptionsComponent {
    @Input() templ: SRTemplate;
    @Input() readyToSchedule: () => boolean;
    @Input() saveTemplate: (args: any) => void;

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
