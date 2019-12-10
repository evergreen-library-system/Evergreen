import {Injectable} from '@angular/core';
import {CanDeactivate} from '@angular/router';
import {Observable} from 'rxjs';

/**
 * https://angular.io/guide/router#candeactivate-handling-unsaved-changes
 *
 * routing:
 * {
 *   path: 'record/:id/:tab',
 *   component: MyComponent,
 *   canDeactivate: [CanDeactivateGuard]
 * }
 *
 * export class MyComponent {
 *   canDeactivate() ... {
 *      ...
 *   }
 * }
 */

export interface CanComponentDeactivate {
    canDeactivate: () => Observable<boolean> | Promise<boolean> | boolean;
}

@Injectable({providedIn: 'root'})
export class CanDeactivateGuard
    implements CanDeactivate<CanComponentDeactivate> {

    canDeactivate(component: CanComponentDeactivate) {
        return component.canDeactivate ? component.canDeactivate() : true;
    }
}
