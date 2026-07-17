import { Component, inject } from '@angular/core';
import {Router} from '@angular/router';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {StoreService} from '@eg/core/store.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { HoldsGridComponent } from '@eg/staff/share/holds/grid.component';

const HOLD_FOR_PATRON_KEY = 'eg.circ.patron_hold_target';

@Component({
    templateUrl: 'holds.component.html',
    selector: 'eg-patron-holds',
    imports: [
        HoldsGridComponent,
        StaffCommonModule
    ]
})
export class HoldsComponent {
    private router = inject(Router);
    private store = inject(StoreService);
    patronService = inject(PatronService);
    context = inject(PatronContextService);


    newHold() {

        this.store.setLoginSessionItem(HOLD_FOR_PATRON_KEY,
            this.context.summary.patron.card().barcode());

        this.router.navigate(['/staff/catalog/search']);
    }
}

