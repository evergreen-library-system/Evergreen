import {Component, OnInit, ViewChild} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {ItemEventGridComponent} from './event-grid.component';

@Component({
    templateUrl: 'event-log.component.html'
})

export class ItemEventLogComponent implements OnInit {
    itemId: number;

    @ViewChild('itemEventGrid', { static: true }) itemEventGrid: ItemEventGridComponent;

    constructor(
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService
    ) {}

    ngOnInit() {
        // Note: if this is not supplied, the grid will show recent events
        // across all items, which may be a neat feature...
        this.itemId = +this.route.snapshot.paramMap.get('item');
    }
}


