import {Component, Input, AfterViewInit, ViewChild} from '@angular/core';
import {Title} from '@angular/platform-browser';
import {StringComponent} from '@eg/share/string/string.component';

/*
    <eg-title i18n-prefix i18n-suffix
        prefix="Patron #{{patronId}}
        suffix="Staff Client">
    </eg-title>

    Tab title shows (in en-US):  "Patron #123 - Staff Client"
*/

@Component({
  selector: 'eg-title',
  templateUrl: 'title.component.html'
})

export class TitleComponent implements AfterViewInit {

    initDone: boolean;

    pfx: string;
    @Input() set prefix(p: string) {
        this.pfx = p;
        this.setTitle();
    }

    sfx: string;
    @Input() set suffix(s: string) {
        this.sfx = s;
        this.setTitle();
    }

    @ViewChild('titleString', { static: true }) titleString: StringComponent;

    constructor(private title: Title) {}

    ngAfterViewInit() {
        this.initDone = true;
        this.setTitle();
    }

    setTitle() {

        // Avoid setting the title while the page is still loading
        if (!this.initDone) { return; }

        setTimeout(() => {
            this.titleString.current({pfx: this.pfx, sfx: this.sfx})
            .then(txt => this.title.setTitle(txt));
        });
    }
}

