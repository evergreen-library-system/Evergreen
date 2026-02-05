import { Cardinality, cardinalityGuess } from './cardinality';

describe('cardinalityGuess()', () => {
    it('returns Unknown if no info given', () => {
        expect(cardinalityGuess({})).toEqual(Cardinality.Unknown);
    });
    it('takes info from cardinality field if given', () => {
        expect(cardinalityGuess({cardinality: 'low'})).toEqual(Cardinality.Low);
        expect(cardinalityGuess({cardinality: 'high'})).toEqual(Cardinality.High);
        expect(cardinalityGuess({cardinality: 'unbounded'})).toEqual(Cardinality.Unbounded);
    });
    it('assumes clases with table names ending in _log or _history are unbounded', () => {
        expect(cardinalityGuess({table: 'acq_lineitem_history'})).toEqual(Cardinality.Unbounded);
        expect(cardinalityGuess({table: 'org_unit_setting_type_log'})).toEqual(Cardinality.Unbounded);
    });
});
