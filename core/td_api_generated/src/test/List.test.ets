import codecRoundTripTest from './CodecRoundTrip.test';
import unknownFallbackTest from './UnknownFallback.test';
import int64PrecisionTest from './Int64Precision.test';
import requestResponseTest from './RequestResponse.test';

export default function testsuite() {
  codecRoundTripTest();
  unknownFallbackTest();
  int64PrecisionTest();
  requestResponseTest();
}
