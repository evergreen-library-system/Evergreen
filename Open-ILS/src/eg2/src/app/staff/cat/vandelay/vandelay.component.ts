import {Component} from '@angular/core';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {take} from 'rxjs/operators';
import {VandelayService} from './vandelay.service';

@Component({
    templateUrl: 'vandelay.component.html'
})
export class VandelayComponent {
    tab: string;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private vandelay: VandelayService) {

        // As the parent component of the vandelay route tree, our
        // activated route never changes.  Instead, listen for global
        // route events, then ask for the first segement of the first
        // child, which will be the tab name.
        this.router.events.subscribe(routeEvent => {
            if (routeEvent instanceof NavigationEnd) {
                this.route.firstChild.url.pipe(take(1))
                    // eslint-disable-next-line rxjs/no-nested-subscribe
                    .subscribe(segments => this.tab = segments[0].path);
            }
        });
    }
}

