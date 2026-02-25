import { Component, inject } from '@angular/core';
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
    private router = inject(Router);
    private route = inject(ActivatedRoute);
    private pcrud = inject(PcrudService);
    private auth = inject(AuthService);
    private store = inject(StoreService);


    targetOrg(): number {
        return this.auth.user().ws_ou();
    }
}

