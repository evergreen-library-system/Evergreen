import { Component, inject } from '@angular/core';
import { Router, NavigationEnd, RouterOutlet } from '@angular/router';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
    selector: 'eg-root',
    template: '<router-outlet></router-outlet>',
    imports: [RouterOutlet]
})

export class BaseComponent {
    private router = inject(Router);


    constructor() {
        this.router.events.subscribe(routeEvent => {
            if (routeEvent instanceof NavigationEnd) {
                // Prevent dialogs from persisting across navigation.
                DialogComponent.closeAll();
            }
        });
    }

}


