import {Component, OnInit, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {NgbNav} from '@ng-bootstrap/ng-bootstrap';
import {StaffCommonModule} from '@eg/staff/common.module';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {SimpleReporterService} from './simple-reporter.service';
import {SROutputsComponent} from './sr-my-outputs.component';

@Component({
    templateUrl: './simple-reporter.component.html',
})

export class SimpleReporterComponent implements OnInit {

    @ViewChild('simpleRptTabs', { static: true }) tabs: NgbNav;

    constructor(
        private router: Router,
        private auth: AuthService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private srSvc: SimpleReporterService
    ) {

    }


    ngOnInit() {

    }

}
