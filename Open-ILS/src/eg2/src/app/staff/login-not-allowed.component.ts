import {Component, OnInit, AfterViewInit} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';

@Component({
    templateUrl : './login-not-allowed.component.html'
})

export class StaffLoginNotAllowedComponent implements OnInit, AfterViewInit {

    username: string;
    userId: number;

    constructor(
      private router: Router,
      private route: ActivatedRoute,
      private ngLocation: Location,
      private auth: AuthService
    ) {}

    ngOnInit() {
        this.username = this.auth.user().usrname();
        this.userId = this.auth.user().id();
    }

    ngAfterViewInit() {
        // Timeout allows us to force the logout, without the UI
        // sending is immediately back to the login page.
        setTimeout(() => this.auth.logout());
    }
}



