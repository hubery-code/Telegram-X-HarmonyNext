/**
 * feature/auth — 国家代码与手机号格式化模型（AUTH-001）。
 */

export interface CountryInfo {
  readonly code: string;
  readonly dialCode: string;
  readonly name: string;
}

export const DEFAULT_COUNTRY: CountryInfo = {
  code: 'CN',
  dialCode: '+86',
  name: 'China'
};

export const SUPPORTED_COUNTRIES: CountryInfo[] = [
  { code: 'CN', dialCode: '+86', name: 'China' },
  { code: 'US', dialCode: '+1', name: 'United States' },
  { code: 'GB', dialCode: '+44', name: 'United Kingdom' },
  { code: 'RU', dialCode: '+7', name: 'Russia' },
  { code: 'DE', dialCode: '+49', name: 'Germany' },
  { code: 'FR', dialCode: '+33', name: 'France' },
  { code: 'JP', dialCode: '+81', name: 'Japan' },
  { code: 'KR', dialCode: '+82', name: 'South Korea' },
  { code: 'IN', dialCode: '+91', name: 'India' },
  { code: 'SG', dialCode: '+65', name: 'Singapore' },
  { code: 'AE', dialCode: '+971', name: 'United Arab Emirates' },
  { code: 'BR', dialCode: '+55', name: 'Brazil' },
  { code: 'CA', dialCode: '+1', name: 'Canada' },
  { code: 'AU', dialCode: '+61', name: 'Australia' }
];

export function findCountryByDialCode(dial: string): CountryInfo | undefined {
  const normalized: string = dial.startsWith('+') ? dial : `+${dial}`;
  for (let i = 0; i < SUPPORTED_COUNTRIES.length; i++) {
    if (SUPPORTED_COUNTRIES[i].dialCode === normalized) {
      return SUPPORTED_COUNTRIES[i];
    }
  }
  return undefined;
}

export function findCountryByIso(iso: string): CountryInfo | undefined {
  const upper: string = iso.toUpperCase();
  for (let i = 0; i < SUPPORTED_COUNTRIES.length; i++) {
    if (SUPPORTED_COUNTRIES[i].code === upper) {
      return SUPPORTED_COUNTRIES[i];
    }
  }
  return undefined;
}

export function formatFullPhoneNumber(dialCode: string, rawPhone: string): string {
  const cleanDial: string = dialCode.startsWith('+') ? dialCode : `+${dialCode}`;
  const cleanPhone: string = rawPhone.replace(/\D/g, '');
  return `${cleanDial}${cleanPhone}`;
}
