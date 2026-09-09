/**
 * 敏感 fixture —— 全部为编造的假值（§14.4：证据/测试中禁止真实数据）。
 * 所有测试断言「这些值绝不出现在日志/脱敏输出中」（secret fixtures 100% 拦截）。
 */

/** （interface 仅用于让 arkts linter 接受字面量；成员即下方各假值。） */
export interface FixtureValues extends Record<string, string> {
  phoneNumber: string;
  phoneMasked: string;
  formattedPhone: string;
  authCode: string;
  recoveryCode: string;
  giftCode: string;
  password: string;
  oldPassword: string;
  newPassword: string;
  passwordHint: string;
  token: string;
  deviceToken: string;
  apiHash: string;
  dbEncryptionKey: string;
  encryptionKey: string;
  proxySecret: string;
  publicToken: string;
  purchaseToken: string;
  proxyUsername: string;
  proxyPassword: string;
  emailAddress: string;
  ipAddress: string;
  firstName: string;
  lastName: string;
  extra: string;
  redacted: string;
}

export const FIXTURES: FixtureValues = {
  // 手机号（假号段，E.164 形态）
  phoneNumber: '+8613901234567',
  phoneMasked: '+86…67',
  formattedPhone: '+86 139 0123 4567',
  // 验证码 / 恢复码
  authCode: '123456',
  recoveryCode: 'fake-recovery-77',
  giftCode: 'gift-fake-88',
  // 密码
  password: 'fake-password-7x',
  oldPassword: 'fake-old-password',
  newPassword: 'fake-new-password',
  passwordHint: 'fake hint no leaks',
  // 令牌 / hash / key（均为假值，且不含 16+ 连续十六进制形态，避免触碰 secret-scan）
  token: 'fake-token-a1b2c3d4e5',
  deviceToken: 'fake-device-token-11223344',
  apiHash: 'fake-apihash-9f8e7d',
  dbEncryptionKey: 'fake-db-key-0123456789',
  encryptionKey: 'fake-e2e-encryption-key',
  proxySecret: 'fake-mtproxy-secret-00',
  publicToken: 'fake-public-token',
  purchaseToken: 'fake-purchase-token',
  // 代理凭据
  proxyUsername: 'proxy-user-fake',
  proxyPassword: 'proxy-pass-fake-00',
  // PII
  emailAddress: 'fake.person@example.invalid',
  ipAddress: '203.0.113.66', // TEST-NET-3 文档保留段
  firstName: 'FakeSan',
  lastName: 'Zhang',
  // @extra 请求关联 id
  extra: 'req-abc123def456ghi',
  // 脱敏占位
  redacted: '\u00ABredacted\u00BB', // «redacted»
};

/** 全部敏感假值——断言输出不含其中任何一个。 */
export const ALL_SECRETS: readonly string[] = [
  FIXTURES.phoneNumber,
  FIXTURES.formattedPhone,
  FIXTURES.authCode,
  FIXTURES.recoveryCode,
  FIXTURES.giftCode,
  FIXTURES.password,
  FIXTURES.oldPassword,
  FIXTURES.newPassword,
  FIXTURES.passwordHint,
  FIXTURES.token,
  FIXTURES.deviceToken,
  FIXTURES.apiHash,
  FIXTURES.dbEncryptionKey,
  FIXTURES.encryptionKey,
  FIXTURES.proxySecret,
  FIXTURES.publicToken,
  FIXTURES.purchaseToken,
  FIXTURES.proxyUsername,
  FIXTURES.proxyPassword,
  FIXTURES.emailAddress,
  FIXTURES.ipAddress,
  FIXTURES.firstName,
  FIXTURES.lastName,
  FIXTURES.extra,
];
