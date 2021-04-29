import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {StoreService} from '@eg/core/store.service';

@Component({
  templateUrl: 'last.component.html'
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
