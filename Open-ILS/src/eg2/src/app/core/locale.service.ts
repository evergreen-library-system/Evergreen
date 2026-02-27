import { Injectable, inject } from '@angular/core';
import {Location} from '@angular/common';
import {environment} from '../../environments/environment';
import {Observable} from 'rxjs';
import {CookieService} from 'ngx-cookie';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';

@Injectable({providedIn: 'root'})
export class LocaleService {
    private ngLocation = inject(Location);
    private cookieService = inject(CookieService);
    private pcrud = inject(PcrudService);


    setLocale(code: string) {
        let url = this.ngLocation.prepareExternalUrl('/');

        // The last part of the base path will be the locale
        // Replace it with the selected locale
        url = url.replace(/\/[a-z]{2}-[A-Z]{2}\/$/, `/${code}`);

        // Finally tack the path of the current page back onto the URL
        // which is more friendly than forcing them back to the splash page.
        url += this.ngLocation.path();

        // Set a 10-year locale cookie to maintain compatibility
        // with the AngularJS client.
        // Cookie takes the form aa_bb instead of aa-BB
        const cookie = code.replace(/-/, '_').toLowerCase();
        this.cookieService.put('eg_locale',
            cookie, {path : '/', secure: true, expires: '+10y'});

        window.location.href = url;
    }

    // Returns i18n_l objects matching the locales supported
    // in the current environment.
    supportedLocales(): Observable<IdlObject> {
        const localeCriteria = environment.production ?
            {staff_client: 't'} :
            {code: 'en-US'}; // non-production environments typically only build in English, so don't present other options

        return this.pcrud.search('i18n_l', localeCriteria, {}, {anonymous: true});
    }

    // Extract the local from the URL.
    // It's the last component of the base path.
    // Note we don't extract it from the cookie since using cookies
    // to store the locale will not be necessary when AngularJS
    // is deprecated.
    currentLocaleCode(): string {
        const base = this.ngLocation.prepareExternalUrl('/');
        const code = base.match(/\/([a-z]{2}-[A-Z]{2})\/$/);
        return code ? code[1] : '';
    }
}


