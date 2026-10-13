/**
 * feature/chat — 名片消息视图模型（CONTACT-MSG-101）。
 *
 * 承载名片消息气泡渲染与交互所需的联系人卡片信息，由 messageContact.contact 映射。
 */

/**
 * 优雅计算联系人全名：first_name + ' ' + last_name 去除首尾空白，若为空则回退到 phone_number。
 */
export function formatContactFullName(firstName: string, lastName: string, phoneNumber: string = ''): string {
  const first: string = firstName !== null && firstName !== undefined ? firstName.trim() : '';
  const last: string = lastName !== null && lastName !== undefined ? lastName.trim() : '';
  let full: string = `${first} ${last}`.trim();
  if (full.length === 0) {
    full = phoneNumber !== null && phoneNumber !== undefined ? phoneNumber.trim() : '';
  }
  return full;
}

export class ContactCard {
  readonly firstName: string;
  readonly lastName: string;
  readonly fullName: string;
  readonly phoneNumber: string;
  readonly vcard: string;
  readonly userId: number;

  constructor(
    firstName: string = '',
    lastName: string = '',
    fullName: string = '',
    phoneNumber: string = '',
    vcard: string = '',
    userId: number = 0
  ) {
    this.firstName = firstName;
    this.lastName = lastName;
    this.fullName = fullName.length > 0 ? fullName : formatContactFullName(firstName, lastName, phoneNumber);
    this.phoneNumber = phoneNumber;
    this.vcard = vcard;
    this.userId = userId;
  }
}
