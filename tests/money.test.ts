import {describe,it,expect} from 'vitest';
import {cents,sum,decimal,money,normalizeDigits,reconciliation} from '../src/lib/money';
describe('exact financial arithmetic',()=>{
 it('adds decimal amounts without floating-point loss',()=>expect(decimal(sum(['0.10','0.20']))).toBe('0.30'));
 it('retains large NUMERIC values',()=>expect(decimal(cents('99999999999999.99'))).toBe('99999999999999.99'));
 it('rejects fractional cents',()=>expect(()=>cents('1.001')).toThrow());
 it('supports reversals',()=>expect(money(sum(['1000.10','-200.05']))).toBe('800.05'));
 it('normalizes Arabic keypad input',()=>expect(normalizeDigits('١٢٣٫٤٥')).toBe('123.45'));
 it('reconciliation never automatically approves',()=>expect(reconciliation('100.10','100.10')).toEqual({difference:'0.00',requiresApproval:true}));
});
