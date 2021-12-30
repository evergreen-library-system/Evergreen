import {Component, OnInit, Input, ViewChild, HostListener} from '@angular/core';
import {NgbTabset, NgbTabChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';

@Component({
  selector: 'eg-holds-pull-list',
  templateUrl: 'pull-list.component.html'
})
export class HoldsPullListComponent implements OnInit {

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: StoreService
    ) {}

    ngOnInit() {
    }

    targetOrg(): number {
        return this.auth.user().ws_ou();
    }
}

