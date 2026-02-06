import {Component} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { HoldsGridComponent } from '@eg/staff/share/holds/grid.component';

@Component({
    selector: 'eg-holds-pull-list',
    templateUrl: 'pull-list.component.html',
    imports: [
        HoldsGridComponent,
        StaffCommonModule
    ]
})
export class HoldsPullListComponent {

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: StoreService
    ) {}

    targetOrg(): number {
        return this.auth.user().ws_ou();
    }
}

