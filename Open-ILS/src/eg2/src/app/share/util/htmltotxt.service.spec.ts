import {HtmlToTxtService} from './htmltotxt.service';

let h2txt: HtmlToTxtService;

beforeEach(() => {
    h2txt = new HtmlToTxtService();
});

describe('HtmlToTxtService', () => {
    it('htmlToTxt cleans multiline comments', () => {
        // this is a regression test for LP#1857710 on Firefox
        const str = '<h1>A print template</h1> <!-- I am a comment\nwith an embedded newline --> <div>body of template</div>';
        expect(h2txt.htmlToTxt(str)).toEqual('A print template  body of template');
    });
});
