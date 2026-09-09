import { describe, it, expect } from '@ohos/hypium';
import {
  findCountryByDialCode,
  findCountryByIso,
  formatFullPhoneNumber,
  CountryInfo
} from '../main/ets/model/CountryCode';

export default function countryCodeTest(): void {
  describe('CountryCodeTest', () => {
    it('findCountryByDialCode_matchesExactPrefix', 0, () => {
      const cn: CountryInfo | undefined = findCountryByDialCode('+86');
      expect(cn !== undefined).assertTrue();
      if (cn !== undefined) {
        expect(cn.code).assertEqual('CN');
        expect(cn.name).assertEqual('China');
      }

      const us: CountryInfo | undefined = findCountryByDialCode('1');
      expect(us !== undefined).assertTrue();
      if (us !== undefined) {
        expect(us.code).assertEqual('US');
      }

      const unknown: CountryInfo | undefined = findCountryByDialCode('+99999');
      expect(unknown).assertUndefined();
    });

    it('findCountryByIso_caseInsensitive', 0, () => {
      const cn: CountryInfo | undefined = findCountryByIso('cn');
      expect(cn !== undefined).assertTrue();
      if (cn !== undefined) {
        expect(cn.dialCode).assertEqual('+86');
      }

      const us: CountryInfo | undefined = findCountryByIso('US');
      expect(us !== undefined).assertTrue();
      if (us !== undefined) {
        expect(us.dialCode).assertEqual('+1');
      }

      const invalid: CountryInfo | undefined = findCountryByIso('XYZ');
      expect(invalid).assertUndefined();
    });

    it('formatFullPhoneNumber_cleansNonDigits', 0, () => {
      const formatted: string = formatFullPhoneNumber('+86', '138-0013-8000');
      expect(formatted).assertEqual('+8613800138000');

      const formattedNoPlus: string = formatFullPhoneNumber('86', '(138) 0013 8000');
      expect(formattedNoPlus).assertEqual('+8613800138000');
    });
  });
}
