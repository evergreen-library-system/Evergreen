import { Component, OnInit, AfterViewInit, ViewChild, ViewEncapsulation, inject } from '@angular/core';
import {Router, ActivatedRoute, RouterModule} from '@angular/router';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {SckoService} from './scko.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import { CommonModule } from '@angular/common';
import { StringComponent } from '@eg/share/string/string.component';
import { ContextMenuContainerComponent } from '@eg/share/context-menu/context-menu-container.component';
import { PrintComponent } from '@eg/share/print/print.component';
import { ToastComponent } from '@eg/share/toast/toast.component';
import { AlertDialogComponent } from '@eg/share/dialog/alert.component';
import { SckoBannerComponent } from './banner.component';
import { SckoSummaryComponent } from './summary.component';

@Component({
    templateUrl: 'scko.component.html',
    styleUrls: ['scko.component.css'],
    encapsulation: ViewEncapsulation.None,
    imports: [
        AlertDialogComponent,
        CommonModule,
        ConfirmDialogComponent,
        ContextMenuContainerComponent,
        PrintComponent,
        RouterModule,
        SckoBannerComponent,
        SckoSummaryComponent,
        StringComponent,
        ToastComponent
    ]
})

export class SckoComponent implements OnInit, AfterViewInit {
    private router = inject(Router);
    private route = inject(ActivatedRoute);
    private net = inject(NetService);
    private auth = inject(AuthService);
    scko = inject(SckoService);


    @ViewChild('logoutDialog') logoutDialog: ConfirmDialogComponent;
    @ViewChild('alertDialog') alertDialog: ConfirmDialogComponent;

    ngOnInit() {
        this.net.authExpired$.subscribe(how => {
            console.debug('SCKO auth expired with info', how);
            this.scko.logoutStaff();
        });

        // force light mode (for now)
        document.documentElement.setAttribute('data-bs-theme', 'light');

        this.scko.load();
    }

    ngAfterViewInit() {
        this.scko.logoutDialog = this.logoutDialog;
        this.scko.alertDialog = this.alertDialog;
    }
}

