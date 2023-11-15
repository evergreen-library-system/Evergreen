import { Timezone } from './timezone';

describe('timezone utility', () => {
    it('includes valid timezones', () => {
        expect(new Timezone().values()).toContain('America/Chicago');
        expect(new Timezone().values()).toContain('America/New_York');
    });
    it('does not include invalid timezones', () => {
        expect(new Timezone().values()).not.toContain('MARGARITA TIME!!!');
    });
});
