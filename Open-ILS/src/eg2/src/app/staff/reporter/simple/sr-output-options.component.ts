import {Component, Input, Output, EventEmitter, OnInit, ViewChild} from '@angular/core';
import {NgForm} from '@angular/forms';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {SimpleReporterService, SRTemplate} from './simple-reporter.service';
import * as moment from 'moment-timezone';

@Component({
  selector: 'eg-sr-output-options',
  templateUrl: './sr-output-options.component.html'
})

export class SROutputOptionsComponent implements OnInit {

    @Input() templ: SRTemplate;
    @Input() readyToSchedule: () => boolean;
    @Input() saveTemplate: (args: any) => void;

    constructor(
        private idl: IdlService,
        private srSvc: SimpleReporterService
    ) { }

    ngOnInit() {}

    defaultTime() {
        // When changing to Later for the first time default minutes to the quarter hour
        if (this.templ.runNow === 'later' && this.templ.runTime === null) {
            const now = moment();
            const nextQ = now.add(15 - (now.minutes() % 15), 'minutes');
            this.templ.runTime = nextQ;
        }
    }

}
