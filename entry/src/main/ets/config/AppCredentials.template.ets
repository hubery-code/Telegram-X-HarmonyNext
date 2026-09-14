/**
 * Telegram API credentials template.
 *
 * Real credentials must be injected at build time from local.properties
 * or environment variables (TELEGRAM_API_ID, TELEGRAM_API_HASH).
 * Never commit real credentials to version control.
 */
export interface TelegramCredentials {
  readonly apiId: number;
  readonly apiHash: string;
}

export const TELEGRAM_CREDENTIALS: TelegramCredentials = {
  apiId: 0,
  apiHash: ''
};
