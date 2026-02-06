import {Component, OnInit} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import { StaffBannerComponent } from './share/staff-banner.component';

@Component({
    selector: 'eg-about',
    templateUrl: 'about.component.html',
    imports: [StaffBannerComponent]
})

export class AboutComponent implements OnInit {
    server: string;
    version: string;

    constructor(
        private net: NetService
    ) {}

    ngOnInit() {
        this.server = window.location.hostname;
        this.net.request(
            'open-ils.actor',
            'opensrf.open-ils.system.ils_version'
        ).subscribe(v => this.version = v);
    }
}

