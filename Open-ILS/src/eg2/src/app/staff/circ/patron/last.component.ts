import {Component, OnInit} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {StoreService} from '@eg/core/store.service';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    templateUrl: 'last.component.html',
    imports: [StaffCommonModule]
})
export class LastPatronComponent implements OnInit {
    noRecents = false;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private store: StoreService
    ) {}

    ngOnInit() {

        const ids = this.store.getLoginSessionItem('eg.circ.recent_patrons');
        if (ids && ids[0]) {
            this.noRecents = false;
            this.router.navigate([`/staff/circ/patron/${ids[0]}/checkout`]);
        } else {
            this.noRecents = true;
        }
    }
}
