/**
 * Force reload of a given path
 */
import { Injectable, inject } from '@angular/core';
import {Location} from '@angular/common';

@Injectable()
export class ForceReloadService {
    private ngLocation = inject(Location);

    reload(url: string) {
        window.location.href =
            this.ngLocation.prepareExternalUrl(url);
    }
}
