import {Component, OnInit, ViewChild} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventGridComponent} from './event-grid.component';

@Component({
    templateUrl: 'event-log.component.html'
})

export class EventLogComponent implements OnInit {
    patronId: number;

    @ViewChild('eventGrid', { static: true }) eventGrid: EventGridComponent;

    constructor(
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService
    ) {}

    ngOnInit() {
        // Note: if this is not supplied, the grid will show recent events
        // across all patrons, which may be a neat feature...
        // TODO: see if we're honoring VIEW_USER permission and patron opt-in
        this.patronId = +this.route.snapshot.paramMap.get('patron');
    }
}


