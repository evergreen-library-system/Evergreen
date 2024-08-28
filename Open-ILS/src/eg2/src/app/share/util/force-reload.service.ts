/**
 * Force reload of a given path
 */
import { Injectable } from '@angular/core';
import {Location} from '@angular/common';

@Injectable()
export class ForceReloadService {
    constructor(
        private ngLocation: Location
    ) {}
    reload(url: string) {
        window.location.href =
            this.ngLocation.prepareExternalUrl(url);
    }
}
