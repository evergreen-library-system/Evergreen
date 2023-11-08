import { IdlService } from '@eg/core/idl.service';
import { CatalogSearchContext, CatalogTermContext } from './search-context';

const idlService = new IdlService();
idlService.parseIdl();
const searchOrg = idlService.create('aou');
searchOrg.id(12);
searchOrg.shortname('BR5');


describe('#compileTermSearchQuery', () => {
    let ctx: CatalogSearchContext;
    let termContext: CatalogTermContext;

    beforeEach(() => {
        ctx = new CatalogSearchContext();
        ctx.searchOrg = searchOrg;
        termContext = new CatalogTermContext();
        termContext.reset();
        termContext.query = ['dogs'];
    });

    it('can create a valid query string for an on_reserve filter', () => {
        termContext.onReserveFilter = true;
        ctx.termSearch = termContext;
        expect(ctx.compileTermSearchQuery()).toEqual('on_reserve(12) (keyword:dogs) site(BR5)');
    });

    it('can create a valid query string for a combination of on_reserve and available filter', () => {
        termContext.onReserveFilter = true;
        termContext.available = true;
        ctx.termSearch = termContext;
        expect(ctx.compileTermSearchQuery()).toEqual('#available on_reserve(12) (keyword:dogs) site(BR5)');
    });

    it('can create a valid query string for a negated on_reserve filter', () => {
        termContext.onReserveFilter = true;
        termContext.onReserveFilterNegated = true;
        ctx.termSearch = termContext;
        expect(ctx.compileTermSearchQuery()).toEqual('-on_reserve(12) (keyword:dogs) site(BR5)');
    });
});
