/**
 * feature/chat — 位置与场所视图模型（LOCATION-MSG-101）。
 *
 * 纯 ArkTS 不可变数据模型，对应 TDLib MessageLocation 与 MessageVenue。
 * 包含经纬度、精度、场所标题、地址及是否为场所标记。
 */

export class LocationCard {
  readonly latitude: number;
  readonly longitude: number;
  readonly horizontalAccuracy: number;
  readonly title: string;
  readonly address: string;
  readonly isVenue: boolean;

  constructor(
    latitude: number,
    longitude: number,
    horizontalAccuracy: number = 0,
    title: string = '',
    address: string = '',
    isVenue: boolean = false
  ) {
    this.latitude = latitude;
    this.longitude = longitude;
    this.horizontalAccuracy = horizontalAccuracy;
    this.title = title;
    this.address = address;
    this.isVenue = isVenue;
  }
}
