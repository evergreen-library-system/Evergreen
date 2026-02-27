import { Component, OnInit, ViewChild, inject } from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {EventGridComponent} from './event-grid.component';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    templateUrl: 'event-log.component.html',
    imports: [StaffCommonModule, EventGridComponent]
})

export class EventLogComponent implements OnInit {
    private route = inject(ActivatedRoute);

    patronId: number;

    @ViewChild('eventGrid', { static: true }) eventGrid: EventGridComponent;

    ngOnInit() {
        // Note: if this is not supplied, the grid will show recent events
        // across all patrons, which may be a neat feature...
        // TODO: see if we're honoring VIEW_USER permission and patron opt-in
        this.patronId = +this.route.snapshot.paramMap.get('patron');
    }
}


