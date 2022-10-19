import {Component} from '@angular/core';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';

@Component({
  selector: 'eg-holds-pull-list',
  templateUrl: 'pull-list.component.html'
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

