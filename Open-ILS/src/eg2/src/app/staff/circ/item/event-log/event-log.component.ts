import { Component, OnInit, ViewChild, inject } from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {ItemEventGridComponent} from './event-grid.component';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    templateUrl: 'event-log.component.html',
    imports: [StaffCommonModule]
})

export class ItemEventLogComponent implements OnInit {
    private route = inject(ActivatedRoute);
    private net = inject(NetService);
    private auth = inject(AuthService);

    itemId: number;

    @ViewChild('itemEventGrid', { static: true }) itemEventGrid: ItemEventGridComponent;

    ngOnInit() {
        // Note: if this is not supplied, the grid will show recent events
        // across all items, which may be a neat feature...
        this.itemId = +this.route.snapshot.paramMap.get('item');
    }
}


