import routeRegistryTest from './RouteRegistry.test';
import routeCodecTest from './RouteCodec.test';
import navigationStackTest from './NavigationStack.test';
import telegramLinkTest from './TelegramLink.test';

export default function testsuite() {
  routeRegistryTest();
  routeCodecTest();
  navigationStackTest();
  telegramLinkTest();
}
