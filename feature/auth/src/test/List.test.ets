import countryCodeTest from './CountryCode.test';
import authReducerTest from './AuthReducer.test';
import authCoordinatorTest from './AuthCoordinator.test';
import authCoordinatorDbKeyTest from './AuthCoordinatorDbKey.test';

export default function testsuite(): void {
  countryCodeTest();
  authReducerTest();
  authCoordinatorTest();
  authCoordinatorDbKeyTest();
}
