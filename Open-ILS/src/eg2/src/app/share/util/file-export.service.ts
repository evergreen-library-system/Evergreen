/**
 * Create and consume BroadcastChannel broadcasts
 */
import {Injectable, EventEmitter} from '@angular/core';
import {DomSanitizer, SafeUrl} from '@angular/platform-browser';

@Injectable()
export class FileExportService {

    resolver: Function = null;
    safeUrl: SafeUrl;

    constructor(private sanitizer: DomSanitizer) { }

    exportFile($event: any, content: string,
        contentType: string = 'text/plain'): Promise<any> {

        if (!$event || !content) { return null; }

        if (this.resolver) {
            // This is secondary href click handler.  Give the
            // browser a moment to start the download, then reset
            // the CSV download attributes / state.
            setTimeout(() => {
                this.resolver();
                this.resolver = null;
                this.safeUrl = null;
            }, 500);

            return;
        }

        const promise = new Promise(resolve => this.resolver = resolve);
        const blob = new Blob([content], {type : contentType});
        const win: any = window; // avoid TS errors

        this.safeUrl = this.sanitizer.bypassSecurityTrustUrl(
            (win.URL || win.webkitURL).createObjectURL(blob));

        // Fire the 2nd click event now that the browser has
        // information on how to download the CSV file.
        setTimeout(() => $event.target.click());

        $event.preventDefault();

        return promise;
    }

    inProgress(): boolean {
        return this.resolver !== null;
    }
}

