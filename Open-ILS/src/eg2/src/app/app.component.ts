import {Component, AfterViewChecked} from '@angular/core';
import {Router, NavigationEnd} from '@angular/router';
import {DialogComponent} from '@eg/share/dialog/dialog.component';

@Component({
    selector: 'eg-root',
    template: '<router-outlet></router-outlet>'
})

export class BaseComponent implements AfterViewChecked {

    constructor(private router: Router) {
        this.router.events.subscribe(routeEvent => {
            if (routeEvent instanceof NavigationEnd) {
                // Prevent dialogs from persisting across navigation.
                DialogComponent.closeAll();
            }
        });
    }

    ngAfterViewChecked(): void {
        document.querySelectorAll('a[target="_blank"]').forEach((a) => {
            if (!a.getAttribute('aria-describedby')) {
                a.setAttribute('aria-describedby', 'link-opens-newtab');
            }
        });
    }
}


