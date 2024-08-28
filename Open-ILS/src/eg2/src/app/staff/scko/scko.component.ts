import {Component, OnInit, AfterViewInit, ViewChild, ViewEncapsulation} from '@angular/core';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {SckoService} from './scko.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';

@Component({
    templateUrl: 'scko.component.html',
    styleUrls: ['scko.component.css'],
    encapsulation: ViewEncapsulation.None
})

export class SckoComponent implements OnInit, AfterViewInit {

    @ViewChild('logoutDialog') logoutDialog: ConfirmDialogComponent;
    @ViewChild('alertDialog') alertDialog: ConfirmDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        public  scko: SckoService
    ) {}

    ngOnInit() {
        this.net.authExpired$.subscribe(how => {
            console.debug('SCKO auth expired with info', how);
            this.scko.logoutStaff();
        });

        this.scko.load();
    }

    ngAfterViewInit() {
        this.scko.logoutDialog = this.logoutDialog;
        this.scko.alertDialog = this.alertDialog;
    }
}

