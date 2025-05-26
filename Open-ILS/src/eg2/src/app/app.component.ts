import {Component} from '@angular/core';
import {Router, NavigationEnd} from '@angular/router';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
    selector: 'eg-root',
    template: '<router-outlet></router-outlet>'
})

export class BaseComponent {

    constructor(private router: Router) {
        this.router.events.subscribe(routeEvent => {
            if (routeEvent instanceof NavigationEnd) {
                // Prevent dialogs from persisting across navigation.
                DialogComponent.closeAll();
            }
        });
    }

}


