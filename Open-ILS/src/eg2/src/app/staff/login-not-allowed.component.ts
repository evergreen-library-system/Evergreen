import { Component, OnInit, AfterViewInit, inject } from '@angular/core';
import {RouterModule} from '@angular/router';
import {AuthService} from '@eg/core/auth.service';

@Component({
    templateUrl: './login-not-allowed.component.html',
    imports: [RouterModule]
})

export class StaffLoginNotAllowedComponent implements OnInit, AfterViewInit {
    private auth = inject(AuthService);


    username: string;
    userId: number;

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



